module read_controller #(
    parameter ID_WIDTH      = 4,
    parameter ADDR_WIDTH    = 32
)(
    input logic aclk,
    input logic arst_n,

    //READ ADDRESS
    input logic [ID_WIDTH-1:0]      s_axi_arid,
    input logic                     s_axi_arvalid,
    input logic [ADDR_WIDTH-1:0]    s_axi_araddr,
    input logic [7:0]               s_axi_arlen,
    input logic [1:0]               s_axi_arburst,
    input logic [2:0]               s_axi_arsize,
    output logic                    s_axi_arready,
    
    //READ DATA
    output logic                    s_axi_rvalid,
    output logic                    s_axi_rlast,
    output logic [1:0]              s_axi_rresp,
    input logic                     s_axi_rready,
    output logic [ID_WIDTH-1:0]     s_axi_rid,

    //SENT TO burst_addr_gen
    output logic [ADDR_WIDTH-1:0]   araddr_latch,                           //latch address to burst_addr_gen
    output logic [2:0]              arsize_latch,
    output logic [7:0]              arlen_latch,
    output logic                    rd_step,                                //Announce read 1 beat, increasing address
    output logic                    rd_en                                   //In read process
);
    typedef enum logic [1:0] {IDLE, RECEIVE_DATA_FROM_SRAM, SENT_TO_MASTER} fsm;
    fsm state, next_state;
    logic [7:0] beat_cnt;
    logic [ID_WIDTH-1:0] arid_latch;

    always_ff @(posedge aclk or negedge arst_n) begin
        if (!arst_n) begin
            state <= IDLE;
            beat_cnt        <= '0;
            arid_latch      <= '0;
            araddr_latch    <= '0;
            arsize_latch    <= '0;
            arlen_latch     <= '0;
        end else begin
            state <= next_state;
            if (s_axi_arvalid && s_axi_arready) begin
                araddr_latch <= s_axi_araddr;
                arsize_latch <= s_axi_arsize;
                arlen_latch  <= s_axi_arlen;
                arid_latch   <= s_axi_arid;
                beat_cnt     <= '0;
            end else if (s_axi_rvalid && s_axi_rready) begin
                beat_cnt     <= beat_cnt + 1'b1;
            end
        end
    end

    always_comb begin
        next_state = state;
        s_axi_arready = '0; 
        s_axi_rvalid  = '0;
        
        case (state)
            IDLE: begin
                s_axi_arready = 1'b1;
                if (s_axi_arvalid && s_axi_arready) begin
                    next_state = RECEIVE_DATA_FROM_SRAM;
                end else next_state = IDLE;
            end

            RECEIVE_DATA_FROM_SRAM: begin
                next_state = SENT_TO_MASTER;
            end

            SENT_TO_MASTER: begin
                s_axi_rvalid = 1'b1;
                if (s_axi_rready && s_axi_rvalid) begin
                    if (beat_cnt == arlen_latch) begin
                        next_state = IDLE;
                    end else next_state = RECEIVE_DATA_FROM_SRAM;
                end else next_state = SENT_TO_MASTER;
            end
            default: next_state = IDLE;
        endcase
    end

    assign s_axi_rresp = 2'b00;
    assign s_axi_rlast = (state == SENT_TO_MASTER) && (beat_cnt == arlen_latch);
    assign rd_en = (state != IDLE);
    assign rd_step = (state == SENT_TO_MASTER) && (s_axi_rvalid && s_axi_rready);
    assign s_axi_rid = arid_latch;
endmodule