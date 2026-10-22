module i2c_master #(
    parameter CLK_FREQ_HZ = 25_000_000,
    parameter I2C_FREQ_HZ = 100_000
)(
    input  wire       clk,
    input  wire       reset_n,

    inout  wire       sda,
    output wire       scl,

    input  wire [6:0] i2c_addr,
    input  wire [7:0] reg_addr,
    input  wire [7:0] wr_data,
    output reg  [7:0] read_data,

    input  wire       wr_triger,
    input  wire       rd_triger,
    output reg        busy,
    output reg        done,
    output reg        ack_error
);

    localparam integer DIV_HALF = (CLK_FREQ_HZ/(I2C_FREQ_HZ*2));

    reg [15:0] div_cnt;
    reg        scl_int;
    reg        phase_en;

    reg sda_oe;
    reg sda_out;
    wire sda_in;

    assign sda    = sda_oe ? sda_out : 1'bz;
    assign sda_in = sda;
    assign scl    = scl_int;

    reg wr_d0, wr_d1;
    reg rd_d0, rd_d1;

    wire wr_rise = wr_d0 & ~wr_d1;
    wire rd_rise = rd_d0 & ~rd_d1;

    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            wr_d0 <= 1'b0; wr_d1 <= 1'b0;
            rd_d0 <= 1'b0; rd_d1 <= 1'b0;
        end else begin
            wr_d0 <= wr_triger; wr_d1 <= wr_d0;
            rd_d0 <= rd_triger; rd_d1 <= rd_d0;
        end
    end

    localparam [5:0]
        ST_IDLE            = 6'd0,
        ST_START           = 6'd1,
        ST_SEND_DEVW       = 6'd2,
        ST_ACK_DEVW        = 6'd3,
        ST_SEND_REG        = 6'd4,
        ST_ACK_REG         = 6'd5,
        ST_SEND_DATA       = 6'd6,
        ST_ACK_DATA        = 6'd7,
        ST_RESTART_1       = 6'd8,
        ST_RESTART_2       = 6'd9,
        ST_SEND_DEVR       = 6'd10,
        ST_ACK_DEVR        = 6'd11,
        ST_RECV_DATA       = 6'd12,
        ST_SEND_MACK       = 6'd13,
        ST_STOP_1          = 6'd14,
        ST_STOP_2          = 6'd15,
        ST_DONE            = 6'd16;

    reg [5:0] state;
    reg       op_read;
    reg [7:0] shifter;
    reg [2:0] bit_cnt;

    wire tick = (div_cnt == DIV_HALF-1);

    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            div_cnt   <= 16'd0;
            scl_int   <= 1'b1;
            phase_en  <= 1'b0;
            state     <= ST_IDLE;
            sda_oe    <= 1'b1;
            sda_out   <= 1'b1;
            busy      <= 1'b0;
            done      <= 1'b0;
            ack_error <= 1'b0;
            op_read   <= 1'b0;
            shifter   <= 8'h00;
            bit_cnt   <= 3'd7;
            read_data <= 8'h00;
        end else begin
            done <= 1'b0;

            if(!phase_en) begin
                scl_int <= 1'b1;
                div_cnt <= 16'd0;

                if(state==ST_IDLE) begin
                    if(wr_rise) begin
                        busy      <= 1'b1;
                        ack_error <= 1'b0;
                        op_read   <= 1'b0;
                        state     <= ST_START;
                    end else if(rd_rise) begin
                        busy      <= 1'b1;
                        ack_error <= 1'b0;
                        op_read   <= 1'b1;
                        state     <= ST_START;
                    end
                end else begin
                    phase_en <= 1'b1;
                end
            end else begin
                if(tick) begin
                    div_cnt <= 16'd0;
                    scl_int <= ~scl_int;

                    if(!scl_int) begin
                        case(state)
                            ST_START: begin
                                sda_oe  <= 1'b1;
                                sda_out <= 1'b0;
                                shifter <= {i2c_addr,1'b0};
                                bit_cnt <= 3'd7;
                                state   <= ST_SEND_DEVW;
                            end

                            ST_SEND_DEVW, ST_SEND_REG, ST_SEND_DATA, ST_SEND_DEVR: begin
                                sda_oe  <= 1'b1;
                                sda_out <= shifter[bit_cnt];
                            end

                            ST_ACK_DEVW, ST_ACK_REG, ST_ACK_DATA, ST_ACK_DEVR: begin
                                sda_oe  <= 1'b0;
                            end

                            ST_RECV_DATA: begin
                                sda_oe <= 1'b0;
                            end

                            ST_SEND_MACK: begin
                                sda_oe  <= 1'b1;
                                sda_out <= 1'b1;
                            end

                            ST_RESTART_1: begin
                                sda_oe  <= 1'b1;
                                sda_out <= 1'b1;
                            end

                            ST_RESTART_2: begin
                                sda_oe  <= 1'b1;
                                sda_out <= 1'b0;
                                shifter <= {i2c_addr,1'b1};
                                bit_cnt <= 3'd7;
                                state   <= ST_SEND_DEVR;
                            end

                            ST_STOP_1: begin
                                sda_oe  <= 1'b1;
                                sda_out <= 1'b0;
                            end

                            ST_STOP_2: begin
                                sda_oe  <= 1'b1;
                                sda_out <= 1'b1;
                                state   <= ST_DONE;
                            end
                        endcase
                    end else begin
                        case(state)
                            ST_SEND_DEVW, ST_SEND_REG, ST_SEND_DATA, ST_SEND_DEVR: begin
                                if(bit_cnt==0) begin
                                    case(state)
                                        ST_SEND_DEVW: state <= ST_ACK_DEVW;
                                        ST_SEND_REG : state <= ST_ACK_REG;
                                        ST_SEND_DATA: state <= ST_ACK_DATA;
                                        ST_SEND_DEVR: state <= ST_ACK_DEVR;
                                    endcase
                                end else begin
                                    bit_cnt <= bit_cnt - 1'b1;
                                end
                            end

                            ST_ACK_DEVW: begin
                                if(sda_in) ack_error <= 1'b1;
                                shifter <= reg_addr;
                                bit_cnt <= 3'd7;
                                state   <= ST_SEND_REG;
                            end

                            ST_ACK_REG: begin
                                if(sda_in) ack_error <= 1'b1;
                                if(op_read) begin
                                    state <= ST_RESTART_1;
                                end else begin
                                    shifter <= wr_data;
                                    bit_cnt <= 3'd7;
                                    state   <= ST_SEND_DATA;
                                end
                            end

                            ST_ACK_DATA: begin
                                if(sda_in) ack_error <= 1'b1;
                                state <= ST_STOP_1;
                            end

                            ST_ACK_DEVR: begin
                                if(sda_in) ack_error <= 1'b1;
                                bit_cnt   <= 3'd7;
                                read_data <= 8'h00;
                                state     <= ST_RECV_DATA;
                            end

                            ST_RECV_DATA: begin
                                read_data[bit_cnt] <= sda_in;
                                if(bit_cnt==0) begin
                                    state <= ST_SEND_MACK;
                                end else begin
                                    bit_cnt <= bit_cnt - 1'b1;
                                end
                            end

                            ST_SEND_MACK: begin
                                state <= ST_STOP_1;
                            end

                            ST_RESTART_1: begin
                                state <= ST_RESTART_2;
                            end

                            ST_DONE: begin
                                busy     <= 1'b0;
                                done     <= 1'b1;
                                phase_en <= 1'b0;
                                state    <= ST_IDLE;
                            end
                        endcase
                    end
                end else begin
                    div_cnt <= div_cnt + 1'b1;
                end
            end
        end
    end

endmodule
