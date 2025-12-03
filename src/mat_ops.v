module mat_ops (
    input clk,
    input rst_n,
    input start_op,
    input [2:0] op_sel,
    input [7:0] matrix_a,
    input [7:0] matrix_b,
    input [7:0] scalar_k,

    output op_done,
    output [7:0] result_data,
    output busy_flag,
    output error_flag
);

    // TODO: 实现不同运算

endmodule