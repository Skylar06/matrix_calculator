`timescale 1ns/1ps

// 全功能仿真：覆盖 UART 命令、按键、拨码开关、矩阵运算、显示等所有功能
module tb_matrix_top_full;
    // ========== 顶层 IO ==========
    reg clk = 0;
    reg rst_n = 0;
    reg [7:0] sw;
    reg [4:0] key;
    reg uart_rx;
    wire uart_tx;
    wire [2:0] led;
    wire [3:0] seg_sel;
    wire [7:0] seg_data;

    always #5 clk = ~clk; // 100MHz

    // ========== DUT ==========
    matrix_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .sw(sw),
        .key(key),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .led(led),
        .seg_sel(seg_sel),
        .seg_data(seg_data)
    );

    // ========== UART 参数 ==========
    localparam CLK_FREQ = 100_000_000;
    localparam BAUD_RATE = 115200;
    localparam BAUD_DIV = CLK_FREQ / BAUD_RATE;

    // ========== 任务：等待 N 个时钟周期 ==========
    task wait_clk(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) @(posedge clk);
        end
    endtask

    // ========== 任务：等待 N 微秒 ==========
    task wait_us(input integer us);
        #(us * 1000);
    endtask

    // ========== 任务：UART 发送一个字节 ==========
    task uart_send_byte(input [7:0] data);
        integer i;
        begin
            // 起始位（低电平）
            uart_rx = 1'b0;
            wait_clk(BAUD_DIV);
            
            // 数据位（LSB first）
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = data[i];
                wait_clk(BAUD_DIV);
            end
            
            // 停止位（高电平）
            uart_rx = 1'b1;
            wait_clk(BAUD_DIV);
        end
    endtask

    // ========== 任务：UART 发送字符串 ==========
    task uart_send_string(input [8*256-1:0] str, input integer len);
        integer i;
        begin
            for (i = 0; i < len; i = i + 1) begin
                uart_send_byte(str[i*8 +: 8]);
            end
        end
    endtask

    // ========== 任务：模拟按键按下 ==========
    task key_press(input [3:0] key_idx);
        begin
            key[key_idx] = 1'b0;  // 低电平有效
            wait_clk(10);
            key[key_idx] = 1'b1;  // 释放
            wait_clk(10);
        end
    endtask

    // ========== 任务：设置拨码开关 ==========
    task set_switches(input [7:0] sw_val);
        begin
            sw = sw_val;
            wait_clk(10);
        end
    endtask

    // ========== 任务：配置参数 ==========
    task config_scalar(input signed [7:0] k);
        reg signed [7:0] k_val;
        begin
            k_val = k;
            // 发送 "CONFIG SCALAR "
            uart_send_byte("C");
            uart_send_byte("O");
            uart_send_byte("N");
            uart_send_byte("F");
            uart_send_byte("I");
            uart_send_byte("G");
            uart_send_byte(" ");
            uart_send_byte("S");
            uart_send_byte("C");
            uart_send_byte("A");
            uart_send_byte("L");
            uart_send_byte("A");
            uart_send_byte("R");
            uart_send_byte(" ");
            // 发送数值（简化：只支持 0-9）
            if (k_val < 0) begin
                uart_send_byte("-");
                k_val = -k_val;
            end
            uart_send_byte(8'd48 + k_val); // '0' + k
            uart_send_byte("\n");
            wait_clk(BAUD_DIV * 20); // 等待处理
        end
    endtask

    task config_range(input signed [7:0] min, max);
        begin
            // 发送 "CONFIG RANGE "
            uart_send_byte("C");
            uart_send_byte("O");
            uart_send_byte("N");
            uart_send_byte("F");
            uart_send_byte("I");
            uart_send_byte("G");
            uart_send_byte(" ");
            uart_send_byte("R");
            uart_send_byte("A");
            uart_send_byte("N");
            uart_send_byte("G");
            uart_send_byte("E");
            uart_send_byte(" ");
            // 发送 min（简化：0-9）
            uart_send_byte(8'd48 + min);
            uart_send_byte(" ");
            // 发送 max
            uart_send_byte(8'd48 + max);
            uart_send_byte("\n");
            wait_clk(BAUD_DIV * 20);
        end
    endtask

    // ========== 任务：通过 UART 输入矩阵 ==========
    task uart_input_matrix(input [2:0] m, n, input [3:0] id);
        integer i, j, idx;
        reg [7:0] elem;
        begin
            // 发送 "M N "
            uart_send_byte(8'd48 + m); // '0' + m
            uart_send_byte(" ");
            uart_send_byte(8'd48 + n);
            uart_send_byte(" ");
            
            // 发送矩阵元素（简化：按顺序发送 1, 2, 3...）
            idx = 0;
            for (i = 0; i < m; i = i + 1) begin
                for (j = 0; j < n; j = j + 1) begin
                    elem = idx + 1;
                    uart_send_byte(8'd48 + (elem / 10)); // 十位
                    uart_send_byte(8'd48 + (elem % 10)); // 个位
                    uart_send_byte(" ");
                    idx = idx + 1;
                end
            end
            uart_send_byte("\n");
            wait_clk(BAUD_DIV * (m * n + 10)); // 等待处理
        end
    endtask

    // ========== 任务：通过 UART 随机生成矩阵 ==========
    task uart_gen_matrix(input [2:0] m, n, input [3:0] count);
        begin
            // 发送 "M N COUNT\n"
            uart_send_byte(8'd48 + m);
            uart_send_byte(" ");
            uart_send_byte(8'd48 + n);
            uart_send_byte(" ");
            uart_send_byte(8'd48 + count);
            uart_send_byte("\n");
            wait_clk(BAUD_DIV * 20);
            // 等待生成完成
            wait(dut.u_rand_matrix_gen.gen_done);
            wait_clk(100);
        end
    endtask

    // ========== 任务：通过 UART 选择运算数 ==========
    task uart_select_operands(input [3:0] ida, idb);
        begin
            // 发送 "IDA IDB\n"
            uart_send_byte(8'd48 + ida);
            uart_send_byte(" ");
            uart_send_byte(8'd48 + idb);
            uart_send_byte("\n");
            wait_clk(BAUD_DIV * 10);
        end
    endtask

    // ========== 主测试流程 ==========
    initial begin
        $dumpfile("tb_matrix_top_full.vcd");
        $dumpvars(0, tb_matrix_top_full);

        // ===== 初始化 =====
        sw = 8'h00;
        key = 5'h1F;  // 所有按键释放（高电平）
        uart_rx = 1'b1;  // UART 空闲（高电平）
        
        // ===== 复位 =====
        rst_n = 0;
        wait_clk(100);
        rst_n = 1;
        wait_clk(100);
        
        $display("=== Test 1: 配置标量 K = 5 ===");
        config_scalar(8'sd5);
        wait_clk(1000);
        
        $display("=== Test 2: 配置元素范围 [0, 9] ===");
        config_range(8'sd0, 8'sd9);
        wait_clk(1000);
        
        $display("=== Test 3: 通过 UART 输入 2x2 矩阵（ID=0）===");
        // 设置模式为 INPUT (sw[1:0] = 2'b01)
        set_switches(8'h01);
        wait_clk(10);
        // 按 OK 键进入输入模式
        key_press(0); // key[0] = OK
        wait_clk(100);
        // 通过 UART 发送矩阵数据
        uart_input_matrix(3'd2, 3'd2, 4'd0);
        wait_clk(2000);
        
        $display("=== Test 4: 通过 UART 输入 3x3 矩阵（ID=1）===");
        uart_input_matrix(3'd3, 3'd3, 4'd1);
        wait_clk(2000);
        
        $display("=== Test 5: 随机生成 2x2 矩阵（ID=2）===");
        // 设置模式为 GEN (sw[1:0] = 2'b10)
        set_switches(8'h02);
        wait_clk(10);
        key_press(0); // OK
        wait_clk(100);
        uart_gen_matrix(3'd2, 3'd2, 4'd1); // 生成 1 个
        wait_clk(2000);
        
        $display("=== Test 6: 选择运算模式 - 加法 ===");
        // 设置模式为 OPERATION (sw[1:0] = 2'b11)
        // 设置运算类型为 ADD (sw[4:2] = 3'b001)
        set_switches(8'h19); // 2'b11, 3'b001
        wait_clk(10);
        key_press(0); // OK 进入运算选择
        wait_clk(100);
        key_press(0); // OK 确认运算类型
        wait_clk(500);
        
        $display("=== Test 7: 手动选择运算数（矩阵 0 和 1）===");
        // 设置手动模式 (sw[5] = 1)
        set_switches(8'h39); // sw[5]=1, sw[1:0]=11, sw[4:2]=001
        wait_clk(10);
        // 通过 UART 发送运算数选择
        uart_select_operands(4'd0, 4'd1);
        wait_clk(500);
        key_press(0); // OK 确认选择
        wait_clk(1000);
        
        $display("=== Test 8: 执行加法运算 ===");
        // 等待运算完成
        wait(dut.u_mat_ops.op_done);
        wait_clk(500);
        
        $display("=== Test 9: 显示结果 ===");
        // 设置显示模式
        set_switches(8'h18); // DISPLAY mode (sw[1:0] = 2'b10)
        wait_clk(10);
        key_press(0); // OK
        wait_clk(100);
        // 等待格式化完成
        wait(dut.u_display_formatter.format_done);
        wait_clk(1000);
        
        $display("=== Test 10: 查看矩阵列表 ===");
        // 在运算模式下查看列表
        set_switches(8'h19); // OPERATION mode
        wait_clk(10);
        key_press(0); // OK
        wait_clk(100);
        key_press(0); // OK 查看列表
        wait_clk(500);
        wait(dut.u_display_formatter.format_done);
        wait_clk(1000);
        
        $display("=== Test 11: 测试标量乘运算 ===");
        // 设置运算类型为 SCALAR (sw[4:2] = 3'b010)
        set_switches(8'h1A); // sw[1:0]=11, sw[4:2]=010
        wait_clk(10);
        key_press(0); // OK
        wait_clk(100);
        key_press(0); // OK 确认
        wait_clk(500);
        // 手动选择矩阵 0
        set_switches(8'h3A); // 手动模式
        wait_clk(10);
        uart_select_operands(4'd0, 4'd0); // 标量乘只需要一个矩阵
        wait_clk(500);
        key_press(0); // OK
        wait_clk(1000);
        wait(dut.u_mat_ops.op_done);
        wait_clk(500);
        
        $display("=== Test 12: 测试转置运算 ===");
        // 设置运算类型为 TRANSPOSE (sw[4:2] = 3'b000)
        set_switches(8'h18); // sw[1:0]=11, sw[4:2]=000
        wait_clk(10);
        key_press(0); // OK
        wait_clk(100);
        key_press(0); // OK 确认
        wait_clk(500);
        set_switches(8'h38); // 手动模式
        wait_clk(10);
        uart_select_operands(4'd1, 4'd0); // 转置矩阵 1
        wait_clk(500);
        key_press(0); // OK
        wait_clk(1000);
        wait(dut.u_mat_ops.op_done);
        wait_clk(500);
        
        $display("=== 所有测试完成 ===");
        wait_clk(5000);
        $finish;
    end

    // ========== 监控输出 ==========
    always @(posedge clk) begin
        if (uart_tx !== 1'b1 && dut.u_uart_tx.tx_busy) begin
            // UART 正在发送，可以在这里捕获发送的数据
        end
    end

    // ========== 超时保护 ==========
    initial begin
        #(100_000_000); // 100ms 超时
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule

