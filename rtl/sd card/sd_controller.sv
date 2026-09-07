module sd_controller (
    input logic clk,
    input logic rst,

    input logic init_start,   
    input logic read_start,   
    input logic write_start,  
    input logic [31:0] sector_addr,  

    output logic ready,        
    output logic busy,         
    output logic error,        
    output logic [3:0] fsm_debug,  //for 7seg

    input logic [7:0] wr_data,      
    output logic [8:0] wr_addr,      
    output logic [7:0] rd_data,      
    output logic [8:0] rd_addr,      
    output logic rd_val,       

	 //spi SDcard pins
    output logic sd_clk,
    output logic sd_mosi,
    input logic sd_miso,
    output logic sd_cs
);

    logic spi_start;
    logic [7:0] spi_din;
    logic [7:0] spi_dout;
    logic spi_busy;
    logic spi_done;
    logic spi_slow;

    sd_spi u_spi (
        .clk(clk),
        .rst(rst),
        .start(spi_start),
        .din(spi_din),
        .dout(spi_dout),
        .busy(spi_busy),
        .done(spi_done),
        .slow_clk(spi_slow),
        .sd_clk(sd_clk),
        .sd_mosi(sd_mosi),
        .sd_miso(sd_miso)
    );

    typedef enum logic [4:0] {
        ST_IDLE,
        ST_POWER_ON,
        ST_CS_LOW_SYNC,
        ST_SEND_CMD,
        ST_WAIT_R1,
        ST_READ_R7,
        ST_CMD0,
        ST_CMD8,
        ST_CMD55,
        ST_ACMD41,
        ST_READY,
        ST_CMD24,
        ST_WR_TOKEN,
        ST_WR_DATA,
        ST_WR_CRC,
        ST_WR_RESP,
        ST_WR_BUSY,
        ST_CMD17,
        ST_RD_WAIT_TOKEN,
        ST_RD_DATA,
        ST_RD_CRC,
        ST_ERROR
    } state_t;

    state_t state;
    logic [5:0] curr_cmd; //command number
    logic [47:0] cmd_buf_reg; //command frame
    logic [2:0] cmd_idx;
    logic [15:0] byte_cnt;
    logic [7:0] clk_dummy_cnt;
    logic [7:0] cmd0_retry_cnt; //reset retry counter

    logic cs_reg;
    assign sd_cs = cs_reg;

    assign ready = (state == ST_READY);
    assign busy = (state != ST_IDLE && state != ST_READY && state != ST_ERROR);
    assign error = (state == ST_ERROR);

    always_comb begin
        case (state)
            ST_IDLE, ST_POWER_ON, ST_CS_LOW_SYNC: fsm_debug = 4'd0;
            ST_CMD0:                              fsm_debug = 4'd1;
            ST_CMD8, ST_READ_R7:                  fsm_debug = 4'd2;
            ST_CMD55, ST_ACMD41:                  fsm_debug = 4'd3;
            ST_CMD24, ST_WR_TOKEN, ST_WR_DATA, 
            ST_WR_CRC, ST_WR_RESP, ST_WR_BUSY:    fsm_debug = 4'd4; // 4 - saving in progress
            ST_READY:                             fsm_debug = 4'd8;
            ST_ERROR:                             fsm_debug = 4'd14; // 'E'
            default:                              fsm_debug = 4'd0;
        endcase
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            cs_reg <= 1'b1;
            spi_start <= 1'b0;
            spi_slow <= 1'b1;
            spi_din <= 8'hFF;
            cmd_buf_reg <= 48'd0;
            cmd_idx <= 3'd0;
            byte_cnt <= 16'd0;
            clk_dummy_cnt <= 8'd0;
            cmd0_retry_cnt <= 8'd0;
            curr_cmd <= 6'd0;
            wr_addr <= 9'd0;
            rd_addr <= 9'd0;
            rd_data <= 8'd0;
            rd_val <= 1'b0;
        end else begin
            spi_start <= 1'b0;
            rd_val <= 1'b0;

            case (state)
                ST_IDLE: begin
                    cs_reg <= 1'b1; //card disabled (active low)
                    spi_slow <= 1'b1;
                    if (init_start) begin
                        clk_dummy_cnt <= 8'd0;
                        cmd0_retry_cnt <= 8'd0;
                        state <= ST_POWER_ON;
                    end
                end

                ST_POWER_ON: begin // sends 20 bytes 0xFF to activate card logic
                    cs_reg <= 1'b1;
                    spi_slow <= 1'b1;
                    if (!spi_busy && !spi_start) begin
                        spi_din <= 8'hFF;
                        spi_start <= 1'b1;
                        if (clk_dummy_cnt == 8'd20) begin
                            clk_dummy_cnt <= 8'd0;
                            cs_reg <= 1'b0;
                            state <= ST_CS_LOW_SYNC;
                        end else begin
                            clk_dummy_cnt <= clk_dummy_cnt + 1'b1;
                        end
                    end
                end

                ST_CS_LOW_SYNC: begin // sends 1 empty sync byte
                    cs_reg <= 1'b0;
                    if (!spi_busy && !spi_start) begin
                        spi_din <= 8'hFF;
                        spi_start <= 1'b1;
                        if (spi_done) begin
                            state <= ST_CMD0;
                        end
                    end
                end

                ST_CMD0: begin // loads frame CMD0 (0x400000000095)
                    cs_reg <= 1'b0;
                    cmd_buf_reg <= {2'b01, 6'd0, 32'h0, 8'h95}; 
                    curr_cmd <= 6'd0;
                    cmd_idx <= 3'd0;
                    state <= ST_SEND_CMD;
                end

                ST_CMD8: begin // loads frame CMD8 (0x48000001AA87)
                    cs_reg <= 1'b0;
                    cmd_buf_reg <= {2'b01, 6'd8, 32'h000001AA, 8'h87}; 
                    curr_cmd <= 6'd8;
                    cmd_idx <= 3'd0;
                    state <= ST_SEND_CMD;
                end

                ST_READ_R7: begin // reads 4 remaining bytes of R7 response
                    cs_reg <= 1'b0;
                    if (!spi_busy && !spi_start) begin
                        spi_din <= 8'hFF;
                        spi_start <= 1'b1;
                        if (spi_done) begin
                            if (byte_cnt == 16'd3) begin
                                byte_cnt <= 16'd0;
                                state <= ST_CMD55;
                            end else begin
                                byte_cnt <= byte_cnt + 1'b1;
                            end
                        end
                    end
                end

                ST_CMD55: begin // loads frame CMD55 (0x770000000065)
                    cs_reg <= 1'b0;
                    cmd_buf_reg <= {2'b01, 6'd55, 32'h0, 8'h65}; 
                    curr_cmd <= 6'd55;
                    cmd_idx <= 3'd0;
                    state <= ST_SEND_CMD;
                end

                ST_ACMD41: begin // loads frame ACMD41 (0x694000000077)
                    cs_reg <= 1'b0;
                    cmd_buf_reg <= {2'b01, 6'd41, 32'h40000000, 8'h77}; 
                    curr_cmd <= 6'd41;
                    cmd_idx <= 3'd0;
                    state <= ST_SEND_CMD;
                end

                ST_SEND_CMD: begin // sends 6 bytes of 48-bit command frame byte by byte
                    cs_reg <= 1'b0;
                    if (!spi_busy && !spi_start) begin
                        case (cmd_idx)
                            3'd0: spi_din <= cmd_buf_reg[47:40]; // byte 0 - command index
                            3'd1: spi_din <= cmd_buf_reg[39:32]; // byte 1 - arg[31:24]
                            3'd2: spi_din <= cmd_buf_reg[31:24]; // byte 2 - arg[23:16]
                            3'd3: spi_din <= cmd_buf_reg[23:16]; // byte 3 - arg[15:8]
                            3'd4: spi_din <= cmd_buf_reg[15:8]; // byte 4 - arg[7:0]
                            3'd5: spi_din <= cmd_buf_reg[7:0]; // byte 5 - CRC + stop bit
                            default: spi_din <= 8'hFF;
                        endcase
                        
                        spi_start <= 1'b1;
                        if (cmd_idx == 3'd5) begin // frame fully transmitted
                            byte_cnt <= 16'd0;
                            state <= ST_WAIT_R1;
                        end else begin
                            cmd_idx <= cmd_idx + 1'b1;
                        end
                    end
                end

                ST_WAIT_R1: begin // polls SPI line waiting for R1 response
                    cs_reg <= 1'b0;
                    if (!spi_busy && !spi_start) begin
                        spi_din <= 8'hFF;
                        spi_start <= 1'b1;
                        if (spi_done) begin
                            if (spi_dout[7] == 1'b0) begin // valid R1 byte received
                                case (curr_cmd)
                                    6'd0: begin
                                        if (spi_dout == 8'h01) begin
                                            state <= ST_CMD8;
                                        end else if (cmd0_retry_cnt < 8'd50) begin
                                            cmd0_retry_cnt <= cmd0_retry_cnt + 1'b1;
                                            clk_dummy_cnt <= 8'd0;
                                            state <= ST_POWER_ON; 
                                        end else begin
                                            state <= ST_ERROR;
                                        end
                                    end

                                    6'd8: begin
                                        if (spi_dout == 8'h01) begin
                                            byte_cnt <= 16'd0;
                                            state <= ST_READ_R7;
                                        end else begin
                                            state <= ST_ERROR;
                                        end
                                    end

                                    6'd55: begin
                                        if (spi_dout <= 8'h01) state <= ST_ACMD41;
                                        else state <= ST_ERROR;
                                    end

                                    6'd41: begin
                                        if (spi_dout == 8'h00) begin //0x00 = init complete
                                            state <= ST_READY;
                                        end else if (spi_dout == 8'h01) begin
                                            state <= ST_CMD55;
                                        end else begin
                                            state <= ST_ERROR;
                                        end
                                    end

                                    6'd24: begin // write command response
                                        if (spi_dout == 8'h00) begin
                                            state <= ST_WR_TOKEN; // card accepted CMD24 -> ready for token
                                        end else begin
                                            state <= ST_ERROR;
                                        end
                                    end

                                    default: state <= ST_READY;
												
                                endcase
										  
                            end else if (byte_cnt == 16'd2000) begin // timeout guard
                                if (curr_cmd == 6'd0 && cmd0_retry_cnt < 8'd50) begin
                                    cmd0_retry_cnt <= cmd0_retry_cnt + 1'b1;
                                    clk_dummy_cnt <= 8'd0;
                                    state <= ST_POWER_ON;
                                end else begin
                                    state <= ST_ERROR;
                                end
                            end else begin
                                byte_cnt <= byte_cnt + 1'b1;
                            end
                        end
                    end
                end

                ST_READY: begin // ready for read/write requests
                    cs_reg <= 1'b0;
                    spi_slow <= 1'b0; 
                    if (write_start) begin
                        cmd_buf_reg <= {2'b01, 6'd24, sector_addr, 8'hFF}; // load CMD24
                        curr_cmd <= 6'd24;
                        cmd_idx <= 3'd0;
                        state <= ST_SEND_CMD;
                    end else if (read_start) begin
                        cmd_buf_reg <= {2'b01, 6'd17, sector_addr, 8'hFF}; // load CMD17
                        curr_cmd <= 6'd17;
                        cmd_idx <= 3'd0;
                        state <= ST_SEND_CMD;
                    end
                end

                // WRITE DATA SEQUENCE
                ST_WR_TOKEN: begin // transmits start block token
                    cs_reg <= 1'b0;
                    if (!spi_busy && !spi_start) begin
                        spi_din <= 8'hFE; // start token for single block
                        spi_start <= 1'b1;
                        wr_addr <= 9'd0;
                        byte_cnt <= 16'd0;
                        state <= ST_WR_DATA;
                    end
                end

                ST_WR_DATA: begin // streams 512 bytes of data to card
                    cs_reg <= 1'b0;
                    if (!spi_busy && !spi_start) begin
                        if (byte_cnt == 16'd512) begin // all bytes transferred
                            byte_cnt <= 16'd0;
                            state <= ST_WR_CRC;
                        end else begin
                            spi_din <= wr_data;//output byte from buffer
                            spi_start <= 1'b1;
                            byte_cnt <= byte_cnt + 1'b1;
                            wr_addr <= wr_addr + 1'b1; //increment buff address
                        end
                    end
                end

                ST_WR_CRC: begin //sends 2 dummy CRC bytes
                    cs_reg <= 1'b0;
                    if (!spi_busy && !spi_start) begin
                        if (byte_cnt == 16'd2) begin
                            byte_cnt <= 16'd0;
                            state <= ST_WR_RESP;
                        end else begin
                            spi_din <= 8'hFF; // dummy bytes
                            spi_start <= 1'b1;
                            byte_cnt <= byte_cnt + 1'b1;
                        end
                    end
                end

                ST_WR_RESP: begin //polls for data response token from card
                    cs_reg <= 1'b0;
                    if (!spi_busy && !spi_start) begin
                        spi_din <= 8'hFF;
                        spi_start <= 1'b1;
                        if (spi_done) begin
                            // waiting for response byte from card (diff from FF)
                            if (spi_dout != 8'hFF) begin
                                if ((spi_dout & 8'h1F) == 8'h05) begin //mask 0x1F: 0x05 data accepted
                                    byte_cnt <= 16'd0;
                                    state <= ST_WR_BUSY;
                                end else begin
                                    state <= ST_ERROR; // CRC or write error
                                end
                            end else if (byte_cnt == 16'd2000) begin
                                state <= ST_ERROR; // timeout
                            end else begin
                                byte_cnt <= byte_cnt + 1'b1;
                            end
                        end
                    end
                end

                ST_WR_BUSY: begin // waits for card internal flash programming (miso low)
                    cs_reg <= 1'b0;
                    if (!spi_busy && !spi_start) begin
                        spi_din <= 8'hFF;
                        spi_start <= 1'b1;
                        if (spi_done) begin
                            // miso = 0xFF (released) - write complete 
                            if (spi_dout == 8'hFF) begin
                                state <= ST_READY; 
                            end else if (byte_cnt == 16'd65535) begin
                                state <= ST_ERROR; // flash write timeout
                            end else begin
                                byte_cnt <= byte_cnt + 1'b1;
                            end
                        end
                    end
                end
					 
                // READ DATA SEQUENCE
                ST_RD_WAIT_TOKEN: begin //polls for start block token from card
                    cs_reg <= 1'b0;
                    if (!spi_busy && !spi_start) begin
                        spi_din <= 8'hFF;
                        spi_start <= 1'b1;
                        if (spi_done) begin
                            if (spi_dout == 8'hFE) begin //start token received
                                rd_addr <= 9'd0;
                                byte_cnt <= 16'd0;
                                state <= ST_RD_DATA;
                            end
                        end
                    end
                end

                ST_RD_DATA: begin //receives 512 bytes of adata
                    cs_reg <= 1'b0;
                    if (!spi_busy && !spi_start) begin
                        spi_din <= 8'hFF;
                        spi_start <= 1'b1;
                        if (spi_done) begin
                            rd_data <= spi_dout; //output data byte
                            rd_val <= 1'b1;
                            if (byte_cnt == 16'd511) begin // all bytes received
                                byte_cnt <= 16'd0;
                                state <= ST_RD_CRC;
                            end else begin
                                byte_cnt <= byte_cnt + 1'b1;
                                rd_addr <= rd_addr + 1'b1;
                            end
                        end
                    end
                end

                ST_RD_CRC: begin //reads and discards 2 bytes of CRC from card
                    cs_reg <= 1'b0;
                    if (!spi_busy && !spi_start) begin
                        spi_din <= 8'hFF;
                        spi_start <= 1'b1;
                        if (spi_done) begin
                            if (byte_cnt == 16'd1) state <= ST_READY;
                            else byte_cnt <= byte_cnt + 1'b1;
                        end
                    end
                end

                ST_ERROR: begin // fault state
                    cs_reg <= 1'b1; //release card
                    if (init_start) state <= ST_IDLE; //reset on new init request
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule