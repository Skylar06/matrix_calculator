`timescale 1ns/1ps

// 全链路冒烟：直接驱动顶层 matrix_top 的高层控制信号，覆盖存储→选择→运算→显示
// 说明：为简化，不经 UART，直接拉高 start_x 等控制，验证数据通路/握手与无 X。
module tb_matrix_top_sanity;
    // 顶层 IO
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

    // DUT
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

    // 简化：直接访问内部信号（非综合路径，仅仿真）
    // 通过 hierarchical reference 方式驱动 parser/storage 信号。
    // 注意：Vivado 仿真允许层次引用，综合时无影响。
    // 层次名按 matrix_top 中例化名：
    // u_uart_cmd_parser, u_matrix_storage, u_mat_ops, u_ctrl_fsm, u_display_formatter

    // 便捷 task：等待若干周期
    task wait_ns(input integer ns);
    begin
        #(ns);
    end
    endtask

    // 写入一个 2x2 矩阵到存储（通过层次引用直接驱动内部信号）
    task write_matrix(input [3:0] id, input [7:0] d0, d1, d2, d3);
    begin
        // 设定尺寸（通过层次引用）
        force dut.u_uart_cmd_parser.dim_m = 3'd2;
        force dut.u_uart_cmd_parser.dim_n = 3'd2;
        force dut.u_uart_cmd_parser.matrix_id = id;
        // 启动 start_input（通过层次引用）
        force dut.u_ctrl_fsm.start_input = 1'b1; 
        wait_ns(10); 
        force dut.u_ctrl_fsm.start_input = 1'b0;
        // 逐个写入（通过层次引用）
        force dut.u_uart_cmd_parser.data_ready = 1'b1;
        force dut.u_matrix_storage.write_en = 1'b1;
        force dut.u_uart_cmd_parser.elem_data = d0; wait_ns(10);
        force dut.u_uart_cmd_parser.elem_data = d1; wait_ns(10);
        force dut.u_uart_cmd_parser.elem_data = d2; wait_ns(10);
        force dut.u_uart_cmd_parser.elem_data = d3; wait_ns(10);
        force dut.u_matrix_storage.write_en = 1'b0;
        force dut.u_uart_cmd_parser.data_ready = 1'b0;
        // 释放 force
        release dut.u_uart_cmd_parser.dim_m;
        release dut.u_uart_cmd_parser.dim_n;
        release dut.u_uart_cmd_parser.matrix_id;
        release dut.u_ctrl_fsm.start_input;
        release dut.u_uart_cmd_parser.data_ready;
        release dut.u_matrix_storage.write_en;
        release dut.u_uart_cmd_parser.elem_data;
    end
    endtask

    // 触发运算
    task run_add(input [3:0] ida, input [3:0] idb);
    begin
        // 选择 A/B（通过层次引用）
        force dut.u_ctrl_fsm.mode_sel = 2'b11;
        force dut.u_ctrl_fsm.op_sel   = 3'b001; // add
        force dut.u_ctrl_fsm.operand_a_id = ida;
        force dut.u_ctrl_fsm.operand_b_id = idb;
        // 触发选择与运算
        force dut.u_ctrl_fsm.start_select = 1'b1; wait_ns(10); 
        force dut.u_ctrl_fsm.start_select = 1'b0;
        wait_ns(100); // 等待选择完成
        force dut.u_ctrl_fsm.start_op = 1'b1; wait_ns(10); 
        force dut.u_ctrl_fsm.start_op = 1'b0;
        // 等待完成
        wait(dut.u_mat_ops.op_done);
        wait_ns(50);
        // 释放 force
        release dut.u_ctrl_fsm.mode_sel;
        release dut.u_ctrl_fsm.op_sel;
        release dut.u_ctrl_fsm.operand_a_id;
        release dut.u_ctrl_fsm.operand_b_id;
        release dut.u_ctrl_fsm.start_select;
        release dut.u_ctrl_fsm.start_op;
    end
    endtask

    // 触发显示结果
    task show_result;
    begin
        force dut.u_ctrl_fsm.start_disp = 1'b1; 
        force dut.u_ctrl_fsm.start_format = 1'b1; 
        wait_ns(10);
        force dut.u_ctrl_fsm.start_disp = 1'b0; 
        force dut.u_ctrl_fsm.start_format = 1'b0;
        // 依赖 display_formatter 的 data_req 握手
        repeat (20) begin
            if (dut.u_display_formatter.data_req) begin
                force dut.u_matrix_storage.read_en = 1'b1;
            end else begin
                force dut.u_matrix_storage.read_en = 1'b0;
            end
            wait_ns(10);
        end
        force dut.u_matrix_storage.read_en = 1'b0;
        // 释放 force
        release dut.u_ctrl_fsm.start_disp;
        release dut.u_ctrl_fsm.start_format;
        release dut.u_matrix_storage.read_en;
    end
    endtask

    initial begin
        $dumpfile("tb_matrix_top_sanity.vcd");
        $dumpvars(0, tb_matrix_top_sanity);

        // 初值
        sw = 0; key = 5'h1F; uart_rx = 1'b1;
        rst_n = 0; wait_ns(50); rst_n = 1; wait_ns(50);

        // 写两矩阵：ID0: [1 2;3 4], ID1: [10 20;30 40]
        write_matrix(4'd0, 8'd1, 8'd2, 8'd3, 8'd4);
        write_matrix(4'd1, 8'd10, 8'd20, 8'd30, 8'd40);

        // 运行加法
        run_add(4'd0, 4'd1);

        // 拉取结果显示
        show_result;

        $display("Sanity done.");
        wait_ns(100);
        $finish;
    end
endmodule

