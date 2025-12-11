`timescale 1ns/1ps

module tb_mat_ops;
    // 时钟与复位
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;  // 100MHz

    // 驱动到 DUT 的输入
    reg start_op;
    reg [2:0] op_sel;
    // 被测 DUT 端口
    reg [8*25-1:0] matrix_a_flat;
    reg [8*25-1:0] matrix_b_flat;
    reg [2:0] dim_a_m, dim_a_n, dim_b_m, dim_b_n;
    reg signed [7:0] scalar_k;
    wire op_done;
    wire [7:0] result_data;
    wire [2:0] result_m, result_n;
    wire busy_flag, error_flag;

    // 实例化 mat_ops
    mat_ops uut (
        .clk(clk),
        .rst_n(rst_n),
        .start_op(start_op),
        .op_sel(op_sel),
        .matrix_a_flat(matrix_a_flat),
        .matrix_b_flat(matrix_b_flat),
        .dim_a_m(dim_a_m),
        .dim_a_n(dim_a_n),
        .dim_b_m(dim_b_m),
        .dim_b_n(dim_b_n),
        .scalar_k(scalar_k),
        .op_done(op_done),
        .result_data(result_data),
        .result_m(result_m),
        .result_n(result_n),
        .busy_flag(busy_flag),
        .error_flag(error_flag)
    );

    // 结果缓存
    integer idx;
    reg [7:0] result_mem [0:24];
    reg [4:0] res_ptr;

    // 采样/打印
    always @(posedge clk) begin
        if (busy_flag)
            $display("[%0t] busy, result_m=%0d result_n=%0d", $time, result_m, result_n);
        if (op_done)
            $display("[%0t] op_done, total elements=%0d", $time, result_m * result_n);
    end

    // 数据采样：仅在 busy 阶段有效
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            res_ptr <= 0;
            for (idx = 0; idx < 25; idx = idx + 1)
                result_mem[idx] <= 8'd0;
        end else begin
            if (busy_flag && !op_done && res_ptr < 25) begin
                result_mem[res_ptr] <= result_data;
                res_ptr <= res_ptr + 1'b1;
            end
        end
    end

    initial begin
        $dumpfile("tb_mat_ops.vcd");
        $dumpvars(0, tb_mat_ops);

        // 复位
        // 默认配置
        start_op = 0;
        op_sel   = 3'b010;  // 标量乘
        scalar_k = 8'sd2;   // 乘以 2
        dim_a_m  = 3'd3;
        dim_a_n  = 3'd3;
        dim_b_m  = 3'd3;    // 仅乘法用，保持一致
        dim_b_n  = 3'd3;
        res_ptr  = 0;
        for (idx = 0; idx < 25; idx = idx + 1)
            result_mem[idx] = 8'd0;

        // 填充 A (3x3): 1..9
        matrix_a_flat = {25{8'd0}};
        matrix_b_flat = {25{8'd0}};
        // pack 3x3 A: 1..9
        matrix_a_flat[0*8 +: 8] = 8'd1;
        matrix_a_flat[1*8 +: 8] = 8'd2;
        matrix_a_flat[2*8 +: 8] = 8'd3;
        matrix_a_flat[3*8 +: 8] = 8'd4;
        matrix_a_flat[4*8 +: 8] = 8'd5;
        matrix_a_flat[5*8 +: 8] = 8'd6;
        matrix_a_flat[6*8 +: 8] = 8'd7;
        matrix_a_flat[7*8 +: 8] = 8'd8;
        matrix_a_flat[8*8 +: 8] = 8'd9;

        // 释放复位
        #50 rst_n = 1;
        #20;

        // 启动运算
        start_op = 1; #10; start_op = 0;

        // 等待完成
        wait(op_done);
        #20;

        // 打印结果
        $display("=== Scalar *2 Result ===");
        for (idx = 0; idx < (result_m * result_n); idx = idx + 1) begin
            $display("C[%0d] = %0d", idx, result_mem[idx]);
        end

        $finish;
    end
endmodule

