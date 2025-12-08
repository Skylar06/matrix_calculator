module matrix_top (
    input clk,
    input rst_n,
    input [7:0] sw,
    input [4:0] key,
    input uart_rx,

    output uart_tx,
    output [2:0] led,
    output [3:0] seg_sel,
    output [7:0] seg_data
);

    // ========== ctrl_fsm <-> 其他模块 ==========
    wire [1:0] mode_sel;
    wire [2:0] op_sel;
    wire [7:0] countdown_val;
    wire start_input, start_gen, start_disp, start_op, tx_start;
    wire error_flag_ctrl, busy_flag_ctrl, done_flag_ctrl;

    // ========== UART RX / parser ==========
    wire [7:0] rx_data;
    wire [3:0] cmd_type;
    wire [2:0] dim_m;
    wire [2:0] dim_n;
    wire [7:0] elem_data;
    wire [7:0] elem_min;
    wire [7:0] elem_max;
    wire [3:0] matrix_id_in;
    wire rx_valid, cfg_valid, write_en, read_en;  // 修复: cfg_val -> cfg_valid, write_ -> write_en

    // ========== storage / rand / ops ==========
    wire [7:0] ms_data_in;
    wire [7:0] ms_data_out;
    wire [3:0] matrix_id_out;
    wire [7:0] rand_data_out;
    wire [7:0] matrix_a;
    wire [7:0] matrix_b;
    wire [7:0] result_data;
    wire meta_info_valid, error_flag_storage, gen_done, op_done, busy_flag_ops, error_flag_ops;

    // ========== LED错误标志汇总 ==========
    assign error_flag_ctrl = error_flag_ops | error_flag_storage;
    assign busy_flag_ctrl  = busy_flag_ops;
    assign done_flag_ctrl  = op_done;

    // ========== 标量K和数据输入选择 ==========
    wire [7:0] scalar_k = sw;  // 从拨码开关读取标量
    assign ms_data_in = (start_gen) ? rand_data_out : elem_data;

    // ========== 实例化所有子模块 ==========

    // 1. 控制FSM
    ctrl_fsm u_ctrl_fsm (
        .clk(clk),
        .rst_n(rst_n),
        .sw(sw[4:0]),
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

    // 2. UART接收
    uart_rx u_uart_rx (
        .clk(clk),
        .rst_n(rst_n),
        .rx(uart_rx),

        .rx_data(rx_data),
        .rx_valid(rx_valid)
    );

    // 3. UART命令解析器
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

    // 4. 随机矩阵生成器
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

    // 5. 矩阵存储
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

    // 6. 矩阵运算模块
    mat_ops u_mat_ops (
        .clk(clk),
        .rst_n(rst_n),
        .start_op(start_op),
        .op_sel(op_sel),
        .matrix_a(matrix_a),
        .matrix_b(matrix_b),
        .scalar_k(scalar_k),

        .op_done(op_done),
        .result_data(result_data),
        .busy_flag(busy_flag_ops),
        .error_flag(error_flag_ops)
    );

    // 7. 七段数码管显示
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

    // 8. LED状态指示
    led_status u_led_status (
        .clk(clk),
        .rst_n(rst_n),
        .error_flag(error_flag_ctrl),
        .busy_flag(busy_flag_ctrl),
        .done_flag(done_flag_ctrl),

        .led(led)
    );

    // 9. UART发送
    // 根据情况选择发送运算结果或存储的矩阵数据
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