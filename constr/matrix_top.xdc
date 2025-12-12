# ==============================================================================
# 时钟约束
# ==============================================================================
# Ego1 板载时钟通常为 100MHz (周期 10ns)
set_property PACKAGE_PIN P17 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]

# 原始板载时钟 100MHz
create_clock -period 10.000 -name clk [get_ports clk]

# 生成时钟：顶层内将 clk 二分频得到 sys_clk（50MHz），用于大部分逻辑
# 约束在 sys_clk 网络上（代码中已添加 KEEP 属性确保不被优化）
# 如果综合后找不到，可以尝试：get_nets -hierarchical -filter {NAME =~ "*sys_clk*"}
create_generated_clock -name sys_clk \
    -source [get_ports clk] \
    -divide_by 2 \
    [get_nets sys_clk]

# ==============================================================================
# 复位信号
# ==============================================================================
set_property PACKAGE_PIN P15 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# ==============================================================================
# UART 引脚
# ==============================================================================
set_property PACKAGE_PIN N5 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]

set_property PACKAGE_PIN T4 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

# ==============================================================================
# 8位拨码开关 (sw[7:0])
# ==============================================================================

    set_property PACKAGE_PIN R1 [get_ports {sw[0]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {sw[0]}]
    
    set_property PACKAGE_PIN N4 [get_ports {sw[1]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {sw[1]}]
    
    set_property PACKAGE_PIN M4 [get_ports {sw[2]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {sw[2]}]
    
    set_property PACKAGE_PIN R2 [get_ports {sw[3]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {sw[3]}]
    
    set_property PACKAGE_PIN P2 [get_ports {sw[4]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {sw[4]}]
    
    set_property PACKAGE_PIN P3 [get_ports {sw[5]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {sw[5]}]
    
    set_property PACKAGE_PIN P4 [get_ports {sw[6]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {sw[6]}]
    
    set_property PACKAGE_PIN P5 [get_ports {sw[7]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {sw[7]}]

# ==============================================================================
# 5位按键 (key[4:0])
# ==============================================================================
set_property PACKAGE_PIN V1 [get_ports {key[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {key[0]}]

set_property PACKAGE_PIN R17 [get_ports {key[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {key[1]}]

set_property PACKAGE_PIN R11 [get_ports {key[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {key[2]}]

set_property PACKAGE_PIN U4 [get_ports {key[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {key[3]}]

set_property PACKAGE_PIN R15 [get_ports {key[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {key[4]}]

# ==============================================================================
# LED 状态指示灯 (led[2:0])
# ==============================================================================
set_property PACKAGE_PIN J3 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]

set_property PACKAGE_PIN J2 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]

set_property PACKAGE_PIN K2 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]

# ==============================================================================
# 7段数码管 - 段选信号 (seg_data[7:0])
# ==============================================================================
# seg_data[7:0] 对应 A, B, C, D, E, F, G, DP
set_property PACKAGE_PIN B4 [get_ports {seg_data[0]}]  ; # A0 (CA0)
set_property IOSTANDARD LVCMOS33 [get_ports {seg_data[0]}]

set_property PACKAGE_PIN A4 [get_ports {seg_data[1]}]  ; # B0 (CB0)
set_property IOSTANDARD LVCMOS33 [get_ports {seg_data[1]}]

set_property PACKAGE_PIN A3 [get_ports {seg_data[2]}]  ; # C0 (CC0)
set_property IOSTANDARD LVCMOS33 [get_ports {seg_data[2]}]

set_property PACKAGE_PIN B1 [get_ports {seg_data[3]}]  ; # D0 (CD0)
set_property IOSTANDARD LVCMOS33 [get_ports {seg_data[3]}]

set_property PACKAGE_PIN A1 [get_ports {seg_data[4]}]  ; # E0 (CE0)
set_property IOSTANDARD LVCMOS33 [get_ports {seg_data[4]}]

set_property PACKAGE_PIN B3 [get_ports {seg_data[5]}]  ; # F0 (CF0)
set_property IOSTANDARD LVCMOS33 [get_ports {seg_data[5]}]

set_property PACKAGE_PIN B2 [get_ports {seg_data[6]}]  ; # G0 (CG0)
set_property IOSTANDARD LVCMOS33 [get_ports {seg_data[6]}]

set_property PACKAGE_PIN D5 [get_ports {seg_data[7]}]  ; # DP0
set_property IOSTANDARD LVCMOS33 [get_ports {seg_data[7]}]

# ==============================================================================
# 7段数码管 - 位选信号 (seg_sel[3:0])
# ==============================================================================
# seg_sel[3:0] 对应 BIT1-BIT4 (DN0_K1-K4)
set_property PACKAGE_PIN G2 [get_ports {seg_sel[0]}]   ; # BIT1 (DN0_K1)
set_property IOSTANDARD LVCMOS33 [get_ports {seg_sel[0]}]

set_property PACKAGE_PIN C2 [get_ports {seg_sel[1]}]   ; # BIT2 (DN0_K2)
set_property IOSTANDARD LVCMOS33 [get_ports {seg_sel[1]}]

set_property PACKAGE_PIN C1 [get_ports {seg_sel[2]}]   ; # BIT3 (DN0_K3)
set_property IOSTANDARD LVCMOS33 [get_ports {seg_sel[2]}]

set_property PACKAGE_PIN H1 [get_ports {seg_sel[3]}]   ; # BIT4 (DN0_K4)
set_property IOSTANDARD LVCMOS33 [get_ports {seg_sel[3]}]
