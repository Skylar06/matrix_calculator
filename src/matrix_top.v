module matrix_top (
    input clk,
    input rst_n,
    input [7:0] sw,
    input [3:0] key,
    input uart_rx,

    output uart_tx,
    output [2:0] led,
    output [3:0] seg_sel,
    output [7:0] seg_data
);

    // ctrl_fsm <-> else
    wire [1:0] mode_sel;
    wire [2:0] op_sel;
    wire [7:0] countdown_val;
    wire start_input, start_gen, start_disp, start_op, tx_start, error_flag_ctr, busy_flag_ctr, done_flag_ctrl;

    // UART RX / parser
    wire [7:0] rx_data;
    wire [3:0] cmd_type;
    wire [2:0] dim_m;
    wire [2:0] dim_n;
    wire [7:0] elem_data;
    wire [7:0] elem_min;
    wire [7:0] elem_max;
    wire [3:0] matrix_id_in;
    wire rx_valid, cfg_val, write_, read_en;

    // storage / rand / ops
    wire [7:0] ms_data_in;
    wire [7:0] ms_data_out;
    wire [3:0] matrix_id_out;
    wire [7:0] rand_data_out;
    wire [7:0] matrix_a;
    wire [7:0] matrix_b;
    wire [7:0] result_data;
    wire meta_info_valid, error_flag_storag, gen_done, op_do, busy_flag_op, error_flag_ops;

    // LED
    assign error_flag_ctrl = error_flag_ops | error_flag_storage;
    assign busy_flag_ctrl  = busy_flag_ops;
    assign done_flag_ctrl  = op_done;

    // TODO: k / storage
    wire [7:0] scalar_k = sw;
    assign ms_data_in = (start_gen) ? rand_data_out : elem_data;

    ctrl_fsm u_ctrl_fsm (
        .clk(clk),
        .rst_n(rst_n),
        .sw(sw[3:0]),
        .key(key[3:0]),
        .error_flag(error_flag_ctrl),
        .busy_flag(busy_flag_ctrl),
        .done_flag(done_flag_ctrl),

        .mode_sel(mode_sel),
        .op_sel(op_sel),
        .countdown_val(countdown_val),
        .start_input(start_input),
        .start_gen(start_gen),
        .start_disp(start_disp),
        .start_op(start_op),
        .tx_start(tx_start)
    );

    uart_rx u_uart_rx (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx(uart_rx),

        .rx_data(rx_data),
        .rx_valid(rx_valid)
    );

    uart_cmd_parser u_uart_cmd_parser (
        .clk(clk),
        .rst_n(rst_n),
        .rx_data(rx_data),
        .rx_valid(rx_valid),

        .cmd_type(cmd_type),
        .dim_m(dim_m),
        .dim_n(dim_n),
        .elem_data(elem_data),
        .elem_min(elem_min),
        .elem_max(elem_max),
        .matrix_id_in(matrix_id_in),
        .cfg_valid(cfg_valid),
        .write_en(write_en),
        .read_en(read_en)
    );

    rand_matrix_gen u_rand_matrix_gen (
        .clk(clk),
        .rst_n(rst_n),
        .start_gen(start_gen),
        .dim_m(dim_m),
        .dim_n(dim_n),
        .elem_min(elem_min),
        .elem_max(elem_max),

        .gen_done(gen_done),
        .data_out(rand_data_out)
    );

    matrix_storage u_matrix_storage (
        .clk(clk),
        .rst_n(rst_n),
        .write_en(write_en),
        .read_en(read_en),
        .dim_m(dim_m),
        .dim_n(dim_n),
        .data_in(ms_data_in),
        .matrix_id_in(matrix_id_in),

        .result_data(result_data),
        .op_done(op_done),
        .start_input(start_input),
        .start_disp(start_disp),
        .data_out(ms_data_out),
        .matrix_id_out(matrix_id_out),
        .meta_info_valid(meta_info_valid),
        .error_flag(error_flag_storage),
        .matrix_a(matrix_a),
        .matrix_b(matrix_b)
    );

    mat_ops u_mat_ops (
        .clk(clk),
        .rst_n(rst_n),
        .start_op(start_op),
        .op_sel(op_sel),
        .matrix_a(matrix_a),
        .matrix_b(matrix_b),
        .scalar_k(scalar_k),

        .op_done    (op_done),
        .result_data(result_data),
        .busy_flag  (busy_flag_ops),
        .error_flag (error_flag_ops)
    );

    seg_display u_seg_display (
        .clk(clk),
        .rst_n(rst_n),
        .mode_sel(mode_sel),
        .op_sel(op_sel),
        .countdown_val(countdown_val),
        .matrix_id_out(matrix_id_out),

        .seg_sel(seg_sel),
        .seg_data(seg_data)
    );

    led_status u_led_status (
        .clk(clk),
        .rst_n(rst_n),
        .error_flag(error_flag_ctrl),
        .busy_flag(busy_flag_ctrl),
        .done_flag(done_flag_ctrl),

        .led(led)
    );

    wire [7:0] tx_data;
    assign tx_data = (op_done) ? result_data : ms_data_out;

    uart_tx u_uart_tx (
        .clk(clk),
        .rst_n(rst_n),
        .tx_start(tx_start),
        .tx_data(tx_data),

        .uart_tx(uart_tx)
    );


endmodule