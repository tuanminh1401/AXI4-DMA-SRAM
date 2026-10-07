`timescale 1ns / 1ps

module tb_dma_csr;

    // =========================================================================
    // 1. PARAMETERS & SIGNALS
    // =========================================================================
    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;
    localparam CLK_PERIOD = 10; // 100 MHz clock

    // Register Offsets
    localparam [4:0] ADDR_DMA_CTRL      = 5'h00;
    localparam [4:0] ADDR_DMA_STATUS    = 5'h04;
    localparam [4:0] ADDR_DMA_SRC_ADDR  = 5'h08;
    localparam [4:0] ADDR_DMA_DST_ADDR  = 5'h0C;
    localparam [4:0] ADDR_DMA_BURST_LEN = 5'h10;

    // Clock & Reset
    logic clk;
    logic rst_n;

    // AXI-Lite Write Channel
    logic [ADDR_WIDTH-1:0] s_axil_awaddr;
    logic [DATA_WIDTH-1:0] s_axil_wdata;
    logic                  s_axil_awvalid;
    logic                  s_axil_wvalid;
    logic                  s_axil_bready;
    logic                  s_axil_awready;
    logic                  s_axil_wready;
    logic                  s_axil_bvalid;
    logic [1:0]            s_axil_bresp;

    // AXI-Lite Read Channel
    logic [ADDR_WIDTH-1:0] s_axil_araddr;
    logic [DATA_WIDTH-1:0] s_axil_rdata;
    logic                  s_axil_arvalid;
    logic                  s_axil_rready;
    logic [1:0]            s_axil_rresp;
    logic                  s_axil_arready;
    logic                  s_axil_rvalid;

    // Master Interface & Status
    logic [ADDR_WIDTH-1:0] src_addr;
    logic [ADDR_WIDTH-1:0] dst_addr;
    logic [7:0]            burst_len;
    logic                  start_rx;
    logic                  start_tx;
    logic                  rx_done;
    logic                  tx_done;
    logic                  read_busy;
    logic                  write_busy;
    logic                  irq;

    int error_count = 0;

    // =========================================================================
    // 2. DEVICE UNDER TEST (DUT)
    // =========================================================================
    dma_csr #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),

        // Write Channel
        .s_axil_awaddr(s_axil_awaddr),
        .s_axil_wdata(s_axil_wdata),
        .s_axil_awvalid(s_axil_awvalid),
        .s_axil_wvalid(s_axil_wvalid),
        .s_axil_bready(s_axil_bready),
        .s_axil_awready(s_axil_awready),
        .s_axil_wready(s_axil_wready),
        .s_axil_bvalid(s_axil_bvalid),
        .s_axil_bresp(s_axil_bresp),

        // Read Channel
        .s_axil_araddr(s_axil_araddr),
        .s_axil_rdata(s_axil_rdata),
        .s_axil_arvalid(s_axil_arvalid),
        .s_axil_rready(s_axil_rready),
        .s_axil_rresp(s_axil_rresp),
        .s_axil_arready(s_axil_arready),
        .s_axil_rvalid(s_axil_rvalid),

        // Master Connections
        .src_addr(src_addr),
        .dst_addr(dst_addr),
        .burst_len(burst_len),
        .start_rx(start_rx),
        .start_tx(start_tx),
        .rx_done(rx_done),
        .tx_done(tx_done),
        .read_busy(read_busy),
        .write_busy(write_busy),
        .irq(irq)
    );

    // =========================================================================
    // 3. CLOCK GENERATOR (100 MHz)
    // =========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // =========================================================================
    // 4. AXI-LITE BUS TASKS
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
    // 5. TEST SCENARIOS
    // =========================================================================
    logic [DATA_WIDTH-1:0] rdata;

    initial begin
        // Signal Initialization
        rst_n          = 1'b0;
        s_axil_awaddr  = '0;
        s_axil_wdata   = '0;
        s_axil_awvalid = 1'b0;
        s_axil_wvalid  = 1'b0;
        s_axil_bready  = 1'b0;
        s_axil_araddr  = '0;
        s_axil_arvalid = 1'b0;
        s_axil_rready  = 1'b0;

        rx_done        = 1'b0;
        tx_done        = 1'b0;
        read_busy      = 1'b0;
        write_busy     = 1'b0;

        $display("============================================================");
        $display("              STARTING DMA_CSR VERIFICATION                 ");
        $display("============================================================");

        // -------------------------------------------------------------
        // TEST 1: ASYNCHRONOUS RESET VERIFICATION
        // -------------------------------------------------------------
        #(CLK_PERIOD * 3);
        rst_n = 1'b1;
        #(CLK_PERIOD * 2);

        if (src_addr == '0 && dst_addr == '0 && burst_len == '0 && irq == 1'b0)
            $display("[TEST 1 PASS] Reset de-asserted, internal registers cleared.");
        else begin
            $error("[TEST 1 FAIL] Output signals not cleared after reset!");
            error_count++;
        end

        // -------------------------------------------------------------
        // TEST 2: CONFIGURATION REGISTER R/W
        // -------------------------------------------------------------
        $display("\n--- TEST 2: Configuration Register Write & Read ---");

        // DMA_SRC_ADDR: 0x8000_1000
        axi_write(ADDR_DMA_SRC_ADDR, 32'h8000_1000);
        axi_read(ADDR_DMA_SRC_ADDR, rdata);
        if (rdata === 32'h8000_1000 && src_addr === 32'h8000_1000)
            $display("[PASS] DMA_SRC_ADDR: Written and Read 0x%08h successfully", rdata);
        else begin
            $error("[FAIL] DMA_SRC_ADDR mismatch! Read: 0x%08h, Expected: 0x80001000", rdata);
            error_count++;
        end

        // DMA_DST_ADDR: 0x2000_4000
        axi_write(ADDR_DMA_DST_ADDR, 32'h2000_4000);
        axi_read(ADDR_DMA_DST_ADDR, rdata);
        if (rdata === 32'h2000_4000 && dst_addr === 32'h2000_4000)
            $display("[PASS] DMA_DST_ADDR: Written and Read 0x%08h successfully", rdata);
        else begin
            $error("[FAIL] DMA_DST_ADDR mismatch! Read: 0x%08h, Expected: 0x20004000", rdata);
            error_count++;
        end

        // DMA_BURST_LEN: 0x10 (16 beats)
        axi_write(ADDR_DMA_BURST_LEN, 32'h0000_0010);
        axi_read(ADDR_DMA_BURST_LEN, rdata);
        if (rdata === 32'h0000_0010 && burst_len === 8'h10)
            $display("[PASS] DMA_BURST_LEN: Written and Read 0x%08h successfully", rdata);
        else begin
            $error("[FAIL] DMA_BURST_LEN mismatch! Read: 0x%08h, Expected: 0x00000010", rdata);
            error_count++;
        end

        // -------------------------------------------------------------
        // TEST 3: TRIGGER START PULSE & STATUS MONITORING
        // -------------------------------------------------------------
        $display("\n--- TEST 3: Trigger START Pulse and Verify Operations ---");

        fork
            begin
                // Write START = 1, IE = 1 (value 0x03)
                axi_write(ADDR_DMA_CTRL, 32'h0000_0003);
            end
            begin
                // Capture start_rx single-cycle pulse
                @(posedge start_rx);
                $display("[PASS] Detected start_rx rising edge!");
                
                @(posedge clk);
                #1; // Delay 1ns to allow NBA region update (Resolves race condition)
                if (start_rx === 1'b0)
                    $display("[PASS] start_rx auto-cleared to 0 after 1 clock cycle.");
                else begin
                    $error("[FAIL] start_rx failed to auto-clear to 0!");
                    error_count++;
                end
            end
        join

        // Verify start_tx status level
        if (start_tx === 1'b1)
            $display("[PASS] start_tx held high (DMA busy state active).");
        else begin
            $error("[FAIL] start_tx failed to assert high!");
            error_count++;
        end

        // Verify BUSY bit in DMA_STATUS
        axi_read(ADDR_DMA_STATUS, rdata);
        if (rdata[0] === 1'b1)
            $display("[PASS] Read DMA_STATUS: BUSY bit is 1 as expected.");
        else begin
            $error("[FAIL] BUSY bit in DMA_STATUS not asserted!");
            error_count++;
        end

        // Verify DMA_CTRL: Bit 0 must read 0 (pulse), Bit 1 must be 1 (IE)
        axi_read(ADDR_DMA_CTRL, rdata);
        if (rdata === 32'h0000_0002)
            $display("[PASS] Read DMA_CTRL: Bit START reads 0, Bit IE retained as 1.");
        else begin
            $error("[FAIL] DMA_CTRL mismatch! Read: 0x%08h", rdata);
            error_count++;
        end

        // -------------------------------------------------------------
        // TEST 4: SIMULATE MASTER COMPLETION & IRQ GENERATION
        // -------------------------------------------------------------
        $display("\n--- TEST 4: Master Completion & IRQ Assertion ---");
        #(CLK_PERIOD * 5); // Simulating ongoing DMA transfer...

        // Master asserts tx_done for 1 clock cycle
        @(posedge clk);
        tx_done <= 1'b1;
        @(posedge clk);
        tx_done <= 1'b0;
        @(posedge clk);

        // Verify BUSY clears and IRQ asserts
        if (start_tx === 1'b0 && irq === 1'b1)
            $display("[PASS] tx_done handled: start_tx de-asserted, IRQ asserted high.");
        else begin
            $error("[FAIL] Transfer completion error! start_tx = %b, irq = %b", start_tx, irq);
            error_count++;
        end

        // Read DMA_STATUS: Bit 0 = 0 (Idle), Bit 1 = 1 (DONE)
        axi_read(ADDR_DMA_STATUS, rdata);
        if (rdata[1:0] === 2'b10)
            $display("[PASS] Read DMA_STATUS: DONE bit = 1, BUSY bit = 0.");
        else begin
            $error("[FAIL] Status register mismatch! Read: 0x%08h", rdata);
            error_count++;
        end

        // -------------------------------------------------------------
        // TEST 5: W1C (WRITE-1-TO-CLEAR) MECHANISM
        // -------------------------------------------------------------
        $display("\n--- TEST 5: Verify W1C Mechanism on DONE Bit & IRQ De-assertion ---");

        // Write 1 to bit 1 of DMA_STATUS (0x02) to clear DONE
        axi_write(ADDR_DMA_STATUS, 32'h0000_0002);

        // Verify IRQ immediately drops to 0
        if (irq === 1'b0)
            $display("[PASS] IRQ de-asserted to 0 after W1C acknowledge.");
        else begin
            $error("[FAIL] IRQ remained asserted at 1!");
            error_count++;
        end

        // Read DMA_STATUS to verify DONE bit cleared
        axi_read(ADDR_DMA_STATUS, rdata);
        if (rdata[1] === 1'b0)
            $display("[PASS] Read DMA_STATUS: DONE bit successfully cleared to 0.");
        else begin
            $error("[FAIL] DONE bit not cleared! Read: 0x%08h", rdata);
            error_count++;
        end

        // -------------------------------------------------------------
        // SUMMARY
        // -------------------------------------------------------------
        #(CLK_PERIOD * 5);
        $display("============================================================");
        if (error_count == 0)
            $display(">>> FINAL RESULT: ALL TESTS PASSED SUCCESSFULLY! <<<");
        else
            $display(">>> FINAL RESULT: %0d ERROR(S) DETECTED! <<<", error_count);
        $display("============================================================");
        $finish;
    end

endmodule