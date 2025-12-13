/******************************************************************************
 * 模块名称: matrix_top
 * 功能描述: 顶层封装
 *          - 连接控制路径与数据路径
 *          - 将scalar_k等配置从config_manager分发
 *          - 将存储的矩阵馈入 mat_ops 运算
 ******************************************************************************/
module matrix_top (
    input clk,          // 板载 100MHz 时钟
    input rst_n,        // 复位按键 (S6)
    input [7:0] sw,     // 8个拨码开关
    input [4:0] key,    // 5个按键 (S0-S4)
    input uart_rx,

    output uart_tx,
    output [2:0] led,
    output [3:0] seg_sel,
    output [7:0] seg_data
);

    // ==========================================================================
    // 0. 时钟降频 (关键救命稻草！)
    // ==========================================================================
    // 逻辑太复杂跑不到100MHz，我们降到50MHz，解决Timing Violation
    (* KEEP = "TRUE" *) reg clk_div;
    always @(posedge clk) begin
        clk_div <= ~clk_div; // 100MHz -> 50MHz
    end
    
    (* KEEP = "TRUE" *) wire sys_clk;
    BUFG u_clk_bufg (
        .I(clk_div),
        .O(sys_clk)
    );

    // ==========================================================================
    // 1. 复位信号同步
    // ==========================================================================
    reg rst_n_sync1, rst_n_sync2;
    wire rst_n_synced;
    
    always @(posedge sys_clk or negedge rst_n) begin
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
    // 2. 输入信号同步与消抖
    // ==========================================================================
    
    // --- 开关同步 ---
    reg [7:0] sw_r1, sw_r2;
    always @(posedge sys_clk) begin
        sw_r1 <= sw;
        sw_r2 <= sw_r1;
    end

    // --- 按键消抖 (适配50MHz时钟) ---
    // 50MHz下，20ms = 1,000,000 个周期
    localparam DEBOUNCE_CNT_MAX = 1000000; 
    reg [4:0] key_r1, key_r2;
    reg [4:0] key_stable;
    reg [4:0] key_pulse;
    reg [31:0] cnt_key [4:0];

    genvar i;
    generate
        for(i=0; i<5; i=i+1) begin : key_proc
            always @(posedge sys_clk) begin
                if (!rst_n_synced) begin
                    key_r1[i] <= 1'b0; key_r2[i] <= 1'b0;
                    key_stable[i] <= 1'b0; key_pulse[i] <= 1'b0;
                    cnt_key[i] <= 32'd0;
                end else begin
                    key_r1[i] <= key[i];
                    key_r2[i] <= key_r1[i];

                    if (key_r2[i] != key_stable[i]) begin
                        if (cnt_key[i] < DEBOUNCE_CNT_MAX) begin
                            cnt_key[i] <= cnt_key[i] + 1;
                        end else begin
                            key_stable[i] <= key_r2[i];
                            cnt_key[i] <= 0;
                            if (key_r2[i] == 1'b1) key_pulse[i] <= 1'b1;
                        end
                    end else begin
                        cnt_key[i] <= 0;
                        key_pulse[i] <= 1'b0;
                    end
                end
            end
        end
    endgenerate

    // ==========================================================================
    // 3. 重新映射按键功能 (修复：S3/V1是确认键)
    // ==========================================================================
    // V1在约束文件中是key[0]
    // 但用户说S3是确认键，所以key[0]应该映射为确认键（这个已经对了）
    // 如果还是不对，可能需要调整映射顺序
    
    wire btn_confirm = key_pulse[0];  // S2: 确认 / Start
    wire btn_back    = key_pulse[1];  // S4: 返回 / Back
    wire btn_next    = key_pulse[2];  // S3: 上一个 / A选择
    wire btn_prev    = key_pulse[3];  // S0: 下一个 / B选择
    wire btn_reset   = key_pulse[4];  // S1: 软复位 / 备用
    
    // 将重组后的按键打包送给 FSM
    // ctrl_fsm 内部逻辑: key[0]=Confirm, key[1]=Back, key[2]=SelA, key[3]=SelB
    wire [3:0] fsm_keys = {btn_prev, btn_next, btn_back, btn_confirm}; 

    // ==========================================================================
    // 内部连线 (保持原样，只是时钟换成 sys_clk)
    // ==========================================================================
    wire [1:0] mode_sel;
    wire [2:0] op_sel;
    wire [7:0] countdown_val;
    wire start_input, start_gen, start_disp, start_op, tx_start;
    wire start_select, start_format;
    wire manual_mode;
    wire [3:0] operand_a_id, operand_b_id;
    wire [1:0] display_mode;
    wire error_flag_ctrl, busy_flag_ctrl, done_flag_ctrl;
    wire select_done, select_error, format_done;
    wire [7:0] rx_data;
    wire rx_valid;
    wire [2:0] dim_m, dim_n;
    wire [7:0] elem_data;
    wire [3:0] count, matrix_id_in;
    wire [3:0] user_id_a, user_id_b;
    wire data_ready, user_input_valid;
    wire config_valid;
    wire [2:0] config_type;
    wire signed [7:0] config_value1, config_value2;
    wire signed [7:0] elem_min_cfg, elem_max_cfg, scalar_k_cfg;
    wire [7:0] countdown_init_cfg;
    wire query_max_per_size;
    wire [3:0] max_per_size_out;
    wire config_done, config_error;
    wire [7:0] ms_data_in, ms_data_out;
    wire [3:0] matrix_id_out;
    
    // 修复：GEN模式下，需要记录生成的matrix_id
    reg [3:0] gen_matrix_id;
    reg gen_matrix_id_valid;
    
    // 修复：记录matrix_storage写入时的matrix_id
    wire [3:0] write_matrix_id_out;
    
    // 修复：GEN模式下，使用记录的gen_matrix_id；INPUT模式下，使用uart_cmd_parser的matrix_id
    wire [3:0] matrix_id_in_sel = (mode_sel == 2'b10 && gen_matrix_id_valid) ? gen_matrix_id : matrix_id_in;
    wire [8*25-1:0] matrix_a_flat, matrix_b_flat;
    wire [2:0] matrix_a_m, matrix_a_n, matrix_b_m, matrix_b_n;
    wire [3*10-1:0] list_m_flat, list_n_flat;
    wire [10-1:0] list_valid_flat;
    wire [7:0] result_data;
    wire [2:0] result_m, result_n;
    wire meta_info_valid, error_flag_storage;
    wire load_operands, req_list_info;
    wire write_en_parser, rand_write_en, read_en;
    wire [3:0] selected_a, selected_b;
    wire [7:0] tx_data_fmt;
    wire tx_valid_fmt;
    wire [7:0] matrix_data_to_fmt;
    wire matrix_data_valid_fmt;
    wire tx_busy, fmt_data_req;
    wire [7:0] rand_data_out;
    wire gen_done;
    wire op_done, busy_flag_ops, error_flag_ops;

    assign ms_data_in = (start_gen) ? rand_data_out : elem_data;
    assign read_en = fmt_data_req;
    assign matrix_data_to_fmt = ms_data_out;
    
    assign error_flag_ctrl = error_flag_ops | error_flag_storage | select_error | config_error;
    assign busy_flag_ctrl  = busy_flag_ops;
    assign done_flag_ctrl  = op_done | gen_done | config_done;
    assign load_operands = start_op;
    assign req_list_info = (display_mode == 2'd1);

    // ==========================================================================
    // 模块实例化 (全部使用 sys_clk)
    // ==========================================================================
    
    config_manager u_config_manager (
        .clk(sys_clk), .rst_n(rst_n_synced),
        .config_valid(config_valid), .config_type(config_type),
        .config_value1(config_value1), .config_value2(config_value2),
        .elem_min(elem_min_cfg), .elem_max(elem_max_cfg),
        .countdown_init(countdown_init_cfg), .scalar_k(scalar_k_cfg),
        .query_max_per_size(query_max_per_size), .max_per_size_out(max_per_size_out),
        .config_done(config_done), .config_error(config_error)
    );
    
    ctrl_fsm u_ctrl_fsm (
        .clk(sys_clk), .rst_n(rst_n_synced),
        .sw(sw_r2[5:0]),
        .key(fsm_keys),       // 使用重新映射后的按键
        .error_flag(error_flag_ctrl), .busy_flag(busy_flag_ctrl), .done_flag(done_flag_ctrl),
        .select_done(select_done), .select_error(select_error),
        .selected_a(selected_a), .selected_b(selected_b),
        .format_done(format_done),
        .countdown_init_cfg(countdown_init_cfg),
        .mode_sel(mode_sel), .op_sel(op_sel), .countdown_val(countdown_val),
        .start_input(start_input), .start_gen(start_gen), .start_disp(start_disp),
        .start_op(start_op), .tx_start(tx_start), .start_select(start_select),
        .manual_mode(manual_mode), .operand_a_id(operand_a_id), .operand_b_id(operand_b_id),
        .display_mode(display_mode), .start_format(start_format)
    );

    uart_rx u_uart_rx (
        .clk(sys_clk), .rst_n(rst_n_synced),
        .rx(uart_rx), .rx_data(rx_data), .rx_valid(rx_valid)
    );

    uart_cmd_parser u_uart_cmd_parser (
        .clk(sys_clk), .rst_n(rst_n_synced),
        .rx_data(rx_data), .rx_valid(rx_valid),
        .mode_sel(mode_sel),
        .start_input(start_input), .start_gen(start_gen),
        .in_operand_select(start_select),
        .dim_m(dim_m), .dim_n(dim_n), .elem_data(elem_data),
        .count(count), .matrix_id(matrix_id_in),
        .write_en(write_en_parser), .data_ready(data_ready),
        .user_id_a(user_id_a), .user_id_b(user_id_b), .user_input_valid(user_input_valid),
        .config_valid(config_valid), .config_type(config_type),
        .config_value1(config_value1), .config_value2(config_value2)
    );

    rand_matrix_gen u_rand_matrix_gen (
        .clk(sys_clk), .rst_n(rst_n_synced),
        .start_gen(start_gen), .dim_m(dim_m), .dim_n(dim_n),
        .count(count), .elem_min_cfg(elem_min_cfg), .elem_max_cfg(elem_max_cfg),
        .gen_done(gen_done), .data_out(rand_data_out), .write_en(rand_write_en)
    );

    matrix_storage u_matrix_storage (
        .clk(sys_clk), .rst_n(rst_n_synced),
        .elem_min(elem_min_cfg), .elem_max(elem_max_cfg),
        .query_max_per_size(query_max_per_size), .max_per_size_in(max_per_size_out),
        .write_en(write_en_parser | rand_write_en), .read_en(read_en),
        .dim_m(dim_m), .dim_n(dim_n),
        .data_in(ms_data_in), .matrix_id_in(matrix_id_in_sel),  // 修复：使用matrix_id_in_sel
        .result_data(result_data), .op_done(op_done),
        .result_m(result_m), .result_n(result_n),
        .start_input(start_input), .start_gen(start_gen), .start_disp(start_disp),
        .load_operands(load_operands),
        .operand_a_id(operand_a_id), .operand_b_id(operand_b_id),
        .req_list_info(req_list_info),
        .data_out(ms_data_out), .matrix_id_out(matrix_id_out),
        .write_matrix_id_out(write_matrix_id_out),  // 修复：连接write_matrix_id_out
        .meta_info_valid(meta_info_valid), .matrix_data_valid(matrix_data_valid_fmt),
        .error_flag(error_flag_storage),
        .matrix_a_flat(matrix_a_flat), .matrix_b_flat(matrix_b_flat),
        .matrix_a_m(matrix_a_m), .matrix_a_n(matrix_a_n),
        .matrix_b_m(matrix_b_m), .matrix_b_n(matrix_b_n),
        .list_m_flat(list_m_flat), .list_n_flat(list_n_flat), .list_valid_flat(list_valid_flat)
    );

    operand_selector u_operand_selector (
        .clk(sys_clk), .rst_n(rst_n_synced),
        .start_select(start_select), .manual_mode(manual_mode), .op_type(op_sel),
        .user_id_a(user_id_a), .user_id_b(user_id_b), .user_input_valid(user_input_valid),
        .meta_m_flat(list_m_flat), .meta_n_flat(list_n_flat), .meta_valid_flat(list_valid_flat),
        .selected_a(selected_a), .selected_b(selected_b),
        .select_done(select_done), .select_error(select_error)
    );

    display_formatter u_display_formatter (
        .clk(sys_clk), .rst_n(rst_n_synced),
        .start_format(start_format), .display_mode(display_mode),
        .matrix_id(matrix_id_out), .dim_m(matrix_a_m), .dim_n(matrix_a_n),
        .matrix_data(matrix_data_to_fmt), .matrix_data_valid(matrix_data_valid_fmt),
        .list_m_flat(list_m_flat), .list_n_flat(list_n_flat), .list_valid_flat(list_valid_flat),
        .tx_data(tx_data_fmt), .tx_valid(tx_valid_fmt),
        .tx_busy(tx_busy), .data_req(fmt_data_req), .format_done(format_done)
    );

    mat_ops u_mat_ops (
        .clk(sys_clk), .rst_n(rst_n_synced),
        .start_op(start_op), .op_sel(op_sel),
        .matrix_a_flat(matrix_a_flat), .matrix_b_flat(matrix_b_flat),
        .dim_a_m(matrix_a_m), .dim_a_n(matrix_a_n),
        .dim_b_m(matrix_b_m), .dim_b_n(matrix_b_n),
        .scalar_k(scalar_k_cfg),
        .op_done(op_done), .result_data(result_data),
        .result_m(result_m), .result_n(result_n),
        .busy_flag(busy_flag_ops), .error_flag(error_flag_ops)
    );

    seg_display u_seg_display (
        .clk(sys_clk), .rst_n(rst_n_synced),
        .mode_sel(mode_sel), .op_sel(op_sel),
        .countdown_val(countdown_val), .matrix_id_out(matrix_id_out),
        .seg_sel(seg_sel), .seg_data(seg_data)
    );

    led_status u_led_status (
        .clk(sys_clk), .rst_n(rst_n_synced),
        .error_flag(error_flag_ctrl), .busy_flag(busy_flag_ctrl), .done_flag(done_flag_ctrl),
        .led(led)
    );

    // ==========================================================================
    // GEN模式matrix_id记录逻辑
    // ==========================================================================
    reg gen_done_prev;
    reg rand_write_en_prev;
    always @(posedge sys_clk) begin
        if (!rst_n_synced) begin
            gen_matrix_id <= 4'd0;
            gen_matrix_id_valid <= 1'b0;
            gen_done_prev <= 1'b0;
            rand_write_en_prev <= 1'b0;
        end else begin
            gen_done_prev <= gen_done;
            rand_write_en_prev <= rand_write_en;
            
            // 当GEN模式写入完成时（write_matrix_id_out更新），记录它
            if (mode_sel == 2'b10 && write_matrix_id_out != 4'd0) begin
                // 检测write_matrix_id_out的变化（写入完成）
                if (rand_write_en_prev && !rand_write_en) begin
                    gen_matrix_id <= write_matrix_id_out;
                    gen_matrix_id_valid <= 1'b1;
                end
            end
            // 当离开GEN模式时，清除标志
            if (mode_sel != 2'b10) begin
                gen_matrix_id_valid <= 1'b0;
            end
        end
    end
    
    // ==========================================================================
    // UART回显测试模式（用于调试）
    // ==========================================================================
    // 当sw[7]=1时，启用回显模式：uart_rx接收到的数据直接通过uart_tx回显
    wire echo_mode = sw_r2[7];
    reg [7:0] echo_data;
    reg echo_valid;
    reg echo_busy;
    
    always @(posedge sys_clk) begin
        if (!rst_n_synced) begin
            echo_valid <= 1'b0;
            echo_busy <= 1'b0;
        end else begin
            echo_valid <= 1'b0;
            if (echo_mode && rx_valid && !echo_busy) begin
                echo_data <= rx_data;
                echo_valid <= 1'b1;
                echo_busy <= 1'b1;
            end else if (echo_busy && !tx_busy) begin
                echo_busy <= 1'b0;
            end
        end
    end
    
    // UART TX：回显模式优先，否则使用display_formatter的数据
    wire [7:0] tx_data_sel = echo_mode ? echo_data : tx_data_fmt;
    wire tx_valid_sel = echo_mode ? echo_valid : tx_valid_fmt;
    
    uart_tx u_uart_tx (
        .clk(sys_clk), .rst_n(rst_n_synced),
        .tx_start(tx_valid_sel), .tx_data(tx_data_sel),
        .tx(uart_tx), .tx_busy(tx_busy)
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