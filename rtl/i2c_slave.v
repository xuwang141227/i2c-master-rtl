`timescale 1ns/1ps

module i2c_slave #(
    parameter [6:0] PHY_ADDR = 7'h7f
)(
    input  wire clk,
    input  wire reset_n,
    input  wire scl,
    inout  wire sda
);
    // Both bus inputs are asynchronous to the 25 MHz system clock.
    (* ASYNC_REG = "TRUE" *) reg [1:0] scl_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] sda_sync;
    reg scl_prev;
    reg sda_prev;

    wire scl_rise =  scl_sync[1] & ~scl_prev;
    wire scl_fall = ~scl_sync[1] &  scl_prev;
    wire start_condition = scl_sync[1] & scl_prev &
                           sda_prev & ~sda_sync[1];
    wire stop_condition = scl_sync[1] & scl_prev &
                          ~sda_prev & sda_sync[1];

    reg sda_low;
    assign sda = sda_low ? 1'b0 : 1'bz;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            scl_sync <= 2'b11;
            sda_sync <= 2'b11;
            scl_prev <= 1'b1;
            sda_prev <= 1'b1;
        end else begin
            scl_sync <= {scl_sync[0], scl};
            sda_sync <= {sda_sync[0], sda};
            scl_prev <= scl_sync[1];
            sda_prev <= sda_sync[1];
        end
    end

    localparam [3:0]
        ST_IDLE       = 4'd0,
        ST_ADDRESS    = 4'd1,
        ST_REGISTER   = 4'd2,
        ST_WRITE      = 4'd3,
        ST_ACK        = 4'd4,
        ST_READ       = 4'd5,
        ST_READ_END   = 4'd6,
        ST_MASTER_ACK = 4'd7,
        ST_READ_NEXT  = 4'd8;

    reg [3:0] state;
    reg [3:0] after_ack;
    reg [1:0] ack_phase;
    reg [2:0] bit_count;
    reg [7:0] rx_shift;
    reg [7:0] tx_shift;
    reg [7:0] reg_ptr;
    reg [7:0] registers [0:255];
    wire [7:0] rx_byte = {rx_shift[6:0], sda_sync[1]};
    integer i;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state     <= ST_IDLE;
            after_ack <= ST_IDLE;
            ack_phase <= 2'd0;
            bit_count <= 3'd7;
            rx_shift  <= 8'd0;
            tx_shift  <= 8'd0;
            reg_ptr   <= 8'd0;
            sda_low   <= 1'b0;
            for (i = 0; i < 256; i = i + 1)
                registers[i] <= 8'd0;
        end else if (start_condition) begin
            state     <= ST_ADDRESS;
            bit_count <= 3'd7;
            rx_shift  <= 8'd0;
            sda_low   <= 1'b0;
        end else if (stop_condition) begin
            state   <= ST_IDLE;
            sda_low <= 1'b0;
        end else begin
            case (state)
                ST_ADDRESS, ST_REGISTER, ST_WRITE: begin
                    if (scl_rise) begin
                        rx_shift <= rx_byte;
                        if (bit_count == 0) begin
                            bit_count <= 3'd7;
                            ack_phase <= 2'd0;
                            case (state)
                                ST_ADDRESS: begin
                                    if (rx_byte[7:1] == PHY_ADDR) begin
                                        state <= ST_ACK;
                                        if (rx_byte[0]) begin
                                            tx_shift <= registers[reg_ptr];
                                            after_ack <= ST_READ;
                                        end else begin
                                            after_ack <= ST_REGISTER;
                                        end
                                    end else begin
                                        state <= ST_IDLE;
                                    end
                                end
                                ST_REGISTER: begin
                                    reg_ptr <= rx_byte;
                                    state <= ST_ACK;
                                    after_ack <= ST_WRITE;
                                end
                                ST_WRITE: begin
                                    registers[reg_ptr] <= rx_byte;
                                    reg_ptr <= reg_ptr + 8'd1;
                                    state <= ST_ACK;
                                    after_ack <= ST_WRITE;
                                end
                                default: state <= ST_IDLE;
                            endcase
                        end else begin
                            bit_count <= bit_count - 1'b1;
                        end
                    end
                end

                ST_ACK: begin
                    // Hold ACK through the entire ninth SCL high period.
                    case (ack_phase)
                        2'd0: if (scl_fall) begin
                            sda_low <= 1'b1;
                            ack_phase <= 2'd1;
                        end
                        2'd1: if (scl_rise)
                            ack_phase <= 2'd2;
                        2'd2: if (scl_fall) begin
                            sda_low <= (after_ack == ST_READ) & ~tx_shift[7];
                            state <= after_ack;
                        end
                        default: begin
                            state <= ST_IDLE;
                            sda_low <= 1'b0;
                        end
                    endcase
                end

                ST_READ: begin
                    if (scl_fall)
                        sda_low <= ~tx_shift[bit_count];
                    if (scl_rise) begin
                        if (bit_count == 0)
                            state <= ST_READ_END;
                        else
                            bit_count <= bit_count - 1'b1;
                    end
                end

                ST_READ_END: begin
                    if (scl_fall) begin
                        sda_low <= 1'b0;
                        state <= ST_MASTER_ACK;
                    end
                end

                ST_MASTER_ACK: begin
                    if (scl_rise) begin
                        if (!sda_sync[1]) begin
                            reg_ptr <= reg_ptr + 8'd1;
                            tx_shift <= registers[reg_ptr + 8'd1];
                            bit_count <= 3'd7;
                            state <= ST_READ_NEXT;
                        end else begin
                            state <= ST_IDLE;
                        end
                    end
                end

                ST_READ_NEXT: begin
                    if (scl_fall) begin
                        sda_low <= ~tx_shift[7];
                        state <= ST_READ;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                    sda_low <= 1'b0;
                end
            endcase
        end
    end
endmodule
