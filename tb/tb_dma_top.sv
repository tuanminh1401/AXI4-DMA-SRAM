`timescale 1ns / 1ps

module tb_dma_top;

    // =========================================================================
    // 1. PARAMETERS & SIGNALS
    // =========================================================================
    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 32;
    localparam FF_DEPTH   = 16;
    localparam CLK_PERIOD = 10; // 100 MHz clock

    // CSR Register Offsets
    localparam [4:0] ADDR_DMA_CTRL      = 5'h00;
    localparam [4:0] ADDR_DMA_STATUS    = 5'h04;
    localparam [4:0] ADDR_DMA_SRC_ADDR  = 5'h08;
    localparam [4:0] ADDR_DMA_DST_ADDR  = 5'h0C;
    localparam [4:0] ADDR_DMA_BURST_LEN = 5'h10;

    // Clock & Reset
    logic clk;
    logic rst_n;

    // AXI-Lite Slave Interface (CPU -> dma_top)
    logic [ADDR_WIDTH-1:0] s_axil_awaddr;
    logic                  s_axil_awvalid;
    logic                  s_axil_awready;
    logic [DATA_WIDTH-1:0] s_axil_wdata;
    logic                  s_axil_wvalid;
    logic                  s_axil_wready;
    logic [1:0]            s_axil_bresp;
    logic                  s_axil_bvalid;
    logic                  s_axil_bready;
    logic [ADDR_WIDTH-1:0] s_axil_araddr;
    logic                  s_axil_arvalid;
    logic                  s_axil_arready;
    logic [DATA_WIDTH-1:0] s_axil_rdata;
    logic [1:0]            s_axil_rresp;
    logic                  s_axil_rvalid;
    logic                  s_axil_rready;

    // AXI4 Read Master Interface (dma_top -> Source RAM)
    logic [ADDR_WIDTH-1:0] m_axi_araddr;
    logic [7:0]            m_axi_arlen;
    logic [2:0]            m_axi_arsize;
    logic [1:0]            m_axi_arburst;
    logic                  m_axi_arvalid;
    logic                  m_axi_arready;
    logic [DATA_WIDTH-1:0] m_axi_rdata;
    logic                  m_axi_rlast;
    logic                  m_axi_rvalid;
    logic [1:0]            m_axi_rresp;
    logic                  m_axi_rready;

    // AXI4 Write Master Interface (dma_top -> Dest SRAM)
    logic [ADDR_WIDTH-1:0] m_axi_awaddr;
    logic [7:0]            m_axi_awlen;
    logic [2:0]            m_axi_awsize;
    logic [1:0]            m_axi_awburst;
    logic                  m_axi_awvalid;
    logic                  m_axi_awready;
    logic [DATA_WIDTH-1:0] m_axi_wdata;
    logic [DATA_WIDTH/8-1:0] m_axi_wstrb;
    logic                  m_axi_wlast;
    logic                  m_axi_wvalid;
    logic                  m_axi_wready;
    logic [1:0]            m_axi_bresp;
    logic                  m_axi_bvalid;
    logic                  m_axi_bready;

    // Interrupt
    logic                  irq;

    // Testbench Variables & Simulated Memories
    logic [DATA_WIDTH-1:0] src_ram [0:255];
    logic [DATA_WIDTH-1:0] dst_ram [0:255];
    int error_count = 0;

    // =========================================================================
    // 2. DUT INSTANTIATION
    // =========================================================================
    dma_top #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .FF_DEPTH   (FF_DEPTH)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),

        // AXI-Lite Slave
        .s_axil_awaddr  (s_axil_awaddr),
        .s_axil_awvalid (s_axil_awvalid),
        .s_axil_awready (s_axil_awready),
        .s_axil_wdata   (s_axil_wdata),
        .s_axil_wvalid  (s_axil_wvalid),
        .s_axil_wready  (s_axil_wready),
        .s_axil_bresp   (s_axil_bresp),
        .s_axil_bvalid  (s_axil_bvalid),
        .s_axil_bready  (s_axil_bready),
        .s_axil_araddr  (s_axil_araddr),
        .s_axil_arvalid (s_axil_arvalid),
        .s_axil_arready (s_axil_arready),
        .s_axil_rdata   (s_axil_rdata),
        .s_axil_rresp   (s_axil_rresp),
        .s_axil_rvalid  (s_axil_rvalid),
        .s_axil_rready  (s_axil_rready),

        // AXI4 Read Master
        .m_axi_araddr   (m_axi_araddr),
        .m_axi_arlen    (m_axi_arlen),
        .m_axi_arsize   (m_axi_arsize),
        .m_axi_arburst  (m_axi_arburst),
        .m_axi_arvalid  (m_axi_arvalid),
        .m_axi_arready  (m_axi_arready),
        .m_axi_rdata    (m_axi_rdata),
        .m_axi_rlast    (m_axi_rlast),
        .m_axi_rvalid   (m_axi_rvalid),
        .m_axi_rresp    (m_axi_rresp),
        .m_axi_rready   (m_axi_rready),

        // AXI4 Write Master
        .m_axi_awaddr   (m_axi_awaddr),
        .m_axi_awlen    (m_axi_awlen),
        .m_axi_awsize   (m_axi_awsize),
        .m_axi_awburst  (m_axi_awburst),
        .m_axi_awvalid  (m_axi_awvalid),
        .m_axi_awready  (m_axi_awready),
        .m_axi_wdata    (m_axi_wdata),
        .m_axi_wstrb    (m_axi_wstrb),
        .m_axi_wlast    (m_axi_wlast),
        .m_axi_wvalid   (m_axi_wvalid),
        .m_axi_wready   (m_axi_wready),
        .m_axi_bresp    (m_axi_bresp),
        .m_axi_bvalid   (m_axi_bvalid),
        .m_axi_bready   (m_axi_bready),

        // Interrupt
        .irq            (irq)
    );

    // =========================================================================
    // 3. CLOCK GENERATOR
    // =========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // =========================================================================
    // 4. AXI4 SLAVE RESPONDER MODELS
    // =========================================================================

    // Model: Source RAM AXI4 Read Slave Responder
    logic [7:0] r_len_latched;
    logic [7:0] r_beat_cnt;
    logic [7:0] r_word_idx;
    logic       r_busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_arready <= 1'b0;
            m_axi_rvalid  <= 1'b0;
            m_axi_rlast   <= 1'b0;
            m_axi_rdata   <= '0;
            m_axi_rresp   <= 2'b00;
            r_len_latched <= '0;
            r_beat_cnt    <= '0;
            r_word_idx    <= '0;
            r_busy        <= 1'b0;
        end else begin
            if (!r_busy) begin
                m_axi_arready <= 1'b1;
                if (m_axi_arvalid && m_axi_arready) begin
                    m_axi_arready <= 1'b0;
                    r_busy        <= 1'b1;
                    r_len_latched <= m_axi_arlen;
                    r_word_idx    <= m_axi_araddr[9:2]; // Địa chỉ theo word
                    r_beat_cnt    <= '0;
                    m_axi_rvalid  <= 1'b1;
                    m_axi_rdata   <= src_ram[m_axi_araddr[9:2]];
                    m_axi_rlast   <= (m_axi_arlen == 8'd0);
                end
            end else begin
                m_axi_arready <= 1'b0;
                if (m_axi_rvalid && m_axi_rready) begin
                    if (r_beat_cnt == r_len_latched) begin
                        m_axi_rvalid <= 1'b0;
                        m_axi_rlast  <= 1'b0;
                        r_busy       <= 1'b0;
                    end else begin
                        r_beat_cnt  <= r_beat_cnt + 1'b1;
                        m_axi_rdata <= src_ram[r_word_idx + r_beat_cnt + 1'b1];
                        if (r_beat_cnt + 1'b1 == r_len_latched) begin
                            m_axi_rlast <= 1'b1;
                        end
                    end
                end
            end
        end
    end

    // Model: Destination SRAM AXI4 Write Slave Responder
    logic [7:0] w_word_idx;
    logic       w_busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_awready <= 1'b0;
            m_axi_wready  <= 1'b0;
            m_axi_bvalid  <= 1'b0;
            m_axi_bresp   <= 2'b00;
            w_word_idx    <= '0;
            w_busy        <= 1'b0;
        end else begin
            if (!w_busy) begin
                m_axi_awready <= 1'b1;
                if (m_axi_awvalid && m_axi_awready) begin
                    m_axi_awready <= 1'b0;
                    w_busy        <= 1'b1;
                    w_word_idx    <= m_axi_awaddr[9:2];
                    m_axi_wready  <= 1'b1;
                end
            end else begin
                m_axi_awready <= 1'b0;
                if (m_axi_wvalid && m_axi_wready) begin
                    dst_ram[w_word_idx] <= m_axi_wdata;
                    w_word_idx          <= w_word_idx + 1'b1;
                    if (m_axi_wlast) begin
                        m_axi_wready <= 1'b0;
                        m_axi_bvalid <= 1'b1;
                        m_axi_bresp  <= 2'b00;
                    end
                end

                if (m_axi_bvalid && m_axi_bready) begin
                    m_axi_bvalid <= 1'b0;
                    w_busy       <= 1'b0;
                end
            end
        end
    end

    // =========================================================================
    // 5. AXI-LITE MASTER CPU TASKS
    // =========================================================================
    task automatic axi_write(input [ADDR_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] data);
        @(posedge clk);
        s_axil_awaddr  <= addr;
        s_axil_wdata   <= data;
        s_axil_awvalid <= 1'b1;
        s_axil_wvalid  <= 1'b1;
        s_axil_bready  <= 1'b1;

        wait(s_axil_awready && s_axil_wready);
        @(posedge clk);
        s_axil_awvalid <= 1'b0;
        s_axil_wvalid  <= 1'b0;

        wait(s_axil_bvalid);
        @(posedge clk);
        s_axil_bready  <= 1'b0;
    endtask

    task automatic axi_read(input [ADDR_WIDTH-1:0] addr, output [DATA_WIDTH-1:0] data);
        @(posedge clk);
        s_axil_araddr  <= addr;
        s_axil_arvalid <= 1'b1;
        s_axil_rready  <= 1'b1;

        wait(s_axil_arready);
        @(posedge clk);
        s_axil_arvalid <= 1'b0;

        wait(s_axil_rvalid);
        data = s_axil_rdata;
        @(posedge clk);
        s_axil_rready  <= 1'b0;
    endtask

    // =========================================================================
    // 6. MAIN TEST SCENARIO
    // =========================================================================
    logic [DATA_WIDTH-1:0] rdata;

    initial begin
        // Khởi tạo Reset và bus AXI-Lite
        rst_n          = 1'b0;
        s_axil_awaddr  = '0;
        s_axil_wdata   = '0;
        s_axil_awvalid = 1'b0;
        s_axil_wvalid  = 1'b0;
        s_axil_bready  = 1'b0;
        s_axil_araddr  = '0;
        s_axil_arvalid = 1'b0;
        s_axil_rready  = 1'b0;

        // Nạp dữ liệu mẫu vào Source RAM (không gán vào dst_ram để tránh lỗi multi-driver)
        for (int i = 0; i < 256; i++) begin
            src_ram[i] = 32'hA000_0000 + i;
        end

        $display("============================================================");
        $display("           STARTING DMA_TOP FULL-SYSTEM VERIFICATION        ");
        $display("============================================================");

        // -------------------------------------------------------------
        // STEP 1: RESET SEQUENCE
        // -------------------------------------------------------------
        #(CLK_PERIOD * 4);
        rst_n = 1'b1;
        #(CLK_PERIOD * 2);
        $display("[STEP 1 PASS] Reset released. System initialized.");

        // -------------------------------------------------------------
        // STEP 2: CONFIGURE DMA VIA AXI-LITE
        // -------------------------------------------------------------
        $display("\n--- STEP 2: Programming DMA Configuration Registers ---");
        // Địa chỉ nguồn: 0x0000_0000 (Index 0 trong RAM)
        axi_write(ADDR_DMA_SRC_ADDR, 32'h0000_0000);
        // Địa chỉ đích: 0x0000_0040 (Index 16 trong SRAM)
        axi_write(ADDR_DMA_DST_ADDR, 32'h0000_0040);
        // Độ dài burst: 16 beats (0x10)
        axi_write(ADDR_DMA_BURST_LEN, 32'h0000_0010);

        $display("[PASS] Programmed SRC=0x00, DST=0x40, BURST_LEN=16 beats.");

        // -------------------------------------------------------------
        // STEP 3: START DMA TRANSFER (START=1, IE=1)
        // -------------------------------------------------------------
        $display("\n--- STEP 3: Triggering DMA Transfer & Monitoring Bus ---");
        axi_write(ADDR_DMA_CTRL, 32'h0000_0003);

        // -------------------------------------------------------------
        // STEP 4: WAIT FOR HARDWARE COMPLETION & INTERRUPT
        // -------------------------------------------------------------
        fork
            begin
                wait(irq === 1'b1);
                $display("[PASS] Hardware IRQ asserted high upon transfer completion!");
            end
            begin
                #(CLK_PERIOD * 300); // Giới hạn timeout 3us
                $error("[FAIL] Simulation Timeout! DMA transfer failed to complete.");
                error_count++;
            end
        join_any
        disable fork;

        // -------------------------------------------------------------
        // STEP 5: VERIFY MEMORY DATA INTEGRITY
        // -------------------------------------------------------------
        $display("\n--- STEP 5: Verifying Destination Memory Integrity ---");
        for (int i = 0; i < 16; i++) begin
            if (dst_ram[16 + i] === src_ram[i]) begin
                $display("  [MATCH] Word %02d: 0x%08h == 0x%08h", i, dst_ram[16 + i], src_ram[i]);
            end else begin
                $error("  [MISMATCH] Word %02d: Got 0x%08h, Expected 0x%08h", i, dst_ram[16 + i], src_ram[i]);
                error_count++;
            end
        end

        // -------------------------------------------------------------
        // STEP 6: VERIFY STATUS AND CLEAR INTERRUPT (W1C)
        // -------------------------------------------------------------
        $display("\n--- STEP 6: Verifying CSR Status & Acknowledging IRQ ---");
        axi_read(ADDR_DMA_STATUS, rdata);
        if (rdata[1:0] === 2'b10)
            $display("[PASS] DMA_STATUS: DONE=1, BUSY=0 as expected.");
        else begin
            $error("[FAIL] Unexpected status! Read: 0x%08h", rdata);
            error_count++;
        end

        // Xóa cờ DONE bằng cơ chế W1C
        axi_write(ADDR_DMA_STATUS, 32'h0000_0002);

        // Kiểm tra hạ ngắt IRQ
        if (irq === 1'b0)
            $display("[PASS] IRQ line successfully cleared to 0.");
        else begin
            $error("[FAIL] IRQ line remained asserted at 1!");
            error_count++;
        end

        // Kiểm tra bit DONE đã bị dập về 0
        axi_read(ADDR_DMA_STATUS, rdata);
        if (rdata[1] === 1'b0)
            $display("[PASS] DONE bit confirmed cleared to 0.");
        else begin
            $error("[FAIL] DONE bit not cleared! Read: 0x%08h", rdata);
            error_count++;
        end

        // -------------------------------------------------------------
        // FINAL VERDICT
        // -------------------------------------------------------------
        #(CLK_PERIOD * 5);
        $display("\n============================================================");
        if (error_count == 0)
            $display(">>> FINAL VERDICT: ALL DMA_TOP TESTS PASSED SUCCESSFULLY! <<<");
        else
            $display(">>> FINAL VERDICT: %0d ERROR(S) DETECTED IN DMA_TOP! <<<", error_count);
        $display("============================================================\n");
        $finish;
    end

endmodule