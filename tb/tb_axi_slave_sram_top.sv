`timescale 1ns/1ps
module tb_axi_slave_sram_top;
    localparam ID_WIDTH = 4;
    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;
    localparam STRB_WIDTH = DATA_WIDTH/8;
    localparam CLK_PERIOD = 10;                             //100MHz

    //Signal
    logic               aclk;
    logic               rst_n;

    // AW Channel
    logic [ID_WIDTH-1:0]     s_axi_awid;
    logic [ADDR_WIDTH-1:0]   s_axi_awaddr;
    logic [7:0]              s_axi_awlen;
    logic [2:0]              s_axi_awsize;
    logic [1:0]              s_axi_awburst;
    logic                    s_axi_awvalid;
    logic                    s_axi_awready;

    // W Channel
    logic [DATA_WIDTH-1:0]   s_axi_wdata;
    logic [STRB_WIDTH-1:0]   s_axi_wstrb;
    logic                    s_axi_wlast;
    logic                    s_axi_wvalid;
    logic                    s_axi_wready;

    // B Channel
    logic [ID_WIDTH-1:0]     s_axi_bid;
    logic [1:0]              s_axi_bresp;
    logic                    s_axi_bvalid;
    logic                    s_axi_bready;

    // AR Channel
    logic [ID_WIDTH-1:0]     s_axi_arid;
    logic [ADDR_WIDTH-1:0]   s_axi_araddr;
    logic [7:0]              s_axi_arlen;
    logic [2:0]              s_axi_arsize;
    logic [1:0]              s_axi_arburst;
    logic                    s_axi_arvalid;
    logic                    s_axi_arready;

    // R Channel
    logic [ID_WIDTH-1:0]     s_axi_rid;
    logic [DATA_WIDTH-1:0]   s_axi_rdata;
    logic                    s_axi_rlast;
    logic [1:0]              s_axi_rresp;
    logic                    s_axi_rvalid;
    logic                    s_axi_rready;

    //DUT
    axi_slave_sram_top #(
        .ID_WIDTH  (ID_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (.*);

    initial aclk = 0;
    always #(CLK_PERIOD/2) aclk = ~aclk;

    task automatic axi_write (input [ID_WIDTH-1:0] ID, input [ADDR_WIDTH-1:0] ADDR, input [7:0] len, input [DATA_WIDTH-1:0] data[], input [3:0] STRB);
        //AW Channel
        @(posedge aclk);
        s_axi_awid <= ID;
        s_axi_awaddr <= ADDR;
        s_axi_awlen <= len;
        s_axi_awsize <= 3'b010;                                 //4 Byte  (2^awsize)
        s_axi_awburst <= 2'b01;                                 //INCR
        s_axi_awvalid <= 1'b1;

        //wait for slave's response awready
        wait (s_axi_awvalid && s_axi_awready);
        @(posedge aclk);
        s_axi_awvalid <= 1'b0;                                  //down to zero immediately

        //W Channel
        for (int i = 0; i <= len; i++) begin
            s_axi_wdata <= data[i];
            s_axi_wstrb <= STRB;
            s_axi_wlast <= (i == len);
            s_axi_wvalid <= 1'b1;

            //wait for slave's response for each beat
            wait (s_axi_wvalid && s_axi_wready);
            @(posedge aclk);
        end

        //clear after sent successfully
        s_axi_wvalid <= 1'b0;
        s_axi_wlast <= 1'b0;

        //B (Response)
        s_axi_bready <= 1'b1;                                   //Master ready to receive response
        wait (s_axi_bvalid && s_axi_bready);
        @(posedge aclk);
        s_axi_bready <= 1'b0;

        $display("[WRITE SUCCESS] ID: %0h, Start Addr: 0x%08h, Length: %0d beats", ID, ADDR, len + 1);
    endtask

    task automatic axi_read (input [ID_WIDTH-1:0] ID, input [ADDR_WIDTH-1:0] ADDR, input [7:0] len, input [DATA_WIDTH-1:0] data[]);
        //AR Channel
        @(posedge aclk);
        s_axi_arid <= ID;
        s_axi_araddr <= ADDR;
        s_axi_arlen <= len;
        s_axi_arsize <= 3'b010;                                 //4 Byte  (2^awsize)
        s_axi_arburst <= 2'b01;                                 //INCR
        s_axi_arvalid <= 1'b1;

        //wait for slave's response awready
        wait (s_axi_arvalid && s_axi_arready);
        @(posedge aclk);
        s_axi_arvalid <= 1'b0;                                  //down to zero immediately

        //R Channel
        s_axi_rready <= 1'b1;
        for (int i = 0; i <= len; i++) begin
            do begin
                @(posedge aclk);
            end while (!s_axi_rvalid);

            if (s_axi_rdata == data[i]) begin
                $display("       -> Beat %0d: Match data (0x%08h)", i, s_axi_rdata);            
            end else begin
                $error("[FAIL] Beat %0d: Address 0x%08h | Expected: 0x%08h | HW: 0x%08h", i, ADDR + i*4, data[i], s_axi_rdata);
            end

            //check whether rlast announce
            if (i == len && !s_axi_rlast) begin
                $error("[FAIL] Lose s_axi_rlast at last beat!");
            end
        end

        @(posedge aclk);
        //clear after sent successfully
        s_axi_rready <= 1'b0;
        $display("[READ SUCCESS] ID: %0h, Start Addr: 0x%08h, Length: %0d beats\n", ID, ADDR, len + 1);
    endtask

    initial begin
        s_axi_awvalid = 0; s_axi_wvalid = 0; s_axi_wlast  = 0; s_axi_bready = 0;
        s_axi_arvalid = 0; s_axi_rready = 0;

        rst_n = 1'b0;
        #(CLK_PERIOD * 5);
        rst_n = 1'b1;
        #(CLK_PERIOD * 2);

        $display("=========================================================");
        $display("START SIMULATION AXI SLAVE SRAM");
        $display("=========================================================");
/*
        //Testcase 1: Single write & read (1 beat) at 0x1000;
        begin
            logic [31:0] data_1beat[1];
            data_1beat = '{32'hDEAD_BEEF};
            $display("\n--- [TEST 1] Single Transaction (len = 0) ---");                            //len = beat - 1;
            axi_write(4'h1, 32'h0000_1000, 8'd0, data_1beat, 4'b1111);
            axi_read (4'h1, 32'h0000_1000, 8'd0, data_1beat);
        end
*/
        // TESTCASE 2: Burst INCR (4 Beats) at 0x2000
        begin
            logic [31:0] data_4beat[4];
            data_4beat = '{32'h1111_1111, 32'h2222_2222, 32'h3333_3333, 32'h4444_4444};
            $display("--- [TEST 2] Burst INCR 4 Beats (len = 3) ---");
            axi_write(4'hA, 32'h0000_2000, 8'd3, data_4beat, 4'b1111);
            axi_read (4'hA, 32'h0000_2000, 8'd3, data_4beat);
        end
/*
        // TESTCASE 3: Back-to-Back Burst (write 8 Beats)
        begin
            logic [31:0] data_8beat[8];
            data_8beat = '{
                32'hAAAA_0000, 32'hAAAA_0001, 32'hAAAA_0002, 32'hAAAA_0003,
                32'hBBBB_0000, 32'hBBBB_0001, 32'hBBBB_0002, 32'hBBBB_0003
            };
            $display("--- [TEST 3] Burst INCR 8 Beats ---");
            axi_write(4'hF, 32'h0000_0040, 8'd7, data_8beat, 4'b1111);
            axi_read (4'hF, 32'h0000_0040, 8'd7, data_8beat);
        end

        //TESTCASE 4: Byte-Enable (wstrb)
        begin
            logic [31:0] data_init[1];
            logic [31:0] data_modify[1];
            logic [31:0] data_expected[1];

            data_init = '{32'hAAAA_AAAA};
            data_modify = '{32'hDEAD_BEEF};
            data_expected = '{32'hAAAA_BEEF};
            $display("--- [TEST 4] Byte Enable ---");

            axi_write(4'h2, 32'h0000_3000, 8'd0, data_init, 4'b1111);
            axi_write(4'h2, 32'h0000_3000, 8'd0, data_modify, 4'b0011);
            axi_read(4'h2, 32'h0000_3000, 8'd0, data_expected);
        end
*/
        $display("=========================================================");
        $display("STOP SIMULATION AXI SLAVE SRAM");
        $display("=========================================================");
        $stop;
    end
endmodule