IVERILOG ?= iverilog
VVP ?= vvp
BUILD_DIR ?= build

.PHONY: sim-slave
sim-slave:
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s tb_i2c_slave -o $(BUILD_DIR)/tb_i2c_slave rtl/i2c_slave.v tb/tb_i2c_slave.v
	cd $(BUILD_DIR) && $(VVP) tb_i2c_slave $(VVP_ARGS)
