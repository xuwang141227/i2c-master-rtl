# i2c-master-rtl

可配置端口的 I2C Master RTL 与 testbench。

## 文件

- `rtl/i2c_master.v`
- `tb/tb_i2c_master.v`

## 接口

- `i2c_addr[6:0]`：I2C 从地址
- `reg_addr[7:0]`：寄存器地址
- `wr_data[7:0]`：写数据
- `read_data[7:0]`：读数据输出
- `wr_triger`：上升沿触发写
- `rd_triger`：上升沿触发读

## 说明

- 时序实现：
  - 写：`START + ADDR(W) + ACK + REG + ACK + DATA + ACK + STOP`
  - 读：`START + ADDR(W) + ACK + REG + ACK + RESTART + ADDR(R) + ACK + DATA + NACK + STOP`
- `busy` 表示控制器忙；`done` 在事务结束拉高 1 个 `clk` 周期。
