module top(
    input logic clk,      
    input logic rst_n,   
 
    input logic [1:0] btn,     
    output logic [3:0] led,     // active low
    output logic [7:0] seg,     
    output logic [3:0] digit,   
 
    // UART
    input logic uart_rx,
    output logic uart_tx,
 
    // microSD
    input logic sd_miso,
    input logic [1:0] sd_det,
    output logic sd_clk,
    output logic sd_mosi,
    output logic sd_cs
);
 
    logic sys_rst;
    assign sys_rst = ~rst_n;
 
 
    // UART echo
 
    uart #(
        .DATA_WIDTH (8),
        .BAUD_RATE (115200),
        .CLK_FREQ (10_000_000)
    ) u_uart (
        .clk (clk),
        .rst (sys_rst),
        .rx (uart_rx),
        .tx_data (tx_data),
        .tx_start (tx_start),
        .rx_done (rx_done),
        .tx_done (tx_done),
        .tx (uart_tx),
        .rx_data (rx_data)
    );
 
    logic [7:0] tx_data;
    logic tx_start;
    logic tx_done;
    logic [7:0] rx_data;
    logic rx_done;
 
    always_ff @(posedge clk or posedge sys_rst) begin
        if (sys_rst) begin
            tx_data <= 8'h00;
            tx_start <= 1'b0;
        end else begin
            tx_start <= 1'b0;

            if (rx_done) begin
                tx_data  <= rx_data;
                tx_start <= 1'b1;
            end
        end
    end

    // microSD

    logic sd_init_start;
    logic sd_write_start;
    logic sd_read_start;
    logic [31:0] sd_sector_addr;
    logic sd_ready;
    logic sd_busy;
    logic sd_error;
    logic [3:0] sd_fsm_debug;
 
    logic [7:0] sd_wr_data;
    logic [8:0] sd_wr_addr;
    logic [7:0] sd_rd_data;
    logic [8:0] sd_rd_addr;
    logic sd_rd_val;
 
    assign sd_wr_data = 8'hFF;    // written data
    assign sd_sector_addr = 32'd0001; // sector address
    assign sd_read_start = 1'b0;
 
    sd_controller u_sd_ctrl (
        .clk(clk),
        .rst(sys_rst),
 
        .init_start(sd_init_start),
        .read_start(sd_read_start),
        .write_start(sd_write_start),
        .sector_addr(sd_sector_addr),
 
        .ready(sd_ready),
        .busy(sd_busy),
        .error(sd_error),
        .fsm_debug(sd_fsm_debug),
 
        .wr_data(sd_wr_data),
        .wr_addr(sd_wr_addr),
        .rd_data(sd_rd_data),
        .rd_addr(sd_rd_addr),
        .rd_val(sd_rd_val),
 
        .sd_clk(sd_clk),
        .sd_mosi(sd_mosi),
        .sd_miso(sd_miso),
        .sd_cs(sd_cs)
    );
 
    // button click detection
	 
    logic btn0_r1, btn0_r2;
    logic btn0_changed;
 
    always_ff @(posedge clk or posedge sys_rst) begin
        if (sys_rst) begin
            btn0_r1 <= 1'b0;
            btn0_r2 <= 1'b0;
        end else begin
            btn0_r1 <= btn[0];
            btn0_r2 <= btn0_r1;
        end
    end
	 
    assign btn0_changed = (btn0_r1 != btn0_r2); // button click to start
	 
	 typedef enum logic [1:0] { ST_START_INIT, ST_WAIT_READY, ST_WRITE, ST_DONE } test_st_t;
    test_st_t test_state;
    logic write_success;
    logic [19:0] power_on_timer; // for 10 MHz clk - 100ms = 1000000 cycles
 
    always_ff @(posedge clk or posedge sys_rst) begin
        if (sys_rst) begin
            test_state <= ST_START_INIT;
            sd_init_start <= 1'b0;
            sd_write_start <= 1'b0;
            write_success <= 1'b0;
            power_on_timer <= 20'd0;
        end else begin
            sd_init_start <= 1'b0;
            sd_write_start <= 1'b0;
 
            case (test_state)
                ST_START_INIT: begin
                    if (power_on_timer == 20'd1_000_000) begin
                        sd_init_start <= 1'b1;
                        test_state <= ST_WAIT_READY;
                    end else begin
                        power_on_timer <= power_on_timer + 1'b1;
                    end
                end
 
                ST_WAIT_READY: begin
                    if (sd_ready && btn0_changed) begin
                        sd_write_start <= 1'b1;
                        test_state <= ST_WRITE;
                    end
                end
 
                ST_WRITE: begin
                    if (!sd_write_start && sd_ready && !sd_busy) begin
                        write_success <= 1'b1;
                        test_state <= ST_DONE;
                    end
                end
 
                ST_DONE: begin
                end
            endcase
        end
    end
 
    // 7seg
	 
    always_comb begin
        digit = 4'b0001;
        case (sd_fsm_debug)
            4'd0: seg = 8'b00111111; // 0 - power on
            4'd1: seg = 8'b00000110; // 1 - CMD0
            4'd2: seg = 8'b01011011; // 2 - CMD8
            4'd3: seg = 8'b01001111; // 3 - ACMD41
            4'd4: seg = 8'b01100110; // 4 - data saving
            4'd8: seg = 8'b01111111; // 8 - READY
            4'd14:seg = 8'b01111001; // E - ERROR
            default: seg = 8'b00111111;
        endcase
    end
	 
	 always_comb begin
        led[0] = ~sd_ready;       // SD card ready
        led[1] = ~write_success;  // sector has been written
        led[2] = 1'b1;
        led[3] = 1'b1;
    end
 
endmodule