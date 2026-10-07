module dma_read_master #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter FF_DEPTH = 16
)(
    input logic                     clk,
    input logic                     rst_n,

    //Signal from DMA Controller (CSR)
    input logic                     start_rx,
    input logic [ADDR_WIDTH-1:0]    src_addr,                           //Address to push data into axi slave sram
    input logic [7:0]               burst_len,                          //Number of beat want to sent to axi slave sram
    output logic                    rx_done,                            //Done write
    output logic                    busy,                               //In write process

    //Connect to dma_fifo
    output logic [DATA_WIDTH-1:0]    fifo_wdata,                         //Data from fifo
    input logic                     fifo_full,                         //Empty flag from fifo
    input logic [$clog2(FF_DEPTH):0] fifo_count,
    output logic                    fifo_wr_en,

    //AR
    output logic [ADDR_WIDTH-1:0]   m_axi_araddr,
    output logic [7:0]              m_axi_arlen,
    output logic [2:0]              m_axi_arsize,
    output logic [1:0]              m_axi_arburst,
    output logic                    m_axi_arvalid,
    input logic                     m_axi_arready,
    
    //R
    input logic [DATA_WIDTH-1:0]    m_axi_rdata,
    input logic                     m_axi_rlast,
    input logic                     m_axi_rvalid,
    input logic [1:0]               m_axi_rresp,
    output logic                    m_axi_rready
);
    typedef enum logic [1:0] {IDLE, WAIT_AR, WAIT_R} fsm;
    fsm state, next_state;
    logic [ADDR_WIDTH-1:0]          addr_reg;                                               //internal Reg
    logic [7:0]                     len_reg;   
    logic                           start_reg;       

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            addr_reg    <= '0;
            len_reg     <= '0;
            start_reg   <= '0;
        end else begin
            state <= next_state;
            if (start_rx) begin
                addr_reg <= src_addr;
                len_reg <= burst_len;
            end 
            if (next_state == WAIT_AR) begin
                start_reg <= 1'b0;
            end else if (start_rx) begin
                start_reg <= 1'b1;
            end
        end
    end

    always_comb begin
        next_state = state;
        m_axi_arvalid = '0;
        m_axi_rready = '0;
        rx_done = '0;

        case (state)
            IDLE: begin
                if ((start_rx || start_reg) && ((FF_DEPTH - fifo_count) >= (start_rx ? burst_len : len_reg)) && ((start_rx ? burst_len : len_reg) > 0)) begin
                    next_state = WAIT_AR;
                end
            end

            WAIT_AR: begin
                m_axi_arvalid = 1'b1;
                if (m_axi_arvalid && m_axi_arready) begin
                    next_state = WAIT_R;
                end
            end

            WAIT_R: begin
                m_axi_rready = !fifo_full;         
                if (m_axi_rvalid && m_axi_rready) begin
                    if (m_axi_rlast) begin
                        rx_done     = 1'b1;
                        next_state  = IDLE;
                    end
                end
            end
            default: next_state = IDLE;
        endcase
    end

    assign fifo_wdata       = m_axi_rdata;
    assign fifo_wr_en       = (state == WAIT_R) && m_axi_rvalid && m_axi_rready;    
    assign m_axi_araddr     = addr_reg;
    assign m_axi_arlen      = (len_reg > 0) ? (len_reg - 1'b1) : 8'd0;
    assign m_axi_arsize     = 3'b010;
    assign m_axi_arburst    = 2'b01;
    assign busy             = (state != IDLE) || start_reg;
endmodule