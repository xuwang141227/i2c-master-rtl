# i2c-master-rtl

可配置端口的 I2C Master RTL 与 testbench。

另提供可综合的 I2C Slave：25 MHz 系统时钟、100 kHz SCL，支持 256 个 8 bit 内部寄存器。

## 文件

- `rtl/i2c_master.v`
- `tb/tb_i2c_master.v`
- `rtl/i2c_slave.v`
- `tb/tb_i2c_slave.v`

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

## I2C Slave

```verilog
i2c_slave #(
    .PHY_ADDR(7'h52)  // 7 bit PHY address, configurable per instance
) u_i2c_slave (
    .clk(clk_25m),
    .reset_n(reset_n),
    .scl(i2c_scl),
    .sda(i2c_sda)
);
```

- `PHY_ADDR[6:0]` 是编译/综合时配置的 7 位从机地址（不含 R/W 位），默认 `7'h7F`，仅响应该参数指定的地址；地址不匹配时不应答。
- `clk` 为 25 MHz；`reset_n` 为低有效异步复位，复位后全部 256 个寄存器及地址指针清零，SDA 释放。
- `scl` 由外部 Master 提供，目标速率为 100 kHz；Slave 不产生 SCL，也不进行时钟拉伸。SCL/SDA 经双触发器同步后在 `clk` 域检测边沿。
- `sda` 为开漏接口，仅输出低电平或高阻态；板级 SDA/SCL 需要上拉电阻。
- 寄存器地址为完整 8 位，`0x00`～`0xFF` 全部有效，数据为 8 位，均 MSB first。寄存器仅通过 I2C 访问。

单字节写入：

```text
START + PHY_ADDR(W) + ACK + REG_ADDR + ACK + DATA + ACK + STOP
```

单字节读取（设置地址后使用 repeated START，地址指针保留）：

```text
START + PHY_ADDR(W) + ACK + REG_ADDR + ACK
      + repeated START + PHY_ADDR(R) + ACK + DATA + NACK + STOP
```

还支持连续读写：每接收一个完整写数据字节后指针加一；连续读时，Master ACK 后指针加一并继续输出下一字节，NACK 后停止输出并释放 SDA。指针从 `0xFF` 回绕到 `0x00`。完整写数据字节在第 8 个 SCL 上升沿写入，未收完的字节遇到 STOP/repeated START 会被丢弃；已写入的数据不回滚。

### Slave 仿真

安装 Icarus Verilog 后运行：

```sh
make sim-slave
# Optional VCD waveform: build/tb_i2c_slave.vcd
make sim-slave VVP_ARGS=+vcd
```

自检 testbench 使用 25 MHz 系统时钟和 100 kHz 总线，实例化默认地址和 `7'h52` 两个 Slave，覆盖全部 256 个地址的复位值、独立读写、重复起始读取、错误 PHY 地址 NACK、连续读写及地址回绕、Master NACK 后释放 SDA、部分传输中止恢复和传输中复位。失败时 `$fatal` 返回非零退出码，成功时打印 `[PASS]`。
