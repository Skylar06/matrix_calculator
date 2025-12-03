module rand_matrix_gen (
    input clk,
    input rst_n,
    input start_gen,
    input [2:0] dim_m,
    input [2:0] dim_n,
    input [7:0] elem_min,
    input [7:0] elem_max,

    output gen_done,
    output [7:0] data_out
);

    // TODO: 随机数生成逻辑

endmodule