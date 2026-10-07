module dma_top #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter FF_DEPTH   = 16
)(
    input  logic                          clk,
    input  logic                          rst_n,

    // =========================================================================
    // 1. AXI-LITE SLAVE INTERFACE (Kết nối CPU điều khiển CSR)
    // =========================================================================
    // Write Address Channel (AW)
    input  logic [ADDR_WIDTH-1:0]         s_axil_awaddr,
    input  logic                          s_axil_awvalid,
    output logic                          s_axil_awready,

    // Write Data Channel (W)
    input  logic [DATA_WIDTH-1:0]         s_axil_wdata,
    input  logic                          s_axil_wvalid,
    output logic                          s_axil_wready,

    // Write Response Channel (B)
    output logic [1:0]                    s_axil_bresp,
    output logic                          s_axil_bvalid,
    input  logic                          s_axil_bready,

    // Read Address Channel (AR)
    input  logic [ADDR_WIDTH-1:0]         s_axil_araddr,
    input  logic                          s_axil_arvalid,
    output logic                          s_axil_arready,

    // Read Data Channel (R)
    output logic [DATA_WIDTH-1:0]         s_axil_rdata,
    output logic [1:0]                    s_axil_rresp,
    output logic                          s_axil_rvalid,
    input  logic                          s_axil_rready,

    // =========================================================================
    // 2. AXI4 MASTER READ INTERFACE (Kết nối RAM nguồn)
    // =========================================================================
    output logic [ADDR_WIDTH-1:0]         m_axi_araddr,
    output logic [7:0]                    m_axi_arlen,
    output logic [2:0]                    m_axi_arsize,
    output logic [1:0]                    m_axi_arburst,
    output logic                          m_axi_arvalid,
    input  logic                          m_axi_arready,

    input  logic [DATA_WIDTH-1:0]         m_axi_rdata,
    input  logic                          m_axi_rlast,
    input  logic                          m_axi_rvalid,
    input  logic [1:0]                    m_axi_rresp,
    output logic                          m_axi_rready,

    // =========================================================================
    // 3. AXI4 MASTER WRITE INTERFACE (Kết nối SRAM/Ngoại vi đích)
    // =========================================================================
    output logic [ADDR_WIDTH-1:0]         m_axi_awaddr,
    output logic [7:0]                    m_axi_awlen,
    output logic [2:0]                    m_axi_awsize,
    output logic [1:0]                    m_axi_awburst,
    output logic                          m_axi_awvalid,
    input  logic                          m_axi_awready,

    output logic [DATA_WIDTH-1:0]         m_axi_wdata,
    output logic [DATA_WIDTH/8-1:0]       m_axi_wstrb,
    output logic                          m_axi_wlast,
    output logic                          m_axi_wvalid,
    input  logic                          m_axi_wready,

    input  logic [1:0]                    m_axi_bresp,
    input  logic                          m_axi_bvalid,
    output logic                          m_axi_bready,

    // =========================================================================
    // 4. INTERRUPT SIGNAL (Báo ngắt CPU khi DMA truyền xong)
    // =========================================================================
    output logic                          irq
);

    // =========================================================================
    // DÂY NỐI NỘI BỘ (INTERNAL INTERCONNECT WIRES)
    // =========================================================================
    // CSR <--> Masters
    logic [ADDR_WIDTH-1:0]     src_addr;
    logic [ADDR_WIDTH-1:0]     dst_addr;
    logic [7:0]                burst_len;
    logic                      start_rx;
    logic                      start_tx;
    logic                      rx_done;
    logic                      tx_done;
    logic                      read_busy;
    logic                      write_busy;

    // FIFO <--> Masters
    logic [DATA_WIDTH-1:0]     fifo_wdata;
    logic                      fifo_wr_en;
    logic                      fifo_full;

    logic [DATA_WIDTH-1:0]     fifo_rdata;
    logic                      fifo_rd_en;
    logic                      fifo_empty;

    logic [$clog2(FF_DEPTH):0] fifo_count;

    // =========================================================================
    // 1. INSTANTIATION: DMA CONTROL & STATUS REGISTERS (dma_csr)
    // =========================================================================
    dma_csr #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_dma_csr (
        .clk            (clk),
        .rst_n          (rst_n),

        // AXI-Lite Write Channel
        .s_axil_awaddr  (s_axil_awaddr),
        .s_axil_wdata   (s_axil_wdata),
        .s_axil_awvalid (s_axil_awvalid),
        .s_axil_wvalid  (s_axil_wvalid),
        .s_axil_bready  (s_axil_bready),
        .s_axil_awready (s_axil_awready),
        .s_axil_wready  (s_axil_wready),
        .s_axil_bvalid  (s_axil_bvalid),
        .s_axil_bresp   (s_axil_bresp),

        // AXI-Lite Read Channel
        .s_axil_araddr  (s_axil_araddr),
        .s_axil_rdata   (s_axil_rdata),
        .s_axil_arvalid (s_axil_arvalid),
        .s_axil_rready  (s_axil_rready),
        .s_axil_rresp   (s_axil_rresp),
        .s_axil_arready (s_axil_arready),
        .s_axil_rvalid  (s_axil_rvalid),

        // Master Control & Status
        .src_addr       (src_addr),
        .dst_addr       (dst_addr),
        .burst_len      (burst_len),
        .start_rx       (start_rx),
        .start_tx       (start_tx),
        .rx_done        (rx_done),
        .tx_done        (tx_done),
        .read_busy      (read_busy),
        .write_busy     (write_busy),

        // CPU Interrupt
        .irq            (irq)
    );

    // =========================================================================
    // 2. INSTANTIATION: DMA INTERNAL BUFFER (dma_fifo)
    // =========================================================================
    dma_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .FF_DEPTH   (FF_DEPTH)
        // ADDR_WIDTH tự động lấy mặc định $clog2(FF_DEPTH)
    ) u_dma_fifo (
        .clk        (clk),
        .rst_n      (rst_n),

        // Cổng ghi từ Read Master
        .wr_en      (fifo_wr_en),
        .wr_data    (fifo_wdata),
        .full       (fifo_full),

        // Cổng đọc từ Write Master
        .rd_en      (fifo_rd_en),
        .rd_data    (fifo_rdata),
        .empty      (fifo_empty),

        // Giám sát dung lượng
        .fifo_count (fifo_count)
    );

    // =========================================================================
    // 3. INSTANTIATION: DMA AXI4 READ MASTER (dma_read_master)
    // =========================================================================
    dma_read_master #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .FF_DEPTH   (FF_DEPTH)
    ) u_dma_read_master (
        .clk           (clk),
        .rst_n         (rst_n),

        // Điều khiển từ CSR
        .start_rx      (start_rx),
        .src_addr      (src_addr),
        .burst_len     (burst_len),
        .rx_done       (rx_done),
        .busy          (read_busy),

        // Đẩy dữ liệu vào FIFO
        .fifo_wdata    (fifo_wdata),
        .fifo_full     (fifo_full),
        .fifo_count    (fifo_count),
        .fifo_wr_en    (fifo_wr_en),

        // Bus AXI4 Read Address (AR)
        .m_axi_araddr  (m_axi_araddr),
        .m_axi_arlen   (m_axi_arlen),
        .m_axi_arsize  (m_axi_arsize),
        .m_axi_arburst (m_axi_arburst),
        .m_axi_arvalid (m_axi_arvalid),
        .m_axi_arready (m_axi_arready),

        // Bus AXI4 Read Data (R)
        .m_axi_rdata   (m_axi_rdata),
        .m_axi_rlast   (m_axi_rlast),
        .m_axi_rvalid  (m_axi_rvalid),
        .m_axi_rresp   (m_axi_rresp),
        .m_axi_rready  (m_axi_rready)
    );

    // =========================================================================
    // 4. INSTANTIATION: DMA AXI4 WRITE MASTER (dma_write_master)
    // =========================================================================
    dma_write_master #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .FF_DEPTH   (FF_DEPTH)
    ) u_dma_write_master (
        .clk           (clk),
        .rst_n         (rst_n),

        // Điều khiển từ CSR
        .start_tx      (start_tx),
        .dst_addr      (dst_addr),
        .burst_len     (burst_len),
        .tx_done       (tx_done),
        .busy          (write_busy),

        // Lấy dữ liệu từ FIFO
        .fifo_rdata    (fifo_rdata),
        .fifo_empty    (fifo_empty),
        .fifo_count    (fifo_count),
        .fifo_rd_en    (fifo_rd_en),

        // Bus AXI4 Write Address (AW)
        .m_axi_awaddr  (m_axi_awaddr),
        .m_axi_awlen   (m_axi_awlen),
        .m_axi_awsize  (m_axi_awsize),
        .m_axi_awburst (m_axi_awburst),
        .m_axi_awvalid (m_axi_awvalid),
        .m_axi_awready (m_axi_awready),

        // Bus AXI4 Write Data (W)
        .m_axi_wdata   (m_axi_wdata),
        .m_axi_wstrb   (m_axi_wstrb),
        .m_axi_wlast   (m_axi_wlast),
        .m_axi_wvalid  (m_axi_wvalid),
        .m_axi_wready  (m_axi_wready),

        // Bus AXI4 Write Response (B)
        .m_axi_bresp   (m_axi_bresp),
        .m_axi_bvalid  (m_axi_bvalid),
        .m_axi_bready  (m_axi_bready)
    );

endmodule