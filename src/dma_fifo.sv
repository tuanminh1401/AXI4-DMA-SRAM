module dma_fifo #(
    parameter DATA_WIDTH = 32,
    parameter FF_DEPTH = 16,
    parameter ADDR_WIDTH = $clog2(FF_DEPTH)
)(
    input logic                     clk,
    input logic                     rst_n,

    //(READ_ENGINE) WRITE DATA FROM READ_ENGINE TO FIFO
    input logic                     wr_en,
    input logic [DATA_WIDTH-1:0]    wr_data,

    output logic                    full,                           //connect to read_engine to block adding more

    //(WRITE_ENGINE) WRITE_ENGINE WANT TO TAKE DATA OUT
    input logic                     rd_en,
    output logic [DATA_WIDTH-1:0]   rd_data,

    output logic                    empty,                          //connect to write_engine to block taking more

    output logic [ADDR_WIDTH:0]     fifo_count                      //connect to write_engine and read_engine to announce how many word in FIFO
);
    //INTERN MEMORY 
    logic [DATA_WIDTH-1:0] mem [0:FF_DEPTH-1];

    //write and read pointer
    logic [ADDR_WIDTH-1:0]  wr_ptr;
    logic [ADDR_WIDTH-1:0]  rd_ptr;

    //Counting word in fifo
    logic [ADDR_WIDTH:0]    count;

    assign full = (count == FF_DEPTH);
    assign empty = (count == '0);
    assign fifo_count = count;

    //Push into FIFO
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
        end else begin
            if (wr_en && !full) begin
                mem[wr_ptr] <= wr_data;
                wr_ptr <= wr_ptr + 1;
            end
        end
    end

    //Pop into write_engine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= '0;
            rd_data <= '0;
        end else begin
            if (rd_en && !empty) begin
                rd_data <= mem[rd_ptr];
                rd_ptr <= rd_ptr + 1;
            end
        end
    end

    //counting
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= '0;
        end else begin
            case ({wr_en && !full, rd_en && !empty})
                2'b10: count <= count + 1;
                2'b01: count <= count - 1;
                default: count <= count;
            endcase
        end
    end

endmodule