module sd_spi (
    input logic clk,  // 50 MHz
    input logic rst,       
    
    input logic start,    
    input logic [7:0] din, //mosi      
    output logic [7:0] dout, //miso   
    output logic busy,       
    output logic done, 
    
    input logic slow_clk, // 1 = 250kHz(init), 0= 12.5MHz(normal operation)
    
	 //physical pins
    output logic sd_clk,
    output logic sd_mosi,
    input logic sd_miso
);

    logic [7:0] clk_cnt;
    logic spi_tick;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_cnt <= 8'd0;
            spi_tick <= 1'b0;
        end else begin
            spi_tick <= 1'b0;
            if (slow_clk) begin
                if (clk_cnt >= 8'd99) begin // 250 kHz
                    clk_cnt <= 8'd0;
                    spi_tick <= 1'b1;
                end else begin
                    clk_cnt <= clk_cnt + 1'b1;
                end
            end else begin
                if (clk_cnt >= 8'd1) begin  // 12.5 MHz
                    clk_cnt <= 8'd0;
                    spi_tick <= 1'b1;
                end else begin
                    clk_cnt <= clk_cnt + 1'b1;
                end
            end
        end
    end

    typedef enum logic [1:0] {IDLE, XFER, DONE_ST} state_t;
    state_t state;

    logic [2:0] bit_cnt;
    logic [7:0] shift_tx;
    logic [7:0] shift_rx;

    assign busy = (state != IDLE);
    assign sd_mosi = shift_tx[7];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            sd_clk <= 1'b0;
            done <= 1'b0;
            bit_cnt <= 3'd0;
            shift_tx <= 8'hFF;
            shift_rx <= 8'h00;
            dout <= 8'h00;
        end else begin
            done <= 1'b0;

            case (state)
                IDLE: begin
                    sd_clk <= 1'b0;
                    if (start) begin
                        shift_tx <= din;
                        bit_cnt <= 3'd7;
                        state <= XFER;
                    end
                end

                XFER: begin
                    if (spi_tick) begin
                        if (!sd_clk) begin
                            sd_clk <= 1'b1; //rising edge
                            shift_rx <= {shift_rx[6:0], sd_miso}; //sample miso input bit into RX reg
                        end else begin
                            sd_clk <= 1'b0; //falling edge
                            shift_tx <= {shift_tx[6:0], 1'b1}; // shift TX reg left
                            
                            if (bit_cnt == 3'd0) begin //last bit transferred
                                state <= DONE_ST;
                            end else begin
                                bit_cnt <= bit_cnt - 1'b1; //move to nxt bit
                            end
                        end
                    end
                end

                DONE_ST: begin
                    if (spi_tick) begin
                        dout <= shift_rx; //latchfully assembled RX byte to dout output
                        done <= 1'b1;
                        sd_clk <= 1'b0; //clk ends low
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule