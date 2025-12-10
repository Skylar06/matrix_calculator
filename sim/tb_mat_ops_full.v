`timescale 1ns/1ps

// 覆盖 mat_ops 所有运算：转置/加法/标量乘/矩阵乘/卷积
module tb_mat_ops_full;
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk; // 100MHz

    // DUT 接口
    reg start_op;
    reg [2:0] op_sel;
    reg [8*25-1:0] matrix_a_flat;
    reg [8*25-1:0] matrix_b_flat;
    reg [2:0] dim_a_m, dim_a_n, dim_b_m, dim_b_n;
    reg signed [7:0] scalar_k;
    wire op_done;
    wire [7:0] result_data;
    wire [2:0] result_m, result_n;
    wire busy_flag, error_flag;

    mat_ops dut (
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

    // 结果捕获
    reg [7:0] result_mem [0:24];
    integer idx;
    reg [4:0] res_ptr;

    task clear_results;
    begin
        res_ptr = 0;
        for (idx = 0; idx < 25; idx = idx + 1) result_mem[idx] = 0;
    end
    endtask

    // 逐元素采样
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            res_ptr <= 0;
            for (idx = 0; idx < 25; idx = idx + 1) result_mem[idx] <= 0;
        end else if (busy_flag && !op_done && res_ptr < 25) begin
            result_mem[res_ptr] <= result_data;
            res_ptr <= res_ptr + 1'b1;
        end
    end

    // 常用填充任务
    task load_matrix_a(input integer m, n, input integer base);
        integer r,c;
    begin
        matrix_a_flat = {25{8'd0}};
        for (r = 0; r < m; r = r + 1)
            for (c = 0; c < n; c = c + 1)
                matrix_a_flat[(r*n+c)*8 +: 8] = base + r*n + c;
        dim_a_m = m[2:0];
        dim_a_n = n[2:0];
    end
    endtask

    task load_matrix_b(input integer m, n, input integer base);
        integer r,c;
    begin
        matrix_b_flat = {25{8'd0}};
        for (r = 0; r < m; r = r + 1)
            for (c = 0; c < n; c = c + 1)
                matrix_b_flat[(r*n+c)*8 +: 8] = base + r*n + c;
        dim_b_m = m[2:0];
        dim_b_n = n[2:0];
    end
    endtask

    task run_op(input [2:0] sel);
    begin
        op_sel   = sel;
        start_op = 1; #10; start_op = 0;
        wait(op_done);
        #10;
    end
    endtask

    // 自检：打印结果矩阵
    task show_result;
        integer total;
    begin
        total = result_m * result_n;
        $display("Result (%0d x %0d):", result_m, result_n);
        for (idx = 0; idx < total; idx = idx + 1)
            $display("  C[%0d]=%0d", idx, result_mem[idx]);
    end
    endtask

    initial begin
        $dumpfile("tb_mat_ops_full.vcd");
        $dumpvars(0, tb_mat_ops_full);

        // 复位
        start_op = 0; op_sel = 0; scalar_k = 0;
        matrix_a_flat = 0; matrix_b_flat = 0;
        dim_a_m = 0; dim_a_n = 0; dim_b_m = 0; dim_b_n = 0;
        clear_results();
        #50 rst_n = 1;
        #20;

        // 1) 转置：3x2 -> 2x3
        clear_results();
        load_matrix_a(3,2,1);          // A: 1..6
        scalar_k = 0;
        run_op(3'b000);                // transpose
        show_result();

        // 2) 加法：2x2 相同维度
        clear_results();
        load_matrix_a(2,2,1);          // A:1..4
        load_matrix_b(2,2,10);         // B:10..13
        run_op(3'b001);                // add
        show_result();

        // 3) 标量乘：3x3 * (-2)
        clear_results();
        load_matrix_a(3,3,1);
        scalar_k = -8'sd2;
        run_op(3'b010);                // scalar
        show_result();

        // 4) 矩阵乘法：A 2x3, B 3x2 => C 2x2
        clear_results();
        load_matrix_a(2,3,1);          // A:1..6
        load_matrix_b(3,2,1);          // B:1..6
        run_op(3'b011);                // multiply
        show_result();

        // 5) 卷积：A 3x3, B 2x2 (valid conv => 2x2)
        clear_results();
        load_matrix_a(3,3,1);          // 1..9
        load_matrix_b(2,2,1);          // 1..4
        run_op(3'b100);                // conv
        show_result();

        $display("All ops done.");
        #50;
        $finish;
    end
endmodule

