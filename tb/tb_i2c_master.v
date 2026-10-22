`timescale 1ns/1ps

module tb_i2c_master;
    reg clk;
    reg reset_n;

    tri1 sda;
    wire scl;

    reg  [6:0] i2c_addr;
    reg  [7:0] reg_addr;
    reg  [7:0] wr_data;
    wire [7:0] read_data;

    reg wr_triger;
    reg rd_triger;
    wire busy;
    wire done;
    wire ack_error;

    i2c_master #(
        .CLK_FREQ_HZ(25_000_000),
        .I2C_FREQ_HZ(100_000)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .sda(sda),
        .scl(scl),
        .i2c_addr(i2c_addr),
        .reg_addr(reg_addr),
        .wr_data(wr_data),
        .read_data(read_data),
        .wr_triger(wr_triger),
        .rd_triger(rd_triger),
        .busy(busy),
        .done(done),
        .ack_error(ack_error)
    );

    i2c_slave_model #(
        .SLV_ADDR(7'h50)
    ) u_slave (
        .scl(scl),
        .sda(sda)
    );

    initial begin
        clk = 0;
        forever #20 clk = ~clk; // 25MHz
    end

    initial begin
        reset_n   = 0;
        wr_triger = 0;
        rd_triger = 0;
        i2c_addr  = 7'h50;
        reg_addr  = 8'h10;
        wr_data   = 8'hA5;

        #500;
        reset_n = 1;

        // write: reg 0x10 <= 0xA5
        pulse_wr();
        wait_done();

        // read: reg 0x10 -> should be 0xA5
        pulse_rd();
        wait_done();

        if(read_data !== 8'hA5) begin
            $display("[TB][FAIL] read_data=0x%02h, expect=0xA5", read_data);
        end else begin
            $display("[TB][PASS] read_data=0x%02h", read_data);
        end

        // change write data and verify again
        wr_data = 8'h3C;
        pulse_wr();
        wait_done();

        pulse_rd();
        wait_done();

        if(read_data !== 8'h3C) begin
            $display("[TB][FAIL] read_data=0x%02h, expect=0x3C", read_data);
        end else begin
            $display("[TB][PASS] read_data=0x%02h", read_data);
        end

        #1000;
        $finish;
    end

    task pulse_wr;
        begin
            @(posedge clk);
            wr_triger <= 1'b1;
            @(posedge clk);
            wr_triger <= 1'b0;
        end
    endtask

    task pulse_rd;
        begin
            @(posedge clk);
            rd_triger <= 1'b1;
            @(posedge clk);
            rd_triger <= 1'b0;
        end
    endtask

    task wait_done;
        begin
            wait(done==1'b1);
            @(posedge clk);
        end
    endtask

endmodule

module i2c_slave_model #(
    parameter [6:0] SLV_ADDR = 7'h50
)(
    input  wire scl,
    inout  wire sda
);
    reg sda_oe;
    reg sda_out;
    assign sda = sda_oe ? sda_out : 1'bz;

    wire sda_in = sda;

    reg sda_d;
    always @(posedge scl or negedge scl) sda_d <= sda_in;

    wire start_cond = (sda_d==1'b1 && sda_in==1'b0 && scl==1'b1);
    wire stop_cond  = (sda_d==1'b0 && sda_in==1'b1 && scl==1'b1);

    reg [3:0] bit_cnt;
    reg [7:0] rx_byte;
    reg [7:0] tx_byte;
    reg [7:0] mem [0:255];
    reg [7:0] reg_ptr;

    reg [2:0]
        ST_IDLE=0,
        ST_ADDR=1,
        ST_REG =2,
        ST_WRD =3,
        ST_RDD =4;

    reg [2:0] st;
    reg       rw;

    integer i;
    initial begin
        sda_oe  = 1'b0;
        sda_out = 1'b1;
        bit_cnt = 0;
        rx_byte = 0;
        tx_byte = 0;
        reg_ptr = 0;
        st = ST_IDLE;
        rw = 1'b0;
        for(i=0;i<256;i=i+1) mem[i]=0;
    end

    always @(negedge sda) begin
        if(scl===1'b1) begin
            st      <= ST_ADDR;
            bit_cnt <= 4'd7;
            sda_oe  <= 1'b0;
        end
    end

    always @(posedge sda) begin
        if(scl===1'b1) begin
            st     <= ST_IDLE;
            sda_oe <= 1'b0;
        end
    end

    always @(posedge scl) begin
        case(st)
            ST_ADDR, ST_REG, ST_WRD: begin
                rx_byte[bit_cnt] <= sda_in;
                if(bit_cnt==0) bit_cnt <= 4'd8;
                else bit_cnt <= bit_cnt - 1'b1;
            end
            ST_RDD: begin
                if(bit_cnt==0) begin
                    bit_cnt <= 4'd8;
                    sda_oe  <= 1'b0;
                end else begin
                    bit_cnt <= bit_cnt - 1'b1;
                end
            end
        endcase
    end

    always @(negedge scl) begin
        case(st)
            ST_ADDR: begin
                if(bit_cnt==4'd8) begin
                    rw <= rx_byte[0];
                    if(rx_byte[7:1]==SLV_ADDR) begin
                        sda_oe  <= 1'b1;
                        sda_out <= 1'b0;
                        if(rx_byte[0]) begin
                            st      <= ST_RDD;
                            tx_byte <= mem[reg_ptr];
                            bit_cnt <= 4'd7;
                        end else begin
                            st      <= ST_REG;
                            bit_cnt <= 4'd7;
                        end
                    end else begin
                        sda_oe <= 1'b0;
                        st     <= ST_IDLE;
                    end
                end
            end

            ST_REG: begin
                if(bit_cnt==4'd8) begin
                    reg_ptr <= rx_byte;
                    sda_oe  <= 1'b1;
                    sda_out <= 1'b0;
                    st      <= ST_WRD;
                    bit_cnt <= 4'd7;
                end
            end

            ST_WRD: begin
                if(bit_cnt==4'd8) begin
                    mem[reg_ptr] <= rx_byte;
                    sda_oe       <= 1'b1;
                    sda_out      <= 1'b0;
                    bit_cnt      <= 4'd7;
                end
            end

            ST_RDD: begin
                if(bit_cnt<=4'd7) begin
                    sda_oe  <= 1'b1;
                    sda_out <= tx_byte[bit_cnt];
                end else begin
                    sda_oe <= 1'b0;
                    st     <= ST_IDLE;
                end
            end
        endcase
    end
endmodule
