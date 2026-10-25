`timescale 1ns/1ps

module tb_i2c_slave;
    reg clk = 1'b0;
    reg reset_n = 1'b0;
    reg scl = 1'b1;
    reg master_sda_low = 1'b0;
    tri1 sda;
    assign sda = master_sda_low ? 1'b0 : 1'bz;
    always #20 clk = ~clk;

    i2c_slave dut (
        .clk(clk), .reset_n(reset_n), .scl(scl), .sda(sda)
    );
    i2c_slave #(.PHY_ADDR(7'h52)) dut_configured (
        .clk(clk), .reset_n(reset_n), .scl(scl), .sda(sda)
    );

    integer checks = 0;
    integer address;
    reg [7:0] value;
    reg [7:0] expected;

    task start_bus;
        begin
            scl = 1'b0;
            master_sda_low = 1'b0;
            #5000;
            scl = 1'b1;
            #5000;
            master_sda_low = 1'b1;
            #5000;
            scl = 1'b0;
        end
    endtask

    task stop_bus;
        begin
            scl = 1'b0;
            master_sda_low = 1'b1;
            #5000;
            scl = 1'b1;
            #5000;
            master_sda_low = 1'b0;
            #5000;
            if (sda !== 1'b1)
                $fatal(1, "Slave did not release SDA after STOP");
        end
    endtask

    task send_bit;
        input data_bit;
        begin
            master_sda_low = ~data_bit;
            #5000;
            scl = 1'b1;
            #5000;
            scl = 1'b0;
        end
    endtask

    task send_byte;
        input [7:0] data_byte;
        input expect_ack;
        integer bit_index;
        begin
            for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1)
                send_bit(data_byte[bit_index]);
            master_sda_low = 1'b0;
            #5000;
            scl = 1'b1;
            #2500;
            if (sda !== !expect_ack)
                $fatal(1, "ACK mismatch: byte=%02h expected_ack=%b SDA=%b at %t",
                       data_byte, expect_ack, sda, $time);
            checks = checks + 1;
            #2500;
            scl = 1'b0;
        end
    endtask

    task receive_byte;
        output [7:0] data_byte;
        input master_ack;
        integer bit_index;
        begin
            master_sda_low = 1'b0;
            for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1) begin
                #5000;
                scl = 1'b1;
                #2500;
                if (sda !== 1'b0 && sda !== 1'b1)
                    $fatal(1, "Unknown SDA while reading");
                data_byte[bit_index] = sda;
                #2500;
                scl = 1'b0;
            end
            send_bit(!master_ack);
            master_sda_low = 1'b0;
        end
    endtask

    task set_pointer;
        input [6:0] phy;
        input [7:0] reg_address;
        begin
            start_bus;
            send_byte({phy, 1'b0}, 1'b1);
            send_byte(reg_address, 1'b1);
        end
    endtask

    task write_register;
        input [6:0] phy;
        input [7:0] reg_address;
        input [7:0] data_byte;
        begin
            set_pointer(phy, reg_address);
            send_byte(data_byte, 1'b1);
            stop_bus;
        end
    endtask

    task check_register;
        input [6:0] phy;
        input [7:0] reg_address;
        input [7:0] expected_byte;
        reg [7:0] actual_byte;
        begin
            set_pointer(phy, reg_address);
            start_bus;
            send_byte({phy, 1'b1}, 1'b1);
            receive_byte(actual_byte, 1'b0);
            stop_bus;
            if (actual_byte !== expected_byte)
                $fatal(1, "Read mismatch: PHY=%02h reg=%02h got=%02h expected=%02h",
                       phy, reg_address, actual_byte, expected_byte);
            checks = checks + 1;
        end
    endtask

    task check_value;
        input [7:0] actual_byte;
        input [7:0] expected_byte;
        begin
            if (actual_byte !== expected_byte)
                $fatal(1, "Burst read mismatch: got=%02h expected=%02h",
                       actual_byte, expected_byte);
            checks = checks + 1;
        end
    endtask

    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_i2c_slave.vcd");
            $dumpvars(0, tb_i2c_slave);
        end
        #503;
        reset_n = 1'b1;
        #1000;

        // Check reset contents through the bus, including all 8 address bits.
        for (address = 0; address < 256; address = address + 1)
            check_register(7'h7f, address[7:0], 8'h00);
        $display("[PASS] All 256 registers reset to zero");

        for (address = 0; address < 256; address = address + 1) begin
            expected = address[7:0] ^ 8'ha5;
            write_register(7'h7f, address[7:0], expected);
            write_register(7'h52, address[7:0], ~expected);
        end
        for (address = 0; address < 256; address = address + 1) begin
            expected = address[7:0] ^ 8'ha5;
            check_register(7'h7f, address[7:0], expected);
            check_register(7'h52, address[7:0], ~expected);
        end
        $display("[PASS] All 256 addresses read/write on two parameterized PHY addresses");

        start_bus;
        send_byte({7'h51, 1'b0}, 1'b0);
        send_byte(8'h00, 1'b0);
        send_byte(8'hff, 1'b0);
        stop_bus;
        start_bus;
        send_byte({7'h51, 1'b1}, 1'b0);
        stop_bus;
        check_register(7'h7f, 8'h00, 8'ha5);
        check_register(7'h52, 8'h00, 8'h5a);
        $display("[PASS] Unmatched PHY address is NACKed and cannot write");

        // Sequential transfer and 0xff -> 0x00 wraparound.
        set_pointer(7'h52, 8'hff);
        send_byte(8'h96, 1'b1);
        send_byte(8'h69, 1'b1);
        stop_bus;
        set_pointer(7'h52, 8'hff);
        start_bus;
        send_byte({7'h52, 1'b1}, 1'b1);
        receive_byte(value, 1'b1);
        check_value(value, 8'h96);
        receive_byte(value, 1'b0);
        check_value(value, 8'h69);
        // A NACK terminates transmission even if extra clocks follow.
        receive_byte(value, 1'b0);
        check_value(value, 8'hff);
        stop_bus;
        $display("[PASS] Burst ACK, final NACK, SDA release and pointer wraparound");

        // STOP and repeated START must discard an incomplete write byte.
        set_pointer(7'h7f, 8'h23);
        send_bit(1'b0);
        send_bit(1'b1);
        send_bit(1'b0);
        stop_bus;
        check_register(7'h7f, 8'h23, 8'h86);
        set_pointer(7'h7f, 8'h23);
        send_bit(1'b0);
        send_bit(1'b1);
        start_bus;
        send_byte({7'h7f, 1'b1}, 1'b1);
        receive_byte(value, 1'b0);
        check_value(value, 8'h86);
        stop_bus;

        // Abort an active read by repeated START while SDA is released.
        write_register(7'h7f, 8'h24, 8'hff);
        set_pointer(7'h7f, 8'h24);
        start_bus;
        send_byte({7'h7f, 1'b1}, 1'b1);
        #5000;
        scl = 1'b1;
        #5000;
        master_sda_low = 1'b1;
        #5000;
        scl = 1'b0;
        send_byte({7'h7f, 1'b0}, 1'b1);
        send_byte(8'h24, 1'b1);
        send_byte(8'h3c, 1'b1);
        stop_bus;
        check_register(7'h7f, 8'h24, 8'h3c);
        $display("[PASS] STOP/repeated START abort partial transfers and recover");

        set_pointer(7'h7f, 8'h24);
        start_bus;
        send_byte({7'h7f, 1'b1}, 1'b1);
        #1000;
        reset_n = 1'b0;
        #503;
        master_sda_low = 1'b0;
        scl = 1'b1;
        #1000;
        if (sda !== 1'b1)
            $fatal(1, "Reset did not release SDA");
        reset_n = 1'b1;
        #1000;
        for (address = 0; address < 256; address = address + 1) begin
            check_register(7'h7f, address[7:0], 8'h00);
            check_register(7'h52, address[7:0], 8'h00);
        end
        $display("[PASS] Reset during read releases SDA and clears both register banks");
        $display("[PASS] %0d checks; clk=25MHz, SCL=100kHz", checks);
        $finish;
    end

    initial begin
        #1000000000;
        $fatal(1, "Simulation watchdog timeout");
    end
endmodule
