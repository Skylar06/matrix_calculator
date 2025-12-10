`timescale 1ns/1ps

module tb_mat_ops;
    // 时钟与复位
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;  // 100MHz

    // 被测模块接口
    reg start_op;
    reg [2:0] op_sel;
    reg [7:0] matrix_a [0:24];
    reg [7:0] matrix_b [0:24];
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
        .matrix_a(matrix_a),
        .matrix_b(matrix_b),
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

    // 结果捕获
    integer idx;
    reg [7:0] result_mem [0:24];
    reg [4:0] res_ptr;

    // 监视输出
    always @(posedge clk) begin
        if (busy_flag)
            $display("[%0t] busy, result_m=%0d result_n=%0d", $time, result_m, result_n);
        if (op_done)
            $display("[%0t] op_done, total elements=%0d", $time, result_m * result_n);
    end

    always @(posedge clk) begin
        if (busy_flag && !op_done) begin
            // 收集逐元素输出
            result_mem[res_ptr] <= result_data;
            res_ptr <= res_ptr + 1'b1;
        end
    end

    initial begin
        $dumpfile("tb_mat_ops.vcd");
        $dumpvars(0, tb_mat_ops);

        // 默认值
        start_op = 0;
        op_sel   = 3'b010;  // 标量乘
        scalar_k = 8'sd2;   // 乘以2
        dim_a_m  = 3'd3;
        dim_a_n  = 3'd3;
        dim_b_m  = 3'd3;    // 仅为接口匹配，无实际使用
        dim_b_n  = 3'd3;
        res_ptr  = 0;

        // 预置矩阵A (3x3): 1..9
        for (idx = 0; idx < 25; idx = idx + 1) begin
            matrix_a[idx] = 0;
            matrix_b[idx] = 0;
        end
        matrix_a[0]=1; matrix_a[1]=2; matrix_a[2]=3;
        matrix_a[3]=4; matrix_a[4]=5; matrix_a[5]=6;
        matrix_a[6]=7; matrix_a[7]=8; matrix_a[8]=9;

        // 释放复位
        #50 rst_n = 1;
        #20;

        // 触发运算脉冲
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

