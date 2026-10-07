`timescale 1ns / 1ps

module tb_dma_sram_system;

    // =========================================================================
    // 1. PARAMETERS & CLOCK
    // =========================================================================
    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 32;
    localparam FF_DEPTH   = 16;
    localparam CLK_PERIOD = 10; // 100 MHz clock

    // CSR Offsets
    localparam [4:0] ADDR_DMA_CTRL      = 5'h00;
    localparam [4:0] ADDR_DMA_STATUS    = 5'h04;
    localparam [4:0] ADDR_DMA_SRC_ADDR  = 5'h08;
    localparam [4:0] ADDR_DMA_DST_ADDR  = 5'h0C;
    localparam [4:0] ADDR_DMA_BURST_LEN = 5'h10;

    logic clk;
    logic rst_n;

    // =========================================================================
    // 2. BUS SIGNALS
    // =========================================================================
    // [Bus 1] AXI-Lite: CPU <--> DMA CSR
    logic [ADDR_WIDTH-1:0]   cpu_axil_awaddr;
    logic                    cpu_axil_awvalid;
    logic                    cpu_axil_awready;
    logic [DATA_WIDTH-1:0]   cpu_axil_wdata;
    logic                    cpu_axil_wvalid;
    logic                    cpu_axil_wready;
    logic [1:0]              cpu_axil_bresp;
    logic                    cpu_axil_bvalid;
    logic                    cpu_axil_bready;
    logic [ADDR_WIDTH-1:0]   cpu_axil_araddr;
    logic                    cpu_axil_arvalid;
    logic                    cpu_axil_arready;
    logic [DATA_WIDTH-1:0]   cpu_axil_rdata;
    logic [1:0]              cpu_axil_rresp;
    logic                    cpu_axil_rvalid;
    logic                    cpu_axil_rready;

    // [Bus 2] AXI4: DMA Read Master <--> Source RAM
    logic [ADDR_WIDTH-1:0]   dma_m_araddr;
    logic [7:0]              dma_m_arlen;
    logic [2:0]              dma_m_arsize;
    logic [1:0]              dma_m_arburst;
    logic                    dma_m_arvalid;
    logic                    dma_m_arready;
    logic [DATA_WIDTH-1:0]   dma_m_rdata;
    logic                    dma_m_rlast;
    logic                    dma_m_rvalid;
    logic [1:0]              dma_m_rresp;
    logic                    dma_m_rready;

    // [Bus 3] AXI4: DMA Write Master <--> axi_slave_sram_top Write Channel
    logic [ADDR_WIDTH-1:0]   dma_m_awaddr;
    logic [7:0]              dma_m_awlen;
    logic [2:0]              dma_m_awsize;
    logic [1:0]              dma_m_awburst;
    logic                    dma_m_awvalid;
    logic                    dma_m_awready;
    logic [DATA_WIDTH-1:0]   dma_m_wdata;
    logic [DATA_WIDTH/8-1:0] dma_m_wstrb;
    logic                    dma_m_wlast;
    logic                    dma_m_wvalid;
    logic                    dma_m_wready;
    logic [1:0]              dma_m_bresp;
    logic                    dma_m_bvalid;
    logic                    dma_m_bready;

    // [Bus 4] AXI4: CPU Direct Read <--> axi_slave_sram_top Read Channel (Verify)
    logic [ADDR_WIDTH-1:0]   sram_cpu_araddr;
    logic [7:0]              sram_cpu_arlen;
    logic [2:0]              sram_cpu_arsize;
    logic [1:0]              sram_cpu_arburst;
    logic                    sram_cpu_arvalid;
    logic                    sram_cpu_arready;
    logic [DATA_WIDTH-1:0]   sram_cpu_rdata;
    logic                    sram_cpu_rlast;
    logic                    sram_cpu_rvalid;
    logic [1:0]              sram_cpu_rresp;
    logic                    sram_cpu_rready;

    // Interrupt & Simulated Source RAM
    logic                    irq;
    logic [DATA_WIDTH-1:0]   src_ram [0:255];
    int                      error_count = 0;

    // =========================================================================
    // 3. DUT INSTANTIATION
    // =========================================================================
    // Module 1: DMA Controller Top
    dma_top #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .FF_DEPTH   (FF_DEPTH)
    ) u_dma_top (
        .clk            (clk),
        .rst_n          (rst_n),

        // AXI-Lite Slave
        .s_axil_awaddr  (cpu_axil_awaddr),
        .s_axil_awvalid (cpu_axil_awvalid),
        .s_axil_awready (cpu_axil_awready),
        .s_axil_wdata   (cpu_axil_wdata),
        .s_axil_wvalid  (cpu_axil_wvalid),
        .s_axil_wready  (cpu_axil_wready),
        .s_axil_bresp   (cpu_axil_bresp),
        .s_axil_bvalid  (cpu_axil_bvalid),
        .s_axil_bready  (cpu_axil_bready),
        .s_axil_araddr  (cpu_axil_araddr),
        .s_axil_arvalid (cpu_axil_arvalid),
        .s_axil_arready (cpu_axil_arready),
        .s_axil_rdata   (cpu_axil_rdata),
        .s_axil_rresp   (cpu_axil_rresp),
        .s_axil_rvalid  (cpu_axil_rvalid),
        .s_axil_rready  (cpu_axil_rready),

        // AXI4 Read Master
        .m_axi_araddr   (dma_m_araddr),
        .m_axi_arlen    (dma_m_arlen),
        .m_axi_arsize   (dma_m_arsize),
        .m_axi_arburst  (dma_m_arburst),
        .m_axi_arvalid  (dma_m_arvalid),
        .m_axi_arready  (dma_m_arready),
        .m_axi_rdata    (dma_m_rdata),
        .m_axi_rlast    (dma_m_rlast),
        .m_axi_rvalid   (dma_m_rvalid),
        .m_axi_rresp    (dma_m_rresp),
        .m_axi_rready   (dma_m_rready),

        // AXI4 Write Master
        .m_axi_awaddr   (dma_m_awaddr),
        .m_axi_awlen    (dma_m_awlen),
        .m_axi_awsize   (dma_m_awsize),
        .m_axi_awburst  (dma_m_awburst),
        .m_axi_awvalid  (dma_m_awvalid),
        .m_axi_awready  (dma_m_awready),
        .m_axi_wdata    (dma_m_wdata),
        .m_axi_wstrb    (dma_m_wstrb),
        .m_axi_wlast    (dma_m_wlast),
        .m_axi_wvalid   (dma_m_wvalid),
        .m_axi_wready   (dma_m_wready),
        .m_axi_bresp    (dma_m_bresp),
        .m_axi_bvalid   (dma_m_bvalid),
        .m_axi_bready   (dma_m_bready),

        .irq            (irq)
    );

    // Module 2: AXI Slave SRAM Top
    axi_slave_sram_top #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_axi_slave_sram (
        .aclk           (clk),
        .rst_n          (rst_n),

        // Write Channel: Connected to DMA Write Master
        .s_axi_awid     ('0),
        .s_axi_awaddr   (dma_m_awaddr),
        .s_axi_awlen    (dma_m_awlen),
        .s_axi_awsize   (dma_m_awsize),
        .s_axi_awburst  (dma_m_awburst),
        .s_axi_awvalid  (dma_m_awvalid),
        .s_axi_awready  (dma_m_awready),

        .s_axi_wdata    (dma_m_wdata),
        .s_axi_wstrb    (dma_m_wstrb),
        .s_axi_wlast    (dma_m_wlast),
        .s_axi_wvalid   (dma_m_wvalid),
        .s_axi_wready   (dma_m_wready),

        .s_axi_bid      (),
        .s_axi_bresp    (dma_m_bresp),
        .s_axi_bvalid   (dma_m_bvalid),
        .s_axi_bready   (dma_m_bready),

        // Read Channel: Connected to CPU Testbench for Verification
        .s_axi_arid     ('0),
        .s_axi_araddr   (sram_cpu_araddr),
        .s_axi_arlen    (sram_cpu_arlen),
        .s_axi_arsize   (sram_cpu_arsize),
        .s_axi_arburst  (sram_cpu_arburst),
        .s_axi_arvalid  (sram_cpu_arvalid),
        .s_axi_arready  (sram_cpu_arready),

        .s_axi_rid      (),
        .s_axi_rdata    (sram_cpu_rdata),
        .s_axi_rlast    (sram_cpu_rlast),
        .s_axi_rvalid   (sram_cpu_rvalid),
        .s_axi_rresp    (sram_cpu_rresp),
        .s_axi_rready   (sram_cpu_rready)
    );

    // =========================================================================
    // 4. CLOCK & SOURCE RAM RESPONDER MODEL
    // =========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    logic [7:0] r_len_latched;
    logic [7:0] r_beat_cnt;
    logic [7:0] r_word_idx;
    logic       r_busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dma_m_arready <= 1'b0;
            dma_m_rvalid  <= 1'b0;
            dma_m_rlast   <= 1'b0;
            dma_m_rdata   <= '0;
            dma_m_rresp   <= 2'b00;
            r_len_latched <= '0;
            r_beat_cnt    <= '0;
            r_word_idx    <= '0;
            r_busy        <= 1'b0;
        end else begin
            if (!r_busy) begin
                dma_m_arready <= 1'b1;
                if (dma_m_arvalid && dma_m_arready) begin
                    dma_m_arready <= 1'b0;
                    r_busy        <= 1'b1;
                    r_len_latched <= dma_m_arlen;
                    r_word_idx    <= dma_m_araddr[9:2];
                    r_beat_cnt    <= '0;
                    dma_m_rvalid  <= 1'b1;
                    dma_m_rdata   <= src_ram[dma_m_araddr[9:2]];
                    dma_m_rlast   <= (dma_m_arlen == 8'd0);
                end
            end else begin
                dma_m_arready <= 1'b0;
                if (dma_m_rvalid && dma_m_rready) begin
                    if (r_beat_cnt == r_len_latched) begin
                        dma_m_rvalid <= 1'b0;
                        dma_m_rlast  <= 1'b0;
                        r_busy       <= 1'b0;
                    end else begin
                        r_beat_cnt   <= r_beat_cnt + 1'b1;
                        dma_m_rdata  <= src_ram[r_word_idx + r_beat_cnt + 1'b1];
                        if (r_beat_cnt + 1'b1 == r_len_latched) begin
                            dma_m_rlast <= 1'b1;
                        end
                    end
                end
            end
        end
    end

    // =========================================================================
    // 5. AXI BUS TASKS
    // =========================================================================
    task automatic cpu_write_csr(input [ADDR_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] data);
        @(posedge clk);
        cpu_axil_awaddr  <= addr;
        cpu_axil_wdata   <= data;
        cpu_axil_awvalid <= 1'b1;
        cpu_axil_wvalid  <= 1'b1;
        cpu_axil_bready  <= 1'b1;

        wait(cpu_axil_awready && cpu_axil_wready);
        @(posedge clk);
        cpu_axil_awvalid <= 1'b0;
        cpu_axil_wvalid  <= 1'b0;

        wait(cpu_axil_bvalid);
        @(posedge clk);
        cpu_axil_bready  <= 1'b0;
    endtask

    task automatic cpu_read_sram_word(input [ADDR_WIDTH-1:0] addr, output [DATA_WIDTH-1:0] data);
        @(posedge clk);
        sram_cpu_araddr  <= addr;
        sram_cpu_arlen   <= 8'd0;    // Single beat (1 word)
        sram_cpu_arsize  <= 3'b010;  // 4 Bytes
        sram_cpu_arburst <= 2'b01;   // INCR
        sram_cpu_arvalid <= 1'b1;
        sram_cpu_rready  <= 1'b1;

        wait(sram_cpu_arready);
        @(posedge clk);
        sram_cpu_arvalid <= 1'b0;

        wait(sram_cpu_rvalid);
        data = sram_cpu_rdata;
        @(posedge clk);
        sram_cpu_rready  <= 1'b0;
    endtask

    // =========================================================================
    // 6. AUTOMATED DMA TRANSFER VERIFICATION TASK
    // =========================================================================
    task automatic run_dma_transfer(
        input [ADDR_WIDTH-1:0] src_addr,
        input [ADDR_WIDTH-1:0] dst_addr,
        input [7:0]            burst_length,
        input string           scenario_name
    );
        logic [DATA_WIDTH-1:0] read_val;
        int src_word_base;

        src_word_base = src_addr[9:2];

        $display("\n------------------------------------------------------------");
        $display(">>> STARTING: %s", scenario_name);
        $display("    Config: SRC = 0x%08h | DST = 0x%08h | LEN = %0d beats", src_addr, dst_addr, burst_length);
        $display("------------------------------------------------------------");

        // 1. Program DMA Registers
        cpu_write_csr(ADDR_DMA_SRC_ADDR, src_addr);
        cpu_write_csr(ADDR_DMA_DST_ADDR, dst_addr);
        cpu_write_csr(ADDR_DMA_BURST_LEN, {24'd0, burst_length});

        // 2. Start Transfer (START=1, IE=1)
        cpu_write_csr(ADDR_DMA_CTRL, 32'h0000_0003);

        // 3. Wait for hardware IRQ assertion
        fork
            begin
                wait(irq === 1'b1);
                $display("[PASS] Hardware IRQ asserted upon completion!");
            end
            begin
                #(CLK_PERIOD * 400);
                $error("[FAIL] Simulation Timeout! DMA transfer failed to complete.");
                error_count++;
            end
        join_any
        disable fork;

        // 4. Verify data directly from SRAM Slave
        for (int i = 0; i < burst_length; i++) begin
            logic [ADDR_WIDTH-1:0] curr_sram_addr;
            curr_sram_addr = dst_addr + (i * 4);

            cpu_read_sram_word(curr_sram_addr, read_val);

            if (read_val === src_ram[src_word_base + i]) begin
                $display("  [MATCH] SRAM[0x%08h] = 0x%08h == SRC[0x%08h]", curr_sram_addr, read_val, src_ram[src_word_base + i]);
            end else begin
                $error("  [MISMATCH] SRAM[0x%08h] = 0x%08h, Expected: 0x%08h", curr_sram_addr, read_val, src_ram[src_word_base + i]);
                error_count++;
            end
        end

        // 5. Acknowledge IRQ via W1C
        cpu_write_csr(ADDR_DMA_STATUS, 32'h0000_0002);
        #(CLK_PERIOD * 2);

        if (irq === 1'b0) begin
            $display("[PASS] IRQ successfully de-asserted to 0. %s completed.", scenario_name);
        end else begin
            $error("[FAIL] IRQ remained high after W1C acknowledge!");
            error_count++;
        end
    endtask

    // =========================================================================
    // 7. BACK-TO-BACK TESTBENCH SCENARIOS
    // =========================================================================
    initial begin
        // Signal Initialization
        rst_n            = 1'b0;
        cpu_axil_awaddr  = '0;
        cpu_axil_wdata   = '0;
        cpu_axil_awvalid = 1'b0;
        cpu_axil_wvalid  = 1'b0;
        cpu_axil_bready  = 1'b0;
        cpu_axil_araddr  = '0;
        cpu_axil_arvalid = 1'b0;
        cpu_axil_rready  = 1'b0;

        sram_cpu_araddr  = '0;
        sram_cpu_arlen   = '0;
        sram_cpu_arsize  = '0;
        sram_cpu_arburst = '0;
        sram_cpu_arvalid = 1'b0;
        sram_cpu_rready  = 1'b0;

        // Populate Source RAM
        for (int i = 0; i < 256; i++) begin
            src_ram[i] = 32'h55AA_0000 + i;
        end

        $display("============================================================");
        $display("       BACK-TO-BACK DMA TRANSFERS VERIFICATION (NO RESET)   ");
        $display("============================================================");

        // System Reset once at the beginning
        #(CLK_PERIOD * 5);
        rst_n = 1'b1;
        #(CLK_PERIOD * 5);
        $display("[INIT PASS] Reset released. Starting continuous back-to-back testing.");

        // ---------------------------------------------------------------------
        // TESTCASE 1: Full-Capacity Burst (16 beats)
        // ---------------------------------------------------------------------
        run_dma_transfer(
            .src_addr     (32'h0000_0000),
            .dst_addr     (32'h0000_0100),
            .burst_length (8'd16),
            .scenario_name("SCENARIO 1: Burst 16 beats (FIFO Full Capacity)")
        );

        // ---------------------------------------------------------------------
        // TESTCASE 2: Immediate Back-to-Back Transfer (8 beats)
        // ---------------------------------------------------------------------
        #(CLK_PERIOD * 3);
        run_dma_transfer(
            .src_addr     (32'h0000_0040),
            .dst_addr     (32'h0000_0200),
            .burst_length (8'd8),
            .scenario_name("SCENARIO 2: Burst 8 beats (Half-FIFO Transfer)")
        );

        // ---------------------------------------------------------------------
        // TESTCASE 3: Immediate Corner-Case Transfer (Single Beat - 1 beat)
        // ---------------------------------------------------------------------
        #(CLK_PERIOD * 3);
        run_dma_transfer(
            .src_addr     (32'h0000_0080),
            .dst_addr     (32'h0000_0300),
            .burst_length (8'd1),
            .scenario_name("SCENARIO 3: Burst 1 beat (Single Word Corner Case)")
        );

        // ---------------------------------------------------------------------
        // FINAL VERDICT
        // ---------------------------------------------------------------------
        #(CLK_PERIOD * 10);
        $display("\n============================================================");
        if (error_count == 0)
            $display(">>> FINAL VERDICT: ALL BACK-TO-BACK TRANSFERS PASSED! <<<");
        else
            $display(">>> FINAL VERDICT: DETECTED %0d ERROR(S) DURING BACK-TO-BACK TRANSFERS! <<<", error_count);
        $display("============================================================\n");
        $finish;
    end

endmodule