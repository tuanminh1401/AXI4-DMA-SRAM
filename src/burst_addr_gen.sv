module burst_addr_gen #(
    parameter ADDR_WIDTH = 32
)(
    input logic                     aclk,
    input logic                     arst_n,

    input logic [ADDR_WIDTH-1:0]    wr_addr_init,
    input logic                     wr_step,
    input logic                     wr_en,
    input logic                     wr_load,

    input logic                     rd_en,
    input logic                     rd_load,
    input logic [ADDR_WIDTH-1:0]    rd_addr_init,
    input logic                     rd_step,

    output logic [13:0]             sram_addr
);
    logic [13:0] wr_current_addr, rd_current_addr; 

    always_ff @(posedge aclk or negedge arst_n) begin
        if (!arst_n) begin
            wr_current_addr <= '0;
        end else begin
            if (wr_load) begin
                wr_current_addr <= wr_addr_init[15:2];
            end else if (wr_step) begin
                wr_current_addr <= wr_current_addr + 1'b1;
            end else wr_current_addr <= wr_current_addr;
        end
    end

    always_ff @(posedge aclk or negedge arst_n) begin
        if (!arst_n) begin
            rd_current_addr <= '0;
        end else begin
            if (rd_load) begin
                rd_current_addr <= rd_addr_init[15:2];
            end else if (rd_step) begin
                rd_current_addr <= rd_current_addr + 1'b1;
            end else rd_current_addr <= rd_current_addr;
        end
    end

    assign sram_addr = wr_en ? wr_current_addr : rd_current_addr;
endmodule