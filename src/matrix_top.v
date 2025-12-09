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

    // ========== ctrl_fsm信号 ==========
    wire [1:0] mode_sel;
    wire [2:0] op_sel;
    wire [7:0] countdown_val;
    wire start_input, start_gen, start_disp, start_op, tx_start;
    wire start_select, start_format;
    wire manual_mode;
    wire [3:0] operand_a_id, operand_b_id;
    wire [1:0] display_mode;
    
    // ========== 错误/忙碌/完成标志 ==========
    wire error_flag_ctrl, busy_flag_ctrl, done_flag_ctrl;
    wire select_done, select_error, format_done;

    // ========== UART RX / parser ==========
    wire [7:0] rx_data;
    wire [2:0] dim_m, dim_n;
    wire [7:0] elem_data, elem_min, elem_max;
    wire [3:0] count, matrix_id_in;
    wire [3:0] user_id_a, user_id_b;
    wire rx_valid, data_ready, write_en, read_en, user_input_valid;

    // ========== storage信号 ==========
    wire [7:0] ms_data_in, ms_data_out;
    wire [3:0] matrix_id_out;
    wire [7:0] matrix_a [0:24];
    wire [7:0] matrix_b [0:24];
    wire [2:0] matrix_a_m, matrix_a_n, matrix_b_m, matrix_b_n;
    wire [2:0] list_m [0:9];
    wire [2:0] list_n [0:9];
    wire list_valid [0:9];
    wire [7:0] result_data;
    wire meta_info_valid, error_flag_storage, gen_done, op_done, busy_flag_ops, error_flag_ops;
    wire load_operands, req_list_info;

    // ========== operand_selector信号 ==========
    wire [3:0] selected_a, selected_b;
    
    // ========== display_formatter信号 ==========
    wire [7:0] tx_data_fmt;
    wire tx_valid_fmt;
    wire [7:0] matrix_data_to_fmt;
    wire matrix_data_valid_fmt;
    
    // ========== 随机生成器信号 ==========
    wire [7:0] rand_data_out;
    wire rand_write_en;
    
    // ========== 标量K ==========
    wire [7:0] scalar_k = sw;
    
    // ========== 数据输入选择 ==========
    assign ms_data_in = (start_gen) ? rand_data_out : elem_data;
    assign write_en = (start_gen) ? rand_write_en : (start_input && data_ready);
    
    // ========== 错误标志汇总 ==========
    assign error_flag_ctrl = error_flag_ops | error_flag_storage | select_error;
    assign busy_flag_ctrl  = busy_flag_ops;
    assign done_flag_ctrl  = op_done | gen_done;
    
    // ========== 运算数加载信号 ==========
    assign load_operands = (state_op_run && prev_state != state_op_run);  // 简化处理
    
    // ========== 列表查询信号 ==========
    assign req_list_info = (display_mode == 2'd1);
    
    // ========== 实例化模块 ==========

    ctrl_fsm u_ctrl_fsm (
        .clk(clk),
        .rst_n(rst_n),
        .sw(sw),
        .key(key[3:0]),
        .error_flag(error_flag_ctrl),
        .busy_flag(busy_flag_ctrl),
        .done_flag(done_flag_ctrl),
        .select_done(select_done),
        .select_error(select_error),
        .selected_a(selected_a),
        .selected_b(selected_b),
        .format_done(format_done),
        
        .mode_sel(mode_sel),
        .op_sel(op_sel),
        .countdown_val(countdown_val),
        .start_input(start_input),
        .start_gen(start_gen),
        .start_disp(start_disp),
        .start_op(start_op),
        .tx_start(tx_start),
        .start_select(start_select),
        .manual_mode(manual_mode),
        .operand_a_id(operand_a_id),
        .operand_b_id(operand_b_id),
        .display_mode(display_mode),
        .start_format(start_format)
    );

    uart_rx u_uart_rx (
        .clk(clk),
        .rst_n(rst_n),
        .rx(uart_rx),
        .rx_data(rx_data),
        .rx_valid(rx_valid)
    );

    uart_cmd_parser u_uart_cmd_parser (
        .clk(clk),
        .rst_n(rst_n),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .mode_sel(mode_sel),
        .start_input(start_input),
        .start_gen(start_gen),
        .in_operand_select(start_select),
        
        .dim_m(dim_m),
        .dim_n(dim_n),
        .elem_data(elem_data),
        .elem_min(elem_min),
        .elem_max(elem_max),
        .count(count),
        .matrix_id(matrix_id_in),
        .write_en(write_en),
        .data_ready(data_ready),
        .user_id_a(user_id_a),
        .user_id_b(user_id_b),
        .user_input_valid(user_input_valid)
    );

    rand_matrix_gen u_rand_matrix_gen (
        .clk(clk),
        .rst_n(rst_n),
        .start_gen(start_gen),
        .dim_m(dim_m),
        .dim_n(dim_n),
        .count(count),
        .elem_min(elem_min),
        .elem_max(elem_max),
        .gen_done(gen_done),
        .data_out(rand_data_out),
        .write_en(rand_write_en)
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
        .load_operands(load_operands),
        .operand_a_id(operand_a_id),
        .operand_b_id(operand_b_id),
        .req_list_info(req_list_info),
        
        .data_out(ms_data_out),
        .matrix_id_out(matrix_id_out),
        .meta_info_valid(meta_info_valid),
        .error_flag(error_flag_storage),
        .matrix_a(matrix_a),
        .matrix_b(matrix_b),
        .matrix_a_m(matrix_a_m),
        .matrix_a_n(matrix_a_n),
        .matrix_b_m(matrix_b_m),
        .matrix_b_n(matrix_b_n),
        .list_m(list_m),
        .list_n(list_n),
        .list_valid(list_valid)
    );

    operand_selector u_operand_selector (
        .clk(clk),
        .rst_n(rst_n),
        .start_select(start_select),
        .manual_mode(manual_mode),
        .op_type(op_sel),
        .user_id_a(user_id_a),
        .user_id_b(user_id_b),
        .user_input_valid(user_input_valid),
        .meta_m(list_m),
        .meta_n(list_n),
        .meta_valid(list_valid),
        
        .selected_a(selected_a),
        .selected_b(selected_b),
        .select_done(select_done),
        .select_error(select_error)
    );

    display_formatter u_display_formatter (
        .clk(clk),
        .rst_n(rst_n),
        .start_format(start_format),
        .display_mode(display_mode),
        .matrix_id(matrix_id_out),
        .dim_m(matrix_a_m),
        .dim_n(matrix_a_n),
        .matrix_data(matrix_data_to_fmt),
        .matrix_data_valid(matrix_data_valid_fmt),
        .list_m(list_m),
        .list_n(list_n),
        .list_valid(list_valid),
        
        .tx_data(tx_data_fmt),
        .tx_valid(tx_valid_fmt),
        .tx_busy(tx_busy),
        .format_done(format_done)
    );

    mat_ops u_mat_ops (
        .clk(clk),
        .rst_n(rst_n),
        .start_op(start_op),
        .op_sel(op_sel),
        .matrix_a(matrix_a[0]),  // 简化：直接传首元素
        .matrix_b(matrix_b[0]),
        .scalar_k(scalar_k),
        
        .op_done(op_done),
        .result_data(result_data),
        .busy_flag(busy_flag_ops),
        .error_flag(error_flag_ops)
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

    uart_tx u_uart_tx (
        .clk(clk),
        .rst_n(rst_n),
        .tx_start(tx_valid_fmt),
        .tx_data(tx_data_fmt),
        .uart_tx(uart_tx),
        .tx_busy(tx_busy)
    );

endmodule