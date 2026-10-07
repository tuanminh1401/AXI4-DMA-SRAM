module dma_csr #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input logic                     clk,
    input logic                     rst_n,

    //WRITE CHANNEL
    //CPU sent to dma_csr
    input logic [ADDR_WIDTH-1:0]    s_axil_awaddr,
    input logic [DATA_WIDTH-1:0]    s_axil_wdata,
    input logic                     s_axil_awvalid,
    input logic                     s_axil_wvalid,
    input logic                     s_axil_bready,

    //Response to CPU
    output logic                    s_axil_awready,
    output logic                    s_axil_wready,
    output logic                    s_axil_bvalid,
    output logic [1:0]              s_axil_bresp,

    //READ CHANNEL
    //CPU sent to dm_csr
    input logic [ADDR_WIDTH-1:0]    s_axil_araddr,
    output logic [DATA_WIDTH-1:0]   s_axil_rdata,
    input logic                     s_axil_arvalid,
    input logic                     s_axil_rready,
    output logic [1:0]              s_axil_rresp,

    //Response to CPU
    output logic                    s_axil_arready,
    output logic                    s_axil_rvalid,

    //Connect to read_master and write_master 
    output logic [ADDR_WIDTH-1:0]   src_addr,                           //connect to src_addr of dma_read
    output logic [ADDR_WIDTH-1:0]   dst_addr,                           //connect to dst_addr of dma_write
    output logic [7:0]              burst_len,          
    output logic                    start_rx,                           
    output logic                    start_tx,
    input logic                     rx_done,
    input logic                     tx_done,
    input logic                     read_busy, 
    input logic                     write_busy, 

    //Interupt to CPU after complete
    output logic                    irq
);
    //function register
    localparam [4:0] DMA_CTRL       = 5'h00;                        //bit0: start, bit1: interupt
    localparam [4:0] DMA_STATUS     = 5'h04;                        //bit0: busy, bit1: done
    localparam [4:0] DMA_SRC_ADDR   = 5'h08;                        //m_axi_araddr (read_master)
    localparam [4:0] DMA_DST_ADDR   = 5'h0C;                        //m_axi_awaddr (write_master)     
    localparam [4:0] DMA_BURST_LEN  = 5'h10;                        //burst_len    

    //internal register
    logic [ADDR_WIDTH-1:0]  reg_src_addr;                           //address of internal memory to read_master
    logic [ADDR_WIDTH-1:0]  reg_dst_addr;                           //address of SRAM provide to write_master
    logic [7:0]             reg_burst_len;                           
    logic                   reg_ie;                                 //interupt
    logic                   reg_busy;
    logic                   reg_done;

    //pulse
    logic                   start_pulse;                            //write into bit0 of DMA_CTRL to connect to start_rx
    logic                   aw_en;                                  //0: block write while write another data to avoid overwrite
    
    //WRITE CHANNEL
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_awready  <= '0;
            s_axil_wready   <= '0;
            s_axil_bvalid   <= '0;
            s_axil_bresp    <= 2'b00;
            aw_en           <= 1'b1;
            reg_src_addr    <= '0;
            reg_dst_addr    <= '0;
            reg_burst_len   <= '0;
            reg_ie          <= '0;
            reg_busy        <= '0;
            reg_done        <= '0;
            start_pulse     <= '0;
        end else begin
            start_pulse <= '0;
            if (tx_done) begin
                reg_done <= 1'b1;
                reg_busy <= 1'b0;
            end
            if (~s_axil_awready && s_axil_awvalid && s_axil_wvalid && aw_en) begin
                s_axil_awready <= 1'b1;
                s_axil_wready <= 1'b1;
                aw_en <= 1'b0;

                case (s_axil_awaddr[4:0])
                    DMA_CTRL: begin
                        if (s_axil_wdata[0] && !reg_busy) begin
                            start_pulse <= 1'b1;    
                            reg_busy    <= 1'b1;
                        end
                        reg_ie <= s_axil_wdata[1];
                    end

                    DMA_STATUS: begin
                        if (s_axil_wdata[1] && !tx_done) begin
                            reg_done <= 1'b0;
                        end
                    end

                    DMA_SRC_ADDR: begin
                        reg_src_addr <= s_axil_wdata;
                    end

                    DMA_DST_ADDR: begin
                        reg_dst_addr <= s_axil_wdata;
                    end

                    DMA_BURST_LEN: begin
                        reg_burst_len <= s_axil_wdata[7:0]; 
                    end
                    default:;
                endcase
            end else begin
                s_axil_awready <= 1'b0; 
                s_axil_wready <= 1'b0;
            end

            if (s_axil_awready && s_axil_wready && ~s_axil_bvalid) begin
                s_axil_bvalid <= 1'b1;
                s_axil_bresp <= 2'b00;
            end else if (s_axil_bvalid && s_axil_bready) begin
                s_axil_bvalid <= 1'b0;
                aw_en <= 1'b1;
            end
        end
    end

    //READ CHANNEL
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_arready <= 1'b0;
            s_axil_rvalid  <= 1'b0;
            s_axil_rresp   <= 2'b00;
            s_axil_rdata   <= '0;
        end else begin
            if (!s_axil_arready && s_axil_arvalid && ~s_axil_rvalid) begin
                s_axil_arready <= 1'b1;
                s_axil_rvalid <= 1'b1;
                s_axil_rresp <= 2'b00;

                case (s_axil_araddr[4:0])
                    DMA_CTRL: begin
                        s_axil_rdata <= {30'd0, reg_ie, 1'b0};
                    end

                    DMA_STATUS: begin
                        s_axil_rdata <= {30'd0, reg_done, (reg_busy | read_busy | write_busy)};
                    end

                    DMA_SRC_ADDR: begin
                        s_axil_rdata <= reg_src_addr;
                    end

                    DMA_DST_ADDR: begin
                        s_axil_rdata <= reg_dst_addr;
                    end

                    DMA_BURST_LEN: begin
                        s_axil_rdata <= {24'd0, reg_burst_len}; 
                    end
                    default: s_axil_rdata <= '0;
                endcase
            end else begin
                s_axil_arready <= 1'b0;
            end

            if (s_axil_rvalid && s_axil_rready) begin
                    s_axil_rvalid <= 1'b0;
            end
        end
    end

    assign src_addr = reg_src_addr;
    assign dst_addr = reg_dst_addr;
    assign burst_len = reg_burst_len;

    assign start_rx = start_pulse;
    assign start_tx = reg_busy;
    assign irq = reg_done & reg_ie;    

endmodule