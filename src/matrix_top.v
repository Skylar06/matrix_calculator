/******************************************************************************
 * 模块名称: matrix_top
 * 功能描述: 顶层模块
 *          - 连接所有子模块
 *          - 【修改】scalar_k 从 config_manager 获取
 *          - 【修改】修正 mat_ops 的数组传递方式
 ******************************************************************************/
module matrix_top (
    input clk,
    input rst_n,
    input [7:0] sw,           // 8位拨码开关
    input [4:0] key,          // 5个按键
    input uart_rx,

    output uart_tx,
    output [2:0] led,
    output [3:0] seg_sel,
    output [7:0] seg_data
);

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
    // 错误/忙碌/完成标志
    // ==========================================================================
    wire error_flag_ctrl, busy_flag_ctrl, done_flag_ctrl;
    wire select_done, select_error, format_done;

    // ==========================================================================
    // UART RX / parser 信号
    // ==========================================================================
    wire [7:0] rx_data;
    wire rx_valid;
    wire [2:0] dim_m, dim_n;
    wire [7:0] elem_data;
    wire [3:0] count, matrix_id_in;
    wire [3:0] user_id_a, user_id_b;
    wire data_ready, user_input_valid;
    
    // CONFIG 命令接口
    wire config_valid;
    wire [2:0] config_type;
    wire signed [7:0] config_value1;
    wire signed [7:0] config_value2;

    // ==========================================================================
    // config_manager 信号
    // ==========================================================================
    wire signed [7:0] elem_min_cfg;
    wire signed [7:0] elem_max_cfg;
    wire [7:0] countdown_init_cfg;
    wire signed [7:0] scalar_k_cfg;        // 【新增】从配置获取标量K
    wire query_max_per_size;
    wire [3:0] max_per_size_out;
    wire config_done, config_error;

    // ==========================================================================
    // storage 信号
    // ==========================================================================
    wire [7:0] ms_data_in, ms_data_out;
    wire [3:0] matrix_id_out;
    wire [7:0] matrix_a [0:24];           // 完整数组（25个元素）
    wire [7:0] matrix_b [0:24];           // 完整数组（25个元素）
    wire [2:0] matrix_a_m, matrix_a_n, matrix_b_m, matrix_b_n;
    wire [2:0] list_m [0:9];
    wire [2:0] list_n [0:9];
    wire list_valid [0:9];
    wire [7:0] result_data;
    wire [2:0] result_m, result_n;
    wire meta_info_valid, error_flag_storage;
    wire load_operands, req_list_info;
    wire write_en_parser, write_en_rand;
    wire read_en;

    // ==========================================================================
    // operand_selector 信号
    // ==========================================================================
    wire [3:0] selected_a, selected_b;
    
    // ==========================================================================
    // display_formatter 信号
    // ==========================================================================
    wire [7:0] tx_data_fmt;
    wire tx_valid_fmt;
    wire [7:0] matrix_data_to_fmt;
    wire matrix_data_valid_fmt;
    wire tx_busy;
    wire fmt_data_req;
    
    // ==========================================================================
    // 随机生成器信号
    // ==========================================================================
    wire [7:0] rand_data_out;
    wire rand_write_en;
    wire gen_done;
    
    // ==========================================================================
    // 运算模块信号
    // ==========================================================================
    wire op_done, busy_flag_ops, error_flag_ops;
    
    // ==========================================================================
    // 数据通路选择
    // ==========================================================================
    assign ms_data_in = (start_gen) ? rand_data_out : elem_data;
    assign write_en_parser = (start_input && data_ready);
    assign read_en = fmt_data_req;                     // 由显示模块拉取数据
    assign matrix_data_to_fmt = ms_data_out;           // 将存储输出送往显示
    
    // ==========================================================================
    // 错误标志汇总
    // ==========================================================================
    assign error_flag_ctrl = error_flag_ops | error_flag_storage | select_error | config_error;
    assign busy_flag_ctrl  = busy_flag_ops;
    assign done_flag_ctrl  = op_done | gen_done | config_done;
    
    // ==========================================================================
    // 运算数加载信号
    // ==========================================================================
    assign load_operands = start_op;
    
    // ==========================================================================
    // 列表查询信号
    // ==========================================================================
    assign req_list_info = (display_mode == 2'd1);
    
    // ==========================================================================
    // 【新增】实例化 config_manager
    // ==========================================================================
    config_manager u_config_manager (
        .clk(clk),
        .rst_n(rst_n),
        
        // ========== 配置命令输入 ==========
        .config_valid(config_valid),
        .config_type(config_type),
        .config_value1(config_value1),
        .config_value2(config_value2),
        
        // ========== 参数输出（广播）==========
        .elem_min(elem_min_cfg),
        .elem_max(elem_max_cfg),
        .countdown_init(countdown_init_cfg),
        .scalar_k(scalar_k_cfg),              // 【关键】输出标量K
        
        // ========== 查询接口 ==========
        .query_max_per_size(query_max_per_size),
        .max_per_size_out(max_per_size_out),
        
        // ========== 状态输出 ==========
        .config_done(config_done),
        .config_error(config_error),
        
        // ========== 回显接口（可选）==========
        .show_max_per_size(),
        .show_elem_min(),
        .show_elem_max(),
        .show_countdown(),
        .show_scalar_k()
    );
    
    // ==========================================================================
    // 实例化 ctrl_fsm
    // ==========================================================================
    ctrl_fsm u_ctrl_fsm (
        .clk(clk),
        .rst_n(rst_n),
        .sw(sw[5:0]),                         // 只用低6位：模式/运算/手动选择
        .key(key[3:0]),
        .error_flag(error_flag_ctrl),
        .busy_flag(busy_flag_ctrl),
        .done_flag(done_flag_ctrl),
        .select_done(select_done),
        .select_error(select_error),
        .selected_a(selected_a),
        .selected_b(selected_b),
        .format_done(format_done),
        
        // ========== 接入配置参数 ==========
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
    // 实例化 uart_rx
    // ==========================================================================
    uart_rx u_uart_rx (
        .clk(clk),
        .rst_n(rst_n),
        .rx(uart_rx),
        .rx_data(rx_data),
        .rx_valid(rx_valid)
    );

    // ==========================================================================
    // 实例化 uart_cmd_parser（已增强CONFIG SCALAR解析）
    // ==========================================================================
    uart_cmd_parser u_uart_cmd_parser (
        .clk(clk),
        .rst_n(rst_n),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .mode_sel(mode_sel),
        .start_input(start_input),
        .start_gen(start_gen),
        .in_operand_select(start_select),
        
        // ========== 矩阵输入/生成输出 ==========
        .dim_m(dim_m),
        .dim_n(dim_n),
        .elem_data(elem_data),
        .elem_min(),                          // 不再使用
        .elem_max(),                          // 不再使用
        .count(count),
        .matrix_id(matrix_id_in),
        .write_en(write_en_parser),
        .data_ready(data_ready),
        
        // ========== 运算数选择输出 ==========
        .user_id_a(user_id_a),
        .user_id_b(user_id_b),
        .user_input_valid(user_input_valid),
        
        // ========== CONFIG 命令输出 ==========
        .config_valid(config_valid),
        .config_type(config_type),
        .config_value1(config_value1),
        .config_value2(config_value2)
    );

    // ==========================================================================
    // 实例化 rand_matrix_gen（接入配置参数）
    // ==========================================================================
    rand_matrix_gen u_rand_matrix_gen (
        .clk(clk),
        .rst_n(rst_n),
        .start_gen(start_gen),
        .dim_m(dim_m),
        .dim_n(dim_n),
        .count(count),
        
        // ========== 接入配置参数 ==========
        .elem_min_cfg(elem_min_cfg),
        .elem_max_cfg(elem_max_cfg),
        
        .gen_done(gen_done),
        .data_out(rand_data_out),
        .write_en(rand_write_en)
    );

    // ==========================================================================
    // 实例化 matrix_storage（接入配置参数）
    // ==========================================================================
    matrix_storage u_matrix_storage (
        .clk(clk),
        .rst_n(rst_n),
        
        // ========== 配置参数输入 ==========
        .elem_min(elem_min_cfg),
        .elem_max(elem_max_cfg),
        .query_max_per_size(query_max_per_size),
        .max_per_size_in(max_per_size_out),
        
        // ========== 写入接口 ==========
        .write_en(write_en_parser | rand_write_en),
        .read_en(read_en),
        .dim_m(dim_m),
        .dim_n(dim_n),
        .data_in(ms_data_in),
        .matrix_id_in(matrix_id_in),
        
        // ========== 运算结果存储 ==========
        .result_data(result_data),
        .op_done(op_done),
        .result_m(result_m),
        .result_n(result_n),
        
        // ========== 控制信号 ==========
        .start_input(start_input),
        .start_disp(start_disp),
        .load_operands(load_operands),
        .operand_a_id(operand_a_id),
        .operand_b_id(operand_b_id),
        .req_list_info(req_list_info),
        
        // ========== 输出接口 ==========
        .data_out(ms_data_out),
        .matrix_id_out(matrix_id_out),
        .meta_info_valid(meta_info_valid),
        .matrix_data_valid(matrix_data_valid_fmt),
        .error_flag(error_flag_storage),
        .matrix_a(matrix_a),                 // 输出完整数组
        .matrix_b(matrix_b),                 // 输出完整数组
        .matrix_a_m(matrix_a_m),
        .matrix_a_n(matrix_a_n),
        .matrix_b_m(matrix_b_m),
        .matrix_b_n(matrix_b_n),
        .list_m(list_m),
        .list_n(list_n),
        .list_valid(list_valid)
    );

    // ==========================================================================
    // 实例化 operand_selector
    // ==========================================================================
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

    // ==========================================================================
    // 实例化 display_formatter
    // ==========================================================================
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
        .data_req(fmt_data_req),
        .format_done(format_done)
    );

    // ==========================================================================
    // 实例化 mat_ops
    // ==========================================================================
    mat_ops u_mat_ops (
        .clk(clk),
        .rst_n(rst_n),
        .start_op(start_op),
        .op_sel(op_sel),
        
        // ========== 【关键】直接传递完整数组 ==========
        .matrix_a(matrix_a),              // ✅ 传递完整数组（25个元素）
        .matrix_b(matrix_b),              // ✅ 传递完整数组（25个元素）
        
        // ========== 【新增】传递维度信息 ==========
        .dim_a_m(matrix_a_m),
        .dim_a_n(matrix_a_n),
        .dim_b_m(matrix_b_m),
        .dim_b_n(matrix_b_n),
        
        // ========== 标量K从配置获取 ==========
        .scalar_k(scalar_k_cfg),
        
        // ========== 输出 ==========
        .op_done(op_done),
        .result_data(result_data),
        .result_m(result_m),              // 【新增】接收结果维度
        .result_n(result_n),              // 【新增】接收结果维度
        .busy_flag(busy_flag_ops),
        .error_flag(error_flag_ops)
    );

    // ==========================================================================
    // 实例化 seg_display
    // ==========================================================================
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

    // ==========================================================================
    // 实例化 led_status
    // ==========================================================================
    led_status u_led_status (
        .clk(clk),
        .rst_n(rst_n),
        .error_flag(error_flag_ctrl),
        .busy_flag(busy_flag_ctrl),
        .done_flag(done_flag_ctrl),
        
        .led(led)
    );

    // ==========================================================================
    // 实例化 uart_tx
    // ==========================================================================
    uart_tx u_uart_tx (
        .clk(clk),
        .rst_n(rst_n),
        .tx_start(tx_valid_fmt),
        .tx_data(tx_data_fmt),
        .tx(uart_tx),
        .tx_busy(tx_busy)
    );

endmodule

/******************************************************************************
 * 顶层模块说明
 * 
 * 1. 拨码开关分配（sw[7:0]）：
 *    sw[5:0] → ctrl_fsm（模式/运算/手动选择）
 *    sw[7:6] → 保留（未来扩展）
 * 
 * 2. 标量K配置：
 *    - 默认值：3
 *    - 通过UART命令设置：CONFIG SCALAR <value>
 *    - 支持负数：CONFIG SCALAR -5
 *    - 范围：[-128, 127]
 * 
 * 3. 数组传递修正：
 *    - mat_ops 接收完整数组 matrix_a[0:24] 和 matrix_b[0:24]
 *    - 而不是单个元素 matrix_a[0]
 * 
 * 4. 配置参数来源：
 *    - elem_min/elem_max → config_manager（UART配置）
 *    - countdown_init → config_manager（UART配置）
 *    - max_per_size → config_manager（UART配置）
 *    - scalar_k → config_manager（UART配置）
 ******************************************************************************/