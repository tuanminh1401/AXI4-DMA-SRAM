module dma_write_master #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter FF_DEPTH = 16
)(
    input logic                     clk,
    input logic                     rst_n,

    //Signal from DMA Controller (CSR)
    input logic                     start_tx,
    input logic [ADDR_WIDTH-1:0]    dst_addr,                           //Address to push data into axi slave sram
    input logic [7:0]               burst_len,                          //Number of beat want to sent to axi slave sram
    output logic                    tx_done,                            //Done write
    output logic                    busy,                               //In write process

    //Connect to dma_fifo
    input logic [DATA_WIDTH-1:0]    fifo_rdata,                         //Data from fifo
    input logic                     fifo_empty,                         //Empty flag from fifo
    input logic [$clog2(FF_DEPTH):0] fifo_count,    
    output logic                    fifo_rd_en,

    //AW
    output logic [ADDR_WIDTH-1:0]   m_axi_awaddr,
    output logic [7:0]              m_axi_awlen,
    output logic [2:0]              m_axi_awsize,
    output logic [1:0]              m_axi_awburst,
    output logic                    m_axi_awvalid,
    input logic                     m_axi_awready,
    
    //W
    output logic [DATA_WIDTH-1:0]   m_axi_wdata,
    output logic [DATA_WIDTH/8-1:0] m_axi_wstrb,
    output logic                    m_axi_wlast,
    output logic                    m_axi_wvalid,
    input logic                     m_axi_wready,

    //B (response)
    input logic [1:0]               m_axi_bresp,
    input logic                     m_axi_bvalid,
    output logic                    m_axi_bready
);
    typedef enum logic [1:0] {IDLE, WAIT_AW, WAIT_W, WAIT_B} fsm;
    fsm state, next_state;
    logic [7:0]                     beat_cnt;                                               //count number of beat sent
    logic [ADDR_WIDTH-1:0]          addr_reg;                                               //internal Reg
    logic [7:0]                     len_reg;          

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            beat_cnt    <= '0;
            addr_reg    <= '0;
            len_reg     <= '0;
        end else begin
            state <= next_state;

            if (state == IDLE && start_tx && (fifo_count >= burst_len) && (burst_len > 0)) begin
                addr_reg <= dst_addr;
                len_reg <= burst_len;
                beat_cnt <= '0;
            end else if (state == WAIT_W && m_axi_wvalid && m_axi_wready) begin
                beat_cnt <= beat_cnt + 1'b1;
            end
        end
    end

    always_comb begin
        next_state = state;
        m_axi_awvalid = '0;
        m_axi_wvalid = '0;
        m_axi_bready = '0;
        m_axi_wlast = '0;
        tx_done = '0;

        case (state)
            IDLE: begin
                if (start_tx && (fifo_count >= burst_len) && (burst_len > 0)) begin
                    next_state = WAIT_AW;
                end
            end

            WAIT_AW: begin
                m_axi_awvalid = 1'b1;
                if (m_axi_awvalid && m_axi_awready) begin
                    next_state = WAIT_W;
                end
            end

            WAIT_W: begin
                m_axi_wvalid = 1'b1;
                if (beat_cnt == len_reg - 1'b1) begin
                    m_axi_wlast = 1'b1;
                end            
                if (m_axi_wvalid && m_axi_wready) begin
                    if (beat_cnt == len_reg - 1'b1) begin
                        next_state = WAIT_B;
                    end
                end
            end

            WAIT_B: begin
                m_axi_bready = 1'b1;
                if (m_axi_bvalid && m_axi_bready) begin
                    tx_done = 1'b1;
                    next_state = IDLE;
                end
            end
            default: next_state = IDLE;
        endcase
    end

    assign fifo_rd_en       = (state == WAIT_AW && m_axi_awvalid && m_axi_awready) || (state == WAIT_W  && m_axi_wvalid  && m_axi_wready && (beat_cnt < len_reg - 1'b1));
    assign m_axi_awaddr     = addr_reg;
    assign m_axi_awlen      = (len_reg > 0) ? (len_reg - 1'b1) : 8'd0;
    assign m_axi_awsize     = 3'b010;
    assign m_axi_awburst    = 2'b01;
    assign m_axi_wdata      = fifo_rdata;
    assign m_axi_wstrb      = {(DATA_WIDTH/8){1'b1}};
    assign busy             = (state != IDLE);
endmodule