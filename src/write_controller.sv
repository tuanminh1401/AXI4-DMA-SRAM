module write_controller #(
    parameter ID_WIDTH      = 4, 
    parameter ADDR_WIDTH    = 32
)(
    input logic aclk,
    input logic arst_n,

    //WRITE ADDRESS
    input logic [ID_WIDTH-1:0]      s_axi_awid,
    input logic                     s_axi_awvalid,
    input logic [ADDR_WIDTH-1:0]    s_axi_awaddr,
    input logic [7:0]               s_axi_awlen,                            //beat per burst
    input logic [2:0]               s_axi_awsize,                           //Number of byte per beat
    input logic [1:0]               s_axi_awburst,                          //FIX/INCR/WRAP
    output logic                    s_axi_awready,

    //WRITE DATA
    input logic                     s_axi_wvalid,
    input logic                     s_axi_wlast,
    output logic                    s_axi_wready,

    //B (RESPONSE)
    input logic                     s_axi_bready,
    output logic [ID_WIDTH-1:0]     s_axi_bid,
    output logic                    s_axi_bvalid,
    output logic [1:0]              s_axi_bresp,

    //OUTPUT FOR burst_addr_gen
    output logic [ADDR_WIDTH-1:0]   awaddr_latch,                           //latch address to burst_addr_gen
    output logic [2:0]              awsize_latch,
    output logic [1:0]              awburst_latch,
    output logic                    wr_step,                                //Announce wrote 1 beat, increasing address
    output logic                    wr_en                                   //In write process
);
    typedef enum logic [1:0] {IDLE, RECEIVE_DATA, RESPONSE} fsm; 
    fsm state, next_state;
    logic [ID_WIDTH-1:0] awid_latch;

    //LATCH CHARACTERISTIC OF DATA
    always_ff @(posedge aclk or negedge arst_n) begin
        if (!arst_n) begin
            state <= IDLE;
            awaddr_latch <= '0;
            awid_latch <= '0;
            awsize_latch <= '0;
            awburst_latch <= '0;
        end else begin
            state <= next_state;
            if (s_axi_awvalid && s_axi_awready) begin
                awid_latch <= s_axi_awid;
                awaddr_latch <= s_axi_awaddr;
                awsize_latch <= s_axi_awsize;
                awburst_latch <= s_axi_awburst;
            end
        end
    end

    //
    always_comb begin
        next_state = state;
        s_axi_awready = 1'b0;
        s_axi_wready = 1'b0;
        s_axi_bvalid = 1'b0;

        case (state) 
            IDLE: begin
                s_axi_awready = 1'b1;
                if (s_axi_awvalid && s_axi_awready) begin 
                    next_state = RECEIVE_DATA;
                end else next_state = IDLE;
            end
            RECEIVE_DATA: begin
                s_axi_wready = 1'b1;
                if (s_axi_wvalid && s_axi_wready && s_axi_wlast) begin
                    next_state = RESPONSE;
                end else next_state = RECEIVE_DATA;
            end
            RESPONSE: begin
                s_axi_bvalid = 1'b1;
                if (s_axi_bvalid && s_axi_bready) begin 
                    next_state = IDLE;
                end else next_state = RESPONSE;
            end
            default: next_state = IDLE;
        endcase
    end

    assign wr_en = (state != IDLE);
    assign wr_step = (state == RECEIVE_DATA) && (s_axi_wvalid && s_axi_wready);
    assign s_axi_bresp = 2'b00;
    assign s_axi_bid = awid_latch;

endmodule