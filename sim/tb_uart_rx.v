`timescale 1ns/1ps

/******************************************************************************
 * UART RX 模块测试平台
 * 用于测试串口接收功能
 ******************************************************************************/
module tb_uart_rx;

    // ==========================================================================
    // 参数定义
    // ==========================================================================
    parameter CLK_FREQ = 50_000_000;  // 50MHz
    parameter BAUD_RATE = 115200;
    parameter BAUD_DIV = CLK_FREQ / BAUD_RATE;  // 434
    parameter BIT_TIME = (1_000_000_000 / BAUD_RATE);  // 纳秒单位的位时间
    
    // ==========================================================================
    // 信号定义
    // ==========================================================================
    reg clk;
    reg rst_n;
    reg rx;
    wire [7:0] rx_data;
    wire rx_valid;
    
    // 测试控制
    integer test_count = 0;
    integer pass_count = 0;
    integer fail_count = 0;
    
    // ==========================================================================
    // 时钟生成 (50MHz, 周期20ns)
    // ==========================================================================
    always #10 clk = ~clk;
    
    // ==========================================================================
    // DUT实例化
    // ==========================================================================
    uart_rx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .rx(rx),
        .rx_data(rx_data),
        .rx_valid(rx_valid)
    );
    
    // ==========================================================================
    // UART发送任务：发送一个字节
    // ==========================================================================
    task uart_send_byte(input [7:0] data);
    integer i;
    begin
        // 起始位 (低电平)
        rx = 1'b0;
        #(BIT_TIME);
        
        // 数据位 (LSB first)
        for (i = 0; i < 8; i = i + 1) begin
            rx = data[i];
            #(BIT_TIME);
        end
        
        // 停止位 (高电平)
        rx = 1'b1;
        #(BIT_TIME);
        
        $display("[%0t] UART发送: 0x%02h ('%c')", $time, data, (data >= 32 && data <= 126) ? data : 32);
    end
    endtask
    
    // ==========================================================================
    // 测试任务：发送并验证
    // ==========================================================================
    task test_byte(input [7:0] expected);
    reg [7:0] captured_data;
    reg data_captured;
    begin
        test_count = test_count + 1;
        data_captured = 1'b0;
        captured_data = 8'h00;
        
        // 启动发送
        uart_send_byte(expected);
        
        // 等待rx_valid上升沿，捕获数据
        // 使用wait语句等待rx_valid变高，最多等待2个字节时间
        fork
            begin
                wait(rx_valid == 1'b1);
                @(posedge clk);  // 在时钟上升沿捕获
                captured_data = rx_data;
                data_captured = 1'b1;
            end
            begin
                #(BIT_TIME * 20);  // 超时保护
                if (!data_captured) begin
                    $display("[%0t] ⚠ 警告: 等待rx_valid超时", $time);
                end
            end
        join_any
        disable fork;
        
        // 等待rx_valid拉低
        wait(rx_valid == 1'b0);
        #(BIT_TIME / 2);  // 等待一小段时间确保稳定
        
        // 验证接收到的数据
        if (data_captured && captured_data == expected) begin
            $display("[%0t] ✓ 测试通过: 接收到 0x%02h ('%c')", $time, captured_data, 
                     (captured_data >= 32 && captured_data <= 126) ? captured_data : 32);
            pass_count = pass_count + 1;
        end else begin
            $display("[%0t] ✗ 测试失败: 期望 0x%02h, 实际 0x%02h, data_captured=%b, rx_busy=%b, bit_idx=%0d", 
                     $time, expected, captured_data, data_captured, dut.rx_busy, dut.bit_idx);
            fail_count = fail_count + 1;
        end
    end
    endtask
    
    // ==========================================================================
    // 主测试流程
    // ==========================================================================
    initial begin
        $display("========================================");
        $display("UART RX 测试开始");
        $display("时钟频率: %0d MHz", CLK_FREQ / 1_000_000);
        $display("波特率: %0d", BAUD_RATE);
        $display("波特分频: %0d", BAUD_DIV);
        $display("位时间: %0d ns", BIT_TIME);
        $display("预计总时间: %0d ns (约 %0d ms)", BIT_TIME * 12 * 9, (BIT_TIME * 12 * 9) / 1_000_000);
        $display("========================================\n");
        
        // 初始化
        clk = 0;
        rst_n = 0;
        rx = 1'b1;  // 空闲状态为高电平
        
        // 复位
        #100;
        rst_n = 1;
        #100;
        
        $display("\n--- 测试1: 发送数字字符 '3' (0x33) ---");
        test_byte(8'h33);  // '3'
        
        $display("\n--- 测试2: 发送空格 ' ' (0x20) ---");
        test_byte(8'h20);  // ' '
        
        $display("\n--- 测试3: 发送数字字符 '1' (0x31) ---");
        test_byte(8'h31);  // '1'
        
        $display("\n--- 测试4: 发送数字字符 '2' (0x32) ---");
        test_byte(8'h32);  // '2'
        
        $display("\n--- 测试5: 连续发送 "3 3 1 2 3 4 5 6 7 8 9" ---");
        test_byte(8'h33);  // '3'
        #(BIT_TIME * 2);
        test_byte(8'h20);  // ' '
        #(BIT_TIME * 2);
        test_byte(8'h33);  // '3'
        #(BIT_TIME * 2);
        test_byte(8'h20);  // ' '
        #(BIT_TIME * 2);
        test_byte(8'h31);  // '1'
        #(BIT_TIME * 2);
        test_byte(8'h20);  // ' '
        #(BIT_TIME * 2);
        test_byte(8'h32);  // '2'
        #(BIT_TIME * 2);
        test_byte(8'h20);  // ' '
        #(BIT_TIME * 2);
        test_byte(8'h33);  // '3'
        
        // 等待所有数据完成
        #(BIT_TIME * 20);
        
        // 测试总结
        $display("\n========================================");
        $display("测试总结:");
        $display("  总测试数: %0d", test_count);
        $display("  通过: %0d", pass_count);
        $display("  失败: %0d", fail_count);
        $display("========================================");
        
        if (fail_count == 0) begin
            $display("✓ 所有测试通过！");
        end else begin
            $display("✗ 有测试失败，请检查uart_rx模块逻辑");
        end
        
        $finish;
    end
    
    // ==========================================================================
    // 监控信号变化
    // ==========================================================================
    initial begin
        $monitor("[%0t] rx=%b rx_busy=%b bit_idx=%0d rx_data=0x%02h rx_valid=%b", 
                 $time, rx, dut.rx_busy, dut.bit_idx, rx_data, rx_valid);
    end

endmodule

