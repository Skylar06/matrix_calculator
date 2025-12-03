module uart_cmd_parser (
    input clk,
    input rst_n,
    input [7:0] rx_data,
    input rx_valid,

    output [3:0] cmd_type, 
    output [2:0] dim_m,
    output [2:0] dim_n,
    output [7:0] elem_data,
    output [7:0] elem_min, 
    output [7:0] elem_max, 
    output [3:0] matrix_id_in,
    output cfg_valid,
    output write_en,
    output read_en
);

    // TODO: 文本协议解析的 FSM

endmodule