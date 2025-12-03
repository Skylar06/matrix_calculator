module matrix_storage (
    input clk,
    input rst_n,
    input write_en,
    input read_en,
    input [2:0] dim_m,
    input [2:0] dim_n,
    input [7:0] data_in,
    input [3:0] matrix_id_in,
    input [7:0] result_data,
    input op_done,
    input start_input,
    input start_disp,

    output [7:0] data_out,
    output [3:0] matrix_id_out,
    output meta_info_valid,
    output error_flag,
    output [7:0] matrix_a,
    output [7:0] matrix_b
);

    // TODO: RAM + 元信息管理

endmodule