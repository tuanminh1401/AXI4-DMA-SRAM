module axi_source_mem #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter MEM_DEPTH  = 256
)(
    input logic clk,
    input logic rst_n,
    
    //AR (slave receive address from master (dma_read))
    input logic [ADDR_WIDTH-1:0]    s_axi_araddr,
    input logic [7:0]               s_axi_arlen,
    input logic [2:0]               s_axi_arsize,
    input logic [1:0]               s_axi_arburst,
    input logic                     s_axi_arvalid,
    output logic                    s_axi_arready,

    //R (master (dma_read) receive address from slave)
    output logic [DATA_WIDTH-1:0]   s_axi_rdata,
    output logic [1:0]              s_axi_rresp,
    output logic                    s_axi_rlast,
    output logic                    s_axi_rvalid,
    input logic                     s_axi_rready
);
    //memory
    logic [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    //sample address
    initial begin
        for (int i = 0; i < MEM_DEPTH; i++) begin
            mem[i] = 32'hA000_0000 + i;
        end
    end

    typedef enum logic [1:0] {S_IDLE, S_DATA} fsm;
    fsm state, next_state;

    logic [ADDR_WIDTH-1:0]  raddr_reg;
    logic [7:0]             rlen_reg;
    logic [7:0]             beat_cnt;

    //transform 32bit from axi to collect mem in 256 ram floor
    wire [$clog2(MEM_DEPTH)-1:0] word_idx = raddr_reg[ADDR_WIDTH-1:2] % MEM_DEPTH;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            raddr_reg <= '0;
            rlen_reg <= '0;
            beat_cnt <= '0;
        end else begin
            state <= next_state;
            if (state == S_IDLE && s_axi_arvalid && s_axi_arready) begin
                raddr_reg <= s_axi_araddr;
                rlen_reg <= s_axi_arlen;
                beat_cnt <= '0;
            end else if (state == S_DATA && s_axi_rvalid && s_axi_rready) begin
                beat_cnt <= beat_cnt + 1;
                raddr_reg <= raddr_reg + 4;
            end 
        end
    end

    always_comb begin   
        next_state = state;
        s_axi_arready = '0;
        s_axi_rvalid = '0;
        s_axi_rlast = '0;

        case (state)
            S_IDLE: begin
                s_axi_arready = 1'b1;
                if (s_axi_arready && s_axi_arvalid) begin
                    next_state = S_DATA;
                end
            end

            S_DATA: begin
                s_axi_rvalid = 1'b1;
                if (beat_cnt == rlen_reg) begin
                    s_axi_rlast = 1'b1;
                end
                if (s_axi_rready && s_axi_rvalid && (beat_cnt == rlen_reg)) begin
                    next_state = S_IDLE;
                end
            end
            default: next_state = S_IDLE;
        endcase
    end

    assign s_axi_rdata = mem[word_idx];
    assign s_axi_rresp = 2'b00;

endmodule