/******************************************************************************
 * 模块名称: matrix_top
 * 功能描述: 顶层封装
 *          - 连接控制路径与数据路径
 *          - 将scalar_k等配置从config_manager分发
 *          - 将存储的矩阵馈入 mat_ops 运算
 ******************************************************************************/
module matrix_top (
    input clk,
    input rst_n,
    input [7:0] sw,           // 8个拨码开关
    input [4:0] key,          // 5个按键
    input uart_rx,

    output uart_tx,
    output [2:0] led,
    output [3:0] seg_sel,
    output [7:0] seg_data
);

    // ==========================================================================
    // 1. 复位信号处理 (异步复位，同步释放)
    // ==========================================================================
    reg rst_n_sync1, rst_n_sync2;
    wire rst_n_synced;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rst_n_sync1 <= 1'b0;
            rst_n_sync2 <= 1'b0;
        end else begin
            rst_n_sync1 <= 1'b1;
            rst_n_sync2 <= rst_n_sync1;
        end
    end
    
    assign rst_n_synced = rst_n_sync2;

    // ==========================================================================
    // 2. 输入信号同步与消抖 (解决Timing Violation和FSM乱跳的核心)
    // ==========================================================================
    
    // --- 开关同步 ---
    reg [7:0] sw_r1, sw_r2;
    always @(posedge clk) begin
        sw_r1 <= sw;
        sw_r2 <= sw_r1; // 使用 sw_r2 作为稳定的内部信号
    end

    // --- 按键消抖与边沿检测 ---
    // 20ms 消抖计数器 (100MHz时钟下约2_000_000个周期)
    localparam DEBOUNCE_CNT_MAX = 2000000; 
    reg [4:0] key_r1, key_r2;    // 同步寄存器
    reg [4:0] key_stable;        // 消抖后的稳定状态
    reg [4:0] key_pulse;         // 按键按下脉冲(上升沿)
    reg [31:0] cnt_key [4:0];    // 每个按键的计数器

    genvar i;
    generate
        for(i=0; i<5; i=i+1) begin : key_proc
            always @(posedge clk) begin
                if (!rst_n_synced) begin
                    key_r1[i] <= 1'b0;
                    key_r2[i] <= 1'b0;
                    key_stable[i] <= 1'b0;
                    key_pulse[i] <= 1'b0;
                    cnt_key[i] <= 32'd0;
                end else begin
                    // 1. 同步输入
                    key_r1[i] <= key[i]; // 假设外部电路未反相，按下为高
                    key_r2[i] <= key_r1[i];

                    // 2. 消抖逻辑
                    if (key_r2[i] != key_stable[i]) begin
                        if (cnt_key[i] < DEBOUNCE_CNT_MAX) begin
                            cnt_key[i] <= cnt_key[i] + 1;
                        end else begin
                            key_stable[i] <= key_r2[i]; // 状态稳定，更新
                            cnt_key[i] <= 0;
                            
                            // 3. 生成脉冲 (仅在按下瞬间产生一个周期的脉冲)
                            if (key_r2[i] == 1'b1) 
                                key_pulse[i] <= 1'b1;
                        end
                    end else begin
                        cnt_key[i] <= 0;
                        key_pulse[i] <= 1'b0; // 其他时候脉冲为0
                    end
                end
            end
        end
    endgenerate

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
    // 错误/忙/完成标志
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
    
    // CONFIG 配置接口
    wire config_valid;
    wire [2:0] config_type;
    wire signed [7:0] config_value1;
    wire signed [7:0] config_value2;

    // ==========================================================================
    // config_manager 输出
    // ==========================================================================
    wire signed [7:0] elem_min_cfg;
    wire signed [7:0] elem_max_cfg;
    wire [7:0] countdown_init_cfg;
    wire signed [7:0] scalar_k_cfg;
    wire query_max_per_size;
    wire [3:0] max_per_size_out;
    wire config_done, config_error;

    // ==========================================================================
    // storage 信号
    // ==========================================================================
    wire [7:0] ms_data_in, ms_data_out;
    wire [3:0] matrix_id_out;
    wire [8*25-1:0] matrix_a_flat;
    wire [8*25-1:0] matrix_b_flat;
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
    // 随机矩阵生成
    // ==========================================================================
    wire [7:0] rand_data_out;
    wire rand_write_en;
    wire gen_done;
    
    // ==========================================================================
    // 运算核心
    // ==========================================================================
    wire op_done, busy_flag_ops, error_flag_ops;
    
    // ==========================================================================
    // 读写与显示连接
    // ==========================================================================
    assign ms_data_in = (start_gen) ? rand_data_out : elem_data;
    assign read_en = fmt_data_req;
    assign matrix_data_to_fmt = ms_data_out;
    
    // ==========================================================================
    // 请求列表信息
    // ==========================================================================
    assign error_flag_ctrl = error_flag_ops | error_flag_storage | select_error | config_error;
    assign busy_flag_ctrl  = busy_flag_ops;
    assign done_flag_ctrl  = op_done | gen_done | config_done;
    
    assign load_operands = start_op;
    assign req_list_info = (display_mode == 2'd1);
    
    // ==========================================================================
    // 实例化 config_manager
    // ==========================================================================
    config_manager u_config_manager (
        .clk(clk),
        .rst_n(rst_n_synced),
        .config_valid(config_valid),
        .config_type(config_type),
        .config_value1(config_value1),
        .config_value2(config_value2),
        .elem_min(elem_min_cfg),
        .elem_max(elem_max_cfg),
        .countdown_init(countdown_init_cfg),
        .scalar_k(scalar_k_cfg),
        .query_max_per_size(query_max_per_size),
        .max_per_size_out(max_per_size_out),
        .config_done(config_done),
        .config_error(config_error),
        .show_max_per_size(),
        .show_elem_min(),
        .show_elem_max(),
        .show_countdown(),
        .show_scalar_k()
    );
    
    // ==========================================================================
    // 实例化 ctrl_fsm
    // ！！注意：这里连接的是消抖后的脉冲信号 key_pulse 和同步后的开关 sw_r2 ！！
    // ==========================================================================
    ctrl_fsm u_ctrl_fsm (
        .clk(clk),
        .rst_n(rst_n_synced),
        .sw(sw_r2[5:0]),          // 使用同步后的开关
        .key(key_pulse[3:0]),     // 使用消抖后的按键脉冲
        .error_flag(error_flag_ctrl),
        .busy_flag(busy_flag_ctrl),
        .done_flag(done_flag_ctrl),
        .select_done(select_done),
        .select_error(select_error),
        .selected_a(selected_a),
        .selected_b(selected_b),
        .format_done(format_done),
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
        .rst_n(rst_n_synced),
        .rx(uart_rx),
        .rx_data(rx_data),
        .rx_valid(rx_valid)
    );

    // ==========================================================================
    // 实例化 uart_cmd_parser
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
        .dim_m(dim_m),
        .dim_n(dim_n),
        .elem_data(elem_data),
        .elem_min(),
        .elem_max(),
        .count(count),
        .matrix_id(matrix_id_in),
        .write_en(write_en_parser),
        .data_ready(data_ready),
        .user_id_a(user_id_a),
        .user_id_b(user_id_b),
        .user_input_valid(user_input_valid),
        .config_valid(config_valid),
        .config_type(config_type),
        .config_value1(config_value1),
        .config_value2(config_value2)
    );

    // ==========================================================================
    // 实例化 rand_matrix_gen
    // ==========================================================================
    rand_matrix_gen u_rand_matrix_gen (
        .clk(clk),
        .rst_n(rst_n_synced),
        .start_gen(start_gen),
        .dim_m(dim_m),
        .dim_n(dim_n),
        .count(count),
        .elem_min_cfg(elem_min_cfg),
        .elem_max_cfg(elem_max_cfg),
        .gen_done(gen_done),
        .data_out(rand_data_out),
        .write_en(rand_write_en)
    );

    // ==========================================================================
    // 实例化 matrix_storage
    // ==========================================================================
    matrix_storage u_matrix_storage (
        .clk(clk),
        .rst_n(rst_n_synced),
        .elem_min(elem_min_cfg),
        .elem_max(elem_max_cfg),
        .query_max_per_size(query_max_per_size),
        .max_per_size_in(max_per_size_out),
        .write_en(write_en_parser | rand_write_en),
        .read_en(read_en),
        .dim_m(dim_m),
        .dim_n(dim_n),
        .data_in(ms_data_in),
        .matrix_id_in(matrix_id_in),
        .result_data(result_data),
        .op_done(op_done),
        .result_m(result_m),
        .result_n(result_n),
        .start_input(start_input),
        .start_disp(start_disp),
        .load_operands(load_operands),
        .operand_a_id(operand_a_id),
        .operand_b_id(operand_b_id),
        .req_list_info(req_list_info),
        .data_out(ms_data_out),
        .matrix_id_out(matrix_id_out),
        .meta_info_valid(meta_info_valid),
        .matrix_data_valid(matrix_data_valid_fmt),
        .error_flag(error_flag_storage),
        .matrix_a_flat(matrix_a_flat),
        .matrix_b_flat(matrix_b_flat),
        .matrix_a_m(matrix_a_m),
        .matrix_a_n(matrix_a_n),
        .matrix_b_m(matrix_b_m),
        .matrix_b_n(matrix_b_n),
        .list_m_flat(list_m_flat),
        .list_n_flat(list_n_flat),
        .list_valid_flat(list_valid_flat)
    );

    // ==========================================================================
    // 实例化 operand_selector
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
    // 实例化 display_formatter
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
    // 实例化 mat_ops
    // ==========================================================================
    mat_ops u_mat_ops (
        .clk(clk),
        .rst_n(rst_n_synced),
        .start_op(start_op),
        .op_sel(op_sel),
        .matrix_a_flat(matrix_a_flat),
        .matrix_b_flat(matrix_b_flat),
        .dim_a_m(matrix_a_m),
        .dim_a_n(matrix_a_n),
        .dim_b_m(matrix_b_m),
        .dim_b_n(matrix_b_n),
        .scalar_k(scalar_k_cfg),
        .op_done(op_done),
        .result_data(result_data),
        .result_m(result_m),
        .result_n(result_n),
        .busy_flag(busy_flag_ops),
        .error_flag(error_flag_ops)
    );

    // ==========================================================================
    // 实例化 seg_display
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
    // 实例化 led_status
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
    // 实例化 uart_tx
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
 * 使用说明
 * 
 * 1. 拨码开关 sw[7:0] 说明
 *    sw[5:0] 交给 ctrl_fsm 选择模式/运算/手动
 *    sw[7:6] 可保留或自定义扩展
 * 
 * 2. 标量K配置
 *    - 默认值 3
 *    - 可通过 UART 命令 CONFIG SCALAR <value>
 *    - 例如：CONFIG SCALAR -5
 *    - 合法范围 [-128, 127]
 * 
 * 3. 矩阵数据流方向
 *    - mat_ops 接收的 matrix_a[0:24] 与 matrix_b[0:24] 来自 storage
 *    - 显示/格式化读取 matrix_a[0]
 * 
 * 4. 其他配置来源
 *    - elem_min/elem_max 由 config_manager 通过 UART 配置
 *    - countdown_init 由 config_manager 通过 UART 配置
 *    - max_per_size 由 config_manager 通过 UART 配置
 *    - scalar_k 由 config_manager 通过 UART 配置
 ******************************************************************************/