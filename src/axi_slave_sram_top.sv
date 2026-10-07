//AXI SLAVE

module axi_slave_sram_top #(
    parameter ID_WIDTH      = 4,
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 32,
    parameter STRB_WIDTH    = DATA_WIDTH / 8
)(
    input   logic                     aclk,
    input   logic                     rst_n,

    //WRITE ADDRESS
    input   logic [ID_WIDTH-1:0]      s_axi_awid,                            //ID for transaction
    input   logic [ADDR_WIDTH-1:0]    s_axi_awaddr,                          //Address of the first transaction start write
    input   logic [7:0]               s_axi_awlen,                           //Number of transaction per burst
    input   logic [2:0]               s_axi_awsize,                          //Size of each beat/transaction
    input   logic [1:0]               s_axi_awburst,                         //Type of burst: FiX/INCR/WRAP
    input   logic                     s_axi_awvalid,                         //(Master) Valid address
    output  logic                     s_axi_awready,                         //(Slave) Ready to receive address
    
    //WRITE DATA
    input   logic [DATA_WIDTH-1:0]    s_axi_wdata,                           //Data write from Master
    input   logic [STRB_WIDTH-1:0]    s_axi_wstrb,                           //Byte mask activate 4 bank
    input   logic                     s_axi_wlast,                           //(Master) Announce last beat of burst
    input   logic                     s_axi_wvalid,                          //(Master) Valid data
    output  logic                     s_axi_wready,                          //(Slave) Ready to write into RAM

    //WRITE RESPONSE
    output  logic [ID_WIDTH-1:0]      s_axi_bid,                             //(Slave) Response ID (equal to awid)
    output  logic [1:0]               s_axi_bresp,                           //(Slave) OKAY/EXOKAY/SLVERR,..
    output  logic                     s_axi_bvalid,                          //(Slave) Valid response
    input   logic                     s_axi_bready,                          //(Master) ready to receive response

    //READ ADDRESS
    input   logic [ID_WIDTH-1:0]      s_axi_arid,                            //ID for transaction
    input   logic [ADDR_WIDTH-1:0]    s_axi_araddr,                          //Address of the first transaction start read
    input   logic [7:0]               s_axi_arlen,                           //Number of transaction per burst
    input   logic [2:0]               s_axi_arsize,                          //Size of each beat/transaction
    input   logic [1:0]               s_axi_arburst,                         //Type of burst: FiX/INCR/WRAP
    input   logic                     s_axi_arvalid,                         //(Master) Valid address
    output  logic                     s_axi_arready,                         //(Slave) Ready to receive address

    //READ DATA
    output  logic [ID_WIDTH-1:0]      s_axi_rid,                             //(Slave) ID from data reed send to Master (equal to arid)
    output  logic [DATA_WIDTH-1:0]    s_axi_rdata,                           //(Slave) Data read from RAM
    output  logic                     s_axi_rlast,                           //(Slave) Announce last beat of burst
    output  logic [1:0]               s_axi_rresp,                           //(Slave) Data status read per beat
    output  logic                     s_axi_rvalid,                          //(Slave) Announce valid data
    input   logic                     s_axi_rready                           //(Master) Ready to receive reed data
);
    //WIRE FROM WRITE_CONTROLLER
    logic [ADDR_WIDTH-1:0]            awaddr_latch;                          //latch address to burst_addr_gen
    logic [2:0]                       awsize_latch;
    logic [1:0]                       awburst_latch;
    logic                             wr_step;                               //Announce wrote 1 beat, increasing address
    logic                             wr_en;                                 //In write process

    //WIRE FROM READ_CONTROLLER
    logic [ADDR_WIDTH-1:0]            araddr_latch;                          //latch address to burst_addr_gen
    logic [2:0]                       arsize_latch;
    logic [7:0]                       arlen_latch;
    logic                             rd_step;                               //Announce read 1 beat, increasing address
    logic                             rd_en;                                 //In read process

    //WIRE FROM SRAM
    logic [13:0]                      sram_addr;
    logic                             sram_wen;

    //Load address pulse
    wire wr_load = s_axi_awvalid && s_axi_awready;                          // Load address when handshaking
    wire rd_load = s_axi_arvalid && s_axi_arready;     
    assign sram_wen = wr_en && (s_axi_wvalid && s_axi_wready);      
    
    //WRITE CONTROLLER
    write_controller #(
        .ID_WIDTH       (ID_WIDTH),
        .ADDR_WIDTH     (ADDR_WIDTH)
    ) u_write_controller (
        .aclk           (aclk),
        .arst_n         (rst_n),

        //WRITE ADDRESS
        .s_axi_awid     (s_axi_awid),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awlen    (s_axi_awlen),
        .s_axi_awsize   (s_axi_awsize),
        .s_axi_awburst  (s_axi_awburst),
        .s_axi_awready  (s_axi_awready),

        //WRITE DATA
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wlast    (s_axi_wlast),
        .s_axi_wready   (s_axi_wready),

        //B (RESPONSE)
        .s_axi_bready   (s_axi_bready),
        .s_axi_bid      (s_axi_bid),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bresp    (s_axi_bresp),

        //OUTPUT FOR burst_addr_gen
        .awaddr_latch   (awaddr_latch),
        .awsize_latch   (awsize_latch),
        .awburst_latch  (awburst_latch),
        .wr_step        (wr_step),
        .wr_en          (wr_en)                                 
    );

    //READ_CONTROLLER
    read_controller #(
        .ID_WIDTH       (ID_WIDTH),
        .ADDR_WIDTH     (ADDR_WIDTH)
    ) u_read_controller (
        .aclk           (aclk),
        .arst_n         (rst_n),
        //READ ADDRESS
        .s_axi_arid     (s_axi_arid),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arlen    (s_axi_arlen),
        .s_axi_arburst  (s_axi_arburst),
        .s_axi_arsize   (s_axi_arsize),
        .s_axi_arready  (s_axi_arready),
        //READ DATA
        .s_axi_rid      (s_axi_rid),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rlast    (s_axi_rlast),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rready   (s_axi_rready),
        //Output for burst_addr_gen
        .araddr_latch   (araddr_latch),
        .arsize_latch   (arsize_latch),
        .arlen_latch    (arlen_latch),
        .rd_step        (rd_step),
        .rd_en          (rd_en)
    );

    //burst_addr_gen
    burst_addr_gen #(
        .ADDR_WIDTH     (ADDR_WIDTH)
    ) u_burst_addr_gen (
        .aclk           (aclk),
        .arst_n         (rst_n),
        // Write path
        .wr_addr_init   (s_axi_awaddr),
        .wr_load        (wr_load),
        .wr_step        (wr_step),
        .wr_en          (wr_en),
        // Read path
        .rd_addr_init   (s_axi_araddr),
        .rd_load        (rd_load),
        .rd_step        (rd_step),
        .rd_en          (rd_en),
        // SRAM Word Address output
        .sram_addr      (sram_addr)
    );

    //SRAM 4 BANK
    sram_4bank_core #(
        .DATA_WIDTH     (DATA_WIDTH),
        .ADDR_WIDTH     (14)
    ) u_sram_4bank_core (
        .aclk            (aclk),
        .we             (sram_wen),
        .addr           (sram_addr),
        .wdata          (s_axi_wdata),
        .wstrb          (s_axi_wstrb),
        .rdata          (s_axi_rdata)
    );

endmodule