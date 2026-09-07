module uart_tx #(
    parameter DATA_WIDTH = 8,
    parameter BAUD_RATE = 115200,
    parameter CLK_FREQ = 10_000_000
)(
    input logic clk,
    input logic rst,

    input logic [DATA_WIDTH-1:0] tx_data,
    input logic tx_start,

    output logic tx,
    output logic tx_done
);

    localparam int CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    logic [DATA_WIDTH-1:0] tx_buff;
    logic [15:0] clk_cnt;
    logic [3:0] bit_cnt;

    typedef enum logic [1:0] { IDLE, START, DATA, STOP } state_t;
    state_t state;

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            clk_cnt <= '0;
            bit_cnt <= '0;
            tx_buff <= '0;
            tx <= 1'b1;
            tx_done <= 1'b0;
        end else begin
            tx_done <= 1'b0;

            case (state)
                IDLE: begin
                    tx <= 1'b1;
                    clk_cnt <= '0;
                    bit_cnt <= '0;
                    if (tx_start) begin
                        tx_buff <= tx_data;
                        state <= START;
                    end
                end

                START: begin
                    tx <= 1'b0; //start bit
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end else begin
                        clk_cnt <= '0;
                        state <= DATA;
                    end
                end

                DATA: begin
                    tx <= tx_buff[bit_cnt];
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end else begin
                        clk_cnt <= '0;
                        if (bit_cnt < DATA_WIDTH - 1) begin
                            bit_cnt <= bit_cnt + 1'b1;
                        end else begin
                            bit_cnt <= '0;
                            state <= STOP;
                        end
                    end
                end

                STOP: begin
                    tx <= 1'b1; //stop bit
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end else begin
                        clk_cnt <= '0;
                        tx_done <= 1'b1;
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule