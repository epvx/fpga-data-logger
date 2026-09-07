module uart_rx #(
    parameter DATA_WIDTH = 8,
    parameter BAUD_RATE = 115200,
    parameter CLK_FREQ = 10_000_000
	 
)(
    input logic clk,
    input logic rst,

    input logic rx,

    output logic [DATA_WIDTH-1:0] rx_data,
    output logic rx_done
);

localparam int CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
localparam int CLK_CNT_WIDTH = (CLKS_PER_BIT <= 1) ? 1 : $clog2(CLKS_PER_BIT);
localparam int BIT_CNT_WIDTH = (DATA_WIDTH <= 1) ? 1 : $clog2(DATA_WIDTH);
localparam int HALF_CLKS_PER_BIT = CLKS_PER_BIT / 2;

logic [DATA_WIDTH-1:0] rx_buff;
logic [CLK_CNT_WIDTH-1:0] clk_cnt;
logic [BIT_CNT_WIDTH-1:0] bit_cnt;

logic [DATA_WIDTH-1:0] rx_buff_nxt;
logic [CLK_CNT_WIDTH-1:0] clk_cnt_nxt;
logic [BIT_CNT_WIDTH-1:0] bit_cnt_nxt;
logic [DATA_WIDTH-1:0] rx_data_nxt;
logic rx_done_nxt;

logic rx_sync1;
logic rx_sync2;

typedef enum logic [3:0] {
    IDLE = 4'b0001,
    START = 4'b0010,
    DATA = 4'b0100,
    STOP = 4'b1000
} state_t;

state_t state, state_nxt;

always_ff @(posedge clk) begin
    if (rst) begin
        state <= IDLE;
        clk_cnt <= 0;
        bit_cnt <= 0;
        rx_buff <= 0;
        rx_data <= 0;
        rx_done <= 0;
        rx_sync1 <= 1;
        rx_sync2 <= 1;
    end
    else begin
        state <= state_nxt;
        clk_cnt <= clk_cnt_nxt;
        bit_cnt <= bit_cnt_nxt;
        rx_buff <= rx_buff_nxt;
        rx_data <= rx_data_nxt;
        rx_done <= rx_done_nxt;
        rx_sync1 <= rx;
        rx_sync2 <= rx_sync1;
    end
end

always_comb begin

    state_nxt = state;
    clk_cnt_nxt = clk_cnt;
    bit_cnt_nxt = bit_cnt;
    rx_buff_nxt = rx_buff;
    rx_data_nxt = rx_data;
    rx_done_nxt = 0;

    case(state)

        IDLE: begin
		      clk_cnt_nxt = 0;
            bit_cnt_nxt = 0;
				if (rx_sync2 == 0) begin
					 state_nxt = START;
				end
        end
		  
		  START: begin
				if (clk_cnt < HALF_CLKS_PER_BIT - 1) begin
				    clk_cnt_nxt = clk_cnt + 1;
				end else begin
				    clk_cnt_nxt = 0;
				    if (rx_sync2 == 0) begin
						  bit_cnt_nxt = 0;
					     state_nxt = DATA;
					 end else begin
					     state_nxt = IDLE;
					 end
				end
			end
			
			DATA: begin
				 if (clk_cnt < CLKS_PER_BIT - 1) begin
				     clk_cnt_nxt = clk_cnt + 1;
				 end else begin
				     clk_cnt_nxt = 0;
					  rx_buff_nxt[bit_cnt] = rx_sync2;
					  if (bit_cnt < DATA_WIDTH - 1) begin
					      bit_cnt_nxt = bit_cnt + 1;
					  end else begin
					      bit_cnt_nxt = 0;
							state_nxt = STOP;
					  end
				  end			  
			end
			
			STOP: begin
             if (clk_cnt < CLKS_PER_BIT - 1) begin
                 clk_cnt_nxt = clk_cnt + 1;
             end else begin
                 clk_cnt_nxt = 0;
                 if (rx_sync2 == 1) begin
                     rx_data_nxt = rx_buff;
                     rx_done_nxt = 1;
                 end
				     state_nxt = IDLE;
				 end
         end
			
			default: begin
			    state_nxt = IDLE;
			end
			
    endcase
end

endmodule