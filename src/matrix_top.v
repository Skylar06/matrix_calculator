/******************************************************************************
 * ???????: matrix_top
 * ????????: ???????
 *          - ?????????????
 *          - ??????scalar_k ?? config_manager ???
 *          - ?????????? mat_ops ???????????
 ******************************************************************************/
module matrix_top (
    input clk,
    input rst_n,
    input [7:0] sw,           // 8????????
    input [4:0] key,          // 5??????
    input uart_rx,

    output uart_tx,
    output [2:0] led,
    output [3:0] seg_sel,
    output [7:0] seg_data
);

    // ==========================================================================
    // 复位信号处理
    // Ego1开发板的复位按键可能是高电平有效，如果J3一直闪烁，尝试反相复位
    // ==========================================================================
    // 方法1：如果复位按键是高电平有效（按下为高），取消注释以下两行：
    // wire rst_n_internal;
    // assign rst_n_internal = ~rst_n;
    // 然后将所有模块的 rst_n 改为 rst_n_internal
    
    // 方法2：添加复位同步器（推荐，更可靠）
    reg rst_n_sync1, rst_n_sync2;
    always @(posedge clk) begin
        rst_n_sync1 <= rst_n;
        rst_n_sync2 <= rst_n_sync1;
    end
    wire rst_n_synced = rst_n_sync2;  // 同步后的复位信号
    
    // ==========================================================================
    // ctrl_fsm 信号
    // ==========================================================================
    wire [1:0] mode_sel;
    wire [2:0] op_sel;
    wire [7:0] countdown_val;
    wire start_input, start_gen, start_disp, start_op, tx_start;
    wire start_select, start_format;
    wire manual_mode;
    wire [3:0] operand_a_id, operand_b_id;
    wire [1:0] display_mode;
    
    // ==========================================================================
    // ????/??/?????
    // ==========================================================================
    wire error_flag_ctrl, busy_flag_ctrl, done_flag_ctrl;
    wire select_done, select_error, format_done;

    // ==========================================================================
    // UART RX / parser ???
    // ==========================================================================
    wire [7:0] rx_data;
    wire rx_valid;
    wire [2:0] dim_m, dim_n;
    wire [7:0] elem_data;
    wire [3:0] count, matrix_id_in;
    wire [3:0] user_id_a, user_id_b;
    wire data_ready, user_input_valid;
    
    // CONFIG ??????
    wire config_valid;
    wire [2:0] config_type;
    wire signed [7:0] config_value1;
    wire signed [7:0] config_value2;

    // ==========================================================================
    // config_manager ???
    // ==========================================================================
    wire signed [7:0] elem_min_cfg;
    wire signed [7:0] elem_max_cfg;
    wire [7:0] countdown_init_cfg;
    wire signed [7:0] scalar_k_cfg;        // ????????????????????K
    wire query_max_per_size;
    wire [3:0] max_per_size_out;
    wire config_done, config_error;

    // ==========================================================================
    // storage ???
    // ==========================================================================
    wire [7:0] ms_data_in, ms_data_out;
    wire [3:0] matrix_id_out;
    wire [8*25-1:0] matrix_a_flat;        // ???????
    wire [8*25-1:0] matrix_b_flat;        // ???????
    wire [2:0] matrix_a_m, matrix_a_n, matrix_b_m, matrix_b_n;
    wire [3*10-1:0] list_m_flat;
    wire [3*10-1:0] list_n_flat;
    wire [10-1:0]   list_valid_flat;
    wire [7:0] result_data;
    wire [2:0] result_m, result_n;
    wire meta_info_valid, error_flag_storage;
    wire load_operands, req_list_info;
    wire write_en_parser, write_en_rand;
    wire read_en;

    // ==========================================================================
    // operand_selector ???
    // ==========================================================================
    wire [3:0] selected_a, selected_b;
    
    // ==========================================================================
    // display_formatter ???
    // ==========================================================================
    wire [7:0] tx_data_fmt;
    wire tx_valid_fmt;
    wire [7:0] matrix_data_to_fmt;
    wire matrix_data_valid_fmt;
    wire tx_busy;
    wire fmt_data_req;
    
    // ==========================================================================
    // ????????????
    // ==========================================================================
    wire [7:0] rand_data_out;
    wire rand_write_en;
    wire gen_done;
    
    // ==========================================================================
    // ??????????
    // ==========================================================================
    wire op_done, busy_flag_ops, error_flag_ops;
    
    // ==========================================================================
    // ??????????
    // ==========================================================================
    assign ms_data_in = (start_gen) ? rand_data_out : elem_data;
    assign read_en = fmt_data_req;                     // ???????????????
    assign matrix_data_to_fmt = ms_data_out;           // ???????????????
    
    // ==========================================================================
    // ??????????
    // ==========================================================================
    assign error_flag_ctrl = error_flag_ops | error_flag_storage | select_error | config_error;
    assign busy_flag_ctrl  = busy_flag_ops;
    assign done_flag_ctrl  = op_done | gen_done | config_done;
    
    // ==========================================================================
    // ?????????????
    // ==========================================================================
    assign load_operands = start_op;
    
    // ==========================================================================
    // ??????????
    // ==========================================================================
    assign req_list_info = (display_mode == 2'd1);
    
    // ==========================================================================
    // ????????????? config_manager
    // ==========================================================================
    config_manager u_config_manager (
        .clk(clk),
        .rst_n(rst_n_synced),
        
        // ========== ???????????? ==========
        .config_valid(config_valid),
        .config_type(config_type),
        .config_value1(config_value1),
        .config_value2(config_value2),
        
        // ========== ?????????????==========
        .elem_min(elem_min_cfg),
        .elem_max(elem_max_cfg),
        .countdown_init(countdown_init_cfg),
        .scalar_k(scalar_k_cfg),              // ??????????????K
        
        // ========== ?????? ==========
        .query_max_per_size(query_max_per_size),
        .max_per_size_out(max_per_size_out),
        
        // ========== ????? ==========
        .config_done(config_done),
        .config_error(config_error),
        
        // ========== ????????????==========
        .show_max_per_size(),
        .show_elem_min(),
        .show_elem_max(),
        .show_countdown(),
        .show_scalar_k()
    );
    
    // ==========================================================================
    // ????? ctrl_fsm
    // ==========================================================================
    ctrl_fsm u_ctrl_fsm (
        .clk(clk),
        .rst_n(rst_n_synced),
        .sw(sw[5:0]),                         // ????6??????/????/??????
        .key(key[3:0]),
        .error_flag(error_flag_ctrl),
        .busy_flag(busy_flag_ctrl),
        .done_flag(done_flag_ctrl),
        .select_done(select_done),
        .select_error(select_error),
        .selected_a(selected_a),
        .selected_b(selected_b),
        .format_done(format_done),
        
        // ========== ???????????? ==========
        .countdown_init_cfg(countdown_init_cfg),
        
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

    // ==========================================================================
    // ????? uart_rx
    // ==========================================================================
    uart_rx u_uart_rx (
        .clk(clk),
        .rst_n(rst_n_synced),
        .rx(uart_rx),
        .rx_data(rx_data),
        .rx_valid(rx_valid)
    );

    // ==========================================================================
    // ????? uart_cmd_parser???????CONFIG SCALAR??????
    // ==========================================================================
    uart_cmd_parser u_uart_cmd_parser (
        .clk(clk),
        .rst_n(rst_n_synced),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .mode_sel(mode_sel),
        .start_input(start_input),
        .start_gen(start_gen),
        .in_operand_select(start_select),
        
        // ========== ????????/??????? ==========
        .dim_m(dim_m),
        .dim_n(dim_n),
        .elem_data(elem_data),
        .elem_min(),                          // ???????
        .elem_max(),                          // ???????
        .count(count),
        .matrix_id(matrix_id_in),
        .write_en(write_en_parser),  // uart_cmd_parser ����� write_en
        .data_ready(data_ready),
        
        // ========== ???????????? ==========
        .user_id_a(user_id_a),
        .user_id_b(user_id_b),
        .user_input_valid(user_input_valid),
        
        // ========== CONFIG ??????? ==========
        .config_valid(config_valid),
        .config_type(config_type),
        .config_value1(config_value1),
        .config_value2(config_value2)
    );

    // ==========================================================================
    // ????? rand_matrix_gen????????????????
    // ==========================================================================
    rand_matrix_gen u_rand_matrix_gen (
        .clk(clk),
        .rst_n(rst_n_synced),
        .start_gen(start_gen),
        .dim_m(dim_m),
        .dim_n(dim_n),
        .count(count),
        
        // ========== ???????????? ==========
        .elem_min_cfg(elem_min_cfg),
        .elem_max_cfg(elem_max_cfg),
        
        .gen_done(gen_done),
        .data_out(rand_data_out),
        .write_en(rand_write_en)
    );

    // ==========================================================================
    // ????? matrix_storage????????????????
    // ==========================================================================
    matrix_storage u_matrix_storage (
        .clk(clk),
        .rst_n(rst_n_synced),
        
        // ========== ???????????? ==========
        .elem_min(elem_min_cfg),
        .elem_max(elem_max_cfg),
        .query_max_per_size(query_max_per_size),
        .max_per_size_in(max_per_size_out),
        
        // ========== ?????? ==========
        .write_en(write_en_parser | rand_write_en),
        .read_en(read_en),
        .dim_m(dim_m),
        .dim_n(dim_n),
        .data_in(ms_data_in),
        .matrix_id_in(matrix_id_in),
        
        // ========== ????????? ==========
        .result_data(result_data),
        .op_done(op_done),
        .result_m(result_m),
        .result_n(result_n),
        
        // ========== ??????? ==========
        .start_input(start_input),
        .start_disp(start_disp),
        .load_operands(load_operands),
        .operand_a_id(operand_a_id),
        .operand_b_id(operand_b_id),
        .req_list_info(req_list_info),
        
        // ========== ?????? ==========
        .data_out(ms_data_out),
        .matrix_id_out(matrix_id_out),
        .meta_info_valid(meta_info_valid),
        .matrix_data_valid(matrix_data_valid_fmt),
        .error_flag(error_flag_storage),
        .matrix_a_flat(matrix_a_flat),       // ???????
        .matrix_b_flat(matrix_b_flat),       // ???????
        .matrix_a_m(matrix_a_m),
        .matrix_a_n(matrix_a_n),
        .matrix_b_m(matrix_b_m),
        .matrix_b_n(matrix_b_n),
        .list_m_flat(list_m_flat),
        .list_n_flat(list_n_flat),
        .list_valid_flat(list_valid_flat)
    );

    // ==========================================================================
    // ????? operand_selector
    // ==========================================================================
    operand_selector u_operand_selector (
        .clk(clk),
        .rst_n(rst_n_synced),
        .start_select(start_select),
        .manual_mode(manual_mode),
        .op_type(op_sel),
        .user_id_a(user_id_a),
        .user_id_b(user_id_b),
        .user_input_valid(user_input_valid),
        .meta_m_flat(list_m_flat),
        .meta_n_flat(list_n_flat),
        .meta_valid_flat(list_valid_flat),
        
        .selected_a(selected_a),
        .selected_b(selected_b),
        .select_done(select_done),
        .select_error(select_error)
    );

    // ==========================================================================
    // ????? display_formatter
    // ==========================================================================
    display_formatter u_display_formatter (
        .clk(clk),
        .rst_n(rst_n_synced),
        .start_format(start_format),
        .display_mode(display_mode),
        .matrix_id(matrix_id_out),
        .dim_m(matrix_a_m),
        .dim_n(matrix_a_n),
        .matrix_data(matrix_data_to_fmt),
        .matrix_data_valid(matrix_data_valid_fmt),
        .list_m_flat(list_m_flat),
        .list_n_flat(list_n_flat),
        .list_valid_flat(list_valid_flat),
        
        .tx_data(tx_data_fmt),
        .tx_valid(tx_valid_fmt),
        .tx_busy(tx_busy),
        .data_req(fmt_data_req),
        .format_done(format_done)
    );

    // ==========================================================================
    // ????? mat_ops
    // ==========================================================================
    mat_ops u_mat_ops (
        .clk(clk),
        .rst_n(rst_n_synced),
        .start_op(start_op),
        .op_sel(op_sel),
        
        // ========== ????????????????????? ==========
        .matrix_a_flat(matrix_a_flat),    // ? ????????????25??????
        .matrix_b_flat(matrix_b_flat),    // ? ????????????25??????
        
        // ========== ?????????????????? ==========
        .dim_a_m(matrix_a_m),
        .dim_a_n(matrix_a_n),
        .dim_b_m(matrix_b_m),
        .dim_b_n(matrix_b_n),
        
        // ========== ????K???????? ==========
        .scalar_k(scalar_k_cfg),
        
        // ========== ??? ==========
        .op_done(op_done),
        .result_data(result_data),
        .result_m(result_m),              // ?????????????????
        .result_n(result_n),              // ?????????????????
        .busy_flag(busy_flag_ops),
        .error_flag(error_flag_ops)
    );

    // ==========================================================================
    // ????? seg_display
    // ==========================================================================
    seg_display u_seg_display (
        .clk(clk),
        .rst_n(rst_n_synced),
        .mode_sel(mode_sel),
        .op_sel(op_sel),
        .countdown_val(countdown_val),
        .matrix_id_out(matrix_id_out),
        
        .seg_sel(seg_sel),
        .seg_data(seg_data)
    );

    // ==========================================================================
    // ????? led_status
    // ==========================================================================
    led_status u_led_status (
        .clk(clk),
        .rst_n(rst_n_synced),
        .error_flag(error_flag_ctrl),
        .busy_flag(busy_flag_ctrl),
        .done_flag(done_flag_ctrl),
        
        .led(led)
    );

    // ==========================================================================
    // ????? uart_tx
    // ==========================================================================
    uart_tx u_uart_tx (
        .clk(clk),
        .rst_n(rst_n_synced),
        .tx_start(tx_valid_fmt),
        .tx_data(tx_data_fmt),
        .tx(uart_tx),
        .tx_busy(tx_busy)
    );

endmodule

/******************************************************************************
 * ??????????
 * 
 * 1. ?????????sw[7:0]????
 *    sw[5:0] ?? ctrl_fsm????/????/??????
 *    sw[7:6] ?? ???????????????
 * 
 * 2. ????K?????
 *    - ??????3
 *    - ???UART?????????CONFIG SCALAR <value>
 *    - ????????CONFIG SCALAR -5
 *    - ??????[-128, 127]
 * 
 * 3. ?????????????
 *    - mat_ops ???????????? matrix_a[0:24] ?? matrix_b[0:24]
 *    - ???????????? matrix_a[0]
 * 
 * 4. ?????????????
 *    - elem_min/elem_max ?? config_manager??UART?????
 *    - countdown_init ?? config_manager??UART?????
 *    - max_per_size ?? config_manager??UART?????
 *    - scalar_k ?? config_manager??UART?????
 ******************************************************************************/