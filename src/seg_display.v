module seg_display (
    input clk,
    input rst_n,
    input [1:0] mode_sel,
    input [2:0] op_sel,
    input [7:0] countdown_val,
    input [3:0] matrix_id_out,

    output [3:0] seg_sel,
    output [7:0] seg_data
);

    // TODO: 字符编码

endmodule