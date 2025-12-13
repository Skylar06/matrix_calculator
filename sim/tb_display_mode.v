`timescale 1ns/1ps

/******************************************************************************
 * DISPLAY模式测试平台
 * 测试DISPLAY模式下matrix_id的传递和显示
 ******************************************************************************/
module tb_display_mode;

    parameter CLK_FREQ = 50_000_000;
    parameter CLK_PERIOD = 20;  // 50MHz = 20ns period
    
    // 时钟和复位
    reg clk;
    reg rst_n;
    
    // 控制信号
    reg [1:0] mode_sel;
    reg start_disp;
    reg start_format;
    reg [1:0] display_mode;
    
    // matrix_storage接口
    wire [3:0] matrix_id_in;
    wire [3:0] matrix_id_out;
    wire [2:0] matrix_a_m, matrix_a_n;
    wire meta_info_valid;
    wire matrix_data_valid;
    wire error_flag;
    
    // display_formatter接口
    wire [7:0] tx_data;
    wire tx_valid;
    wire tx_busy;
    wire format_done;
    
    // 模拟matrix_storage
    reg [3:0] test_matrix_id;
    reg [2:0] test_dim_m, test_dim_n;
    reg test_valid;
    
    // 模拟display_formatter
    reg [3:0] fmt_matrix_id;
    reg [2:0] fmt_dim_m, fmt_dim_n;
    
    // 时钟生成
    always #(CLK_PERIOD/2) clk = ~clk;
    
    // 测试流程
    initial begin
        $display("========================================");
        $display("DISPLAY模式测试开始");
        $display("========================================\n");
        
        // 初始化
        clk = 0;
        rst_n = 0;
        mode_sel = 2'b00;
        start_disp = 0;
        start_format = 0;
        display_mode = 2'd0;
        test_matrix_id = 4'd0;
        test_dim_m = 3'd0;
        test_dim_n = 3'd0;
        test_valid = 1'b0;
        
        // 复位
        #100;
        rst_n = 1;
        #100;
        
        $display("--- 测试1: DISPLAY模式，matrix_id_in=0（无效）---");
        mode_sel = 2'b11;  // DISPLAY模式
        test_matrix_id = 4'd0;
        test_dim_m = 3'd0;
        test_dim_n = 3'd0;
        test_valid = 1'b0;  // 矩阵不存在
        
        start_disp = 1'b1;
        #(CLK_PERIOD);
        start_disp = 1'b0;
        #(CLK_PERIOD * 5);
        
        $display("matrix_id_in=%0d, error_flag=%b", test_matrix_id, error_flag);
        
        $display("\n--- 测试2: DISPLAY模式，matrix_id_in=1（有效）---");
        test_matrix_id = 4'd1;
        test_dim_m = 3'd3;
        test_dim_n = 3'd3;
        test_valid = 1'b1;  // 矩阵存在
        
        start_disp = 1'b1;
        #(CLK_PERIOD);
        start_disp = 1'b0;
        #(CLK_PERIOD * 5);
        
        $display("matrix_id_in=%0d, dim_m=%0d, dim_n=%0d, error_flag=%b", 
                 test_matrix_id, test_dim_m, test_dim_n, error_flag);
        
        $display("\n--- 测试3: display_formatter接收的参数 ---");
        start_format = 1'b1;
        #(CLK_PERIOD);
        start_format = 1'b0;
        #(CLK_PERIOD * 5);
        
        $display("fmt_matrix_id=%0d, fmt_dim_m=%0d, fmt_dim_n=%0d", 
                 fmt_matrix_id, fmt_dim_m, fmt_dim_n);
        
        $display("\n========================================");
        $display("测试完成");
        $display("========================================");
        
        #1000;
        $finish;
    end
    
    // 模拟matrix_id_in_sel逻辑
    assign matrix_id_in = (mode_sel == 2'b11) ? test_matrix_id : 4'd0;
    
    // 模拟matrix_storage的响应
    always @(posedge clk) begin
        if (!rst_n) begin
            matrix_id_out <= 4'd0;
            matrix_a_m <= 3'd0;
            matrix_a_n <= 3'd0;
            meta_info_valid <= 1'b0;
            matrix_data_valid <= 1'b0;
        end else begin
            if (start_disp) begin
                if (test_valid && test_matrix_id < 10) begin
                    matrix_id_out <= test_matrix_id;
                    matrix_a_m <= test_dim_m;
                    matrix_a_n <= test_dim_n;
                    meta_info_valid <= 1'b1;
                end else begin
                    matrix_id_out <= 4'd0;
                    matrix_a_m <= 3'd0;
                    matrix_a_n <= 3'd0;
                    meta_info_valid <= 1'b0;
                end
            end
        end
    end
    
    // 模拟display_formatter接收参数
    always @(posedge clk) begin
        if (!rst_n) begin
            fmt_matrix_id <= 4'd0;
            fmt_dim_m <= 3'd0;
            fmt_dim_n <= 3'd0;
        end else begin
            if (start_format) begin
                fmt_matrix_id <= matrix_id_out;
                fmt_dim_m <= matrix_a_m;
                fmt_dim_n <= matrix_a_n;
            end
        end
    end
    
    assign error_flag = (start_disp && (!test_valid || test_matrix_id >= 10)) ? 1'b1 : 1'b0;

endmodule

