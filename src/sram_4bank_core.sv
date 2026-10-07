//======================================================//
//MODULE: SRAM_4BANK_CORE
//- Mảng nhớ SRAM 32-bit gồm 4 Bank 8-bit độc lập hỗ trợ Byte-Enable
//======================================================//

module sram_4bank_core #(
    parameter DATA_WIDTH = 32,
    parameter STRB_WIDTH = DATA_WIDTH/8,
    parameter ADDR_WIDTH = 14,
    parameter BANK_DEPTH = 16384                                                    //2^14
)(
    input logic                     aclk,
    input logic [DATA_WIDTH-1:0]    wdata,                                          //Data write
    input logic [STRB_WIDTH-1:0]    wstrb,                                          //Strobe from Master
    input logic [ADDR_WIDTH-1:0]    addr,                                           //Address from burst_addr_gen
    input logic                     we,                                             //Write Enable
    
    output logic [DATA_WIDTH-1:0]   rdata                                           //Read data
);
    //4 Bank 8-bit
    logic [7:0] bank0 [0:BANK_DEPTH-1];                                             //Byte 0 [7:0]
    logic [7:0] bank1 [0:BANK_DEPTH-1];                                             //Byte 1 [15:8]
    logic [7:0] bank2 [0:BANK_DEPTH-1];                                             //Byte 2 [23:16]
    logic [7:0] bank3 [0:BANK_DEPTH-1];                                             //Byte 3 [31:24]
    
    //Write
    always_ff @(posedge aclk) begin
        if (we) begin
            if (wstrb[0]) bank0[addr] <= wdata[7:0];
            if (wstrb[1]) bank1[addr] <= wdata[15:8];
            if (wstrb[2]) bank2[addr] <= wdata[23:16];
            if (wstrb[3]) bank3[addr] <= wdata[31:24];
        end
    end

    //4 byte in a row
    always_ff @(posedge aclk) begin
        rdata <= {bank3[addr], bank2[addr], bank1[addr], bank0[addr]};
    end

endmodule