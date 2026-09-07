module uart #(
    parameter DATA_WIDTH = 8,
    parameter BAUD_RATE = 115200,
    parameter CLK_FREQ = 10_000_000
	 
)(
    input logic clk,
    input logic rst,
    input logic rx,
	 input logic [DATA_WIDTH-1:0] tx_data,
	 input logic tx_start,
	 
	 output logic rx_done,
	 output logic tx_done,
	 output logic tx,
    output logic [DATA_WIDTH-1:0] rx_data

);


uart_tx #(
    .DATA_WIDTH(DATA_WIDTH),
    .BAUD_RATE(BAUD_RATE),
    .CLK_FREQ(CLK_FREQ)
) u_uart_tx (
    .clk(clk),
    .rst(rst),
    .tx_data(tx_data),
    .tx_start(tx_start),
    .tx(tx),
    .tx_done(tx_done)
);

uart_rx #(
    .DATA_WIDTH(DATA_WIDTH),
    .BAUD_RATE(BAUD_RATE),
    .CLK_FREQ(CLK_FREQ)
) u_uart_rx (
    .clk(clk),
    .rst(rst),
    .rx(rx),
    .rx_data(rx_data),
    .rx_done(rx_done)
);

endmodule