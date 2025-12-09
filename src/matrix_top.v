module matrix_top (  
    // ========== 系统信号 ==========  
    input clk,                              // 系统时钟 (100MHz)  
    input rst_n,                            // 复位信号（低电平有效）  
    
    // ========== 输入设备 ==========  
    input [7:0] sw,                         // 8位拨码开关  
    input [4:0] key,                        // 5个按键（低电平有效）  
    input uart_rx,                          // UART接收引脚  
    
    // ========== 输出设备 ==========  
    output uart_tx,                         // UART发送引脚  
    output [2:0] led,                       // 3个LED指示灯  
    output [3:0] seg_sel,                   // 七段数码管片选  
    output [7:0] seg_data                   // 七段数码管段选  
);  

    // ==========================================================================  
    // 信号声明区域  
    // ==========================================================================  
    
    // ===== ctrl_fsm输出信号 =====  
    wire [1:0] mode_sel;                    // 模式选择 (00=输入,01=生成,10=显示,11=运算)  
    wire [2:0] op_sel;                      // 运算类型选择  
    wire [7:0] countdown_val;               // 倒计时值  
    wire start_input;                       // 启动输入模式  
    wire start_gen;                         // 启动生成模式  
    wire start_disp;                        // 启动显示模式  
    wire start_op;                          // 启动运算  
    wire tx_start;                          // 启动UART发送  
    wire start_select;                      // 启动运算数选择  
    wire start_format;                      // 启动显示格式化  
    wire manual_mode;                       // 手动/随机选择模式  
    wire [3:0] operand_a_id;                // 选中的运算数A的ID  
    wire [3:0] operand_b_id;                // 选中的运算数B的ID  
    wire [1:0] display_mode;                // 显示模式 (0=单矩阵,1=列表,2=结果)  
    
    // ===== 状态标志信号 =====  
    wire error_flag_ctrl;                   // 总错误标志  
    wire busy_flag_ctrl;                    // 总忙碌标志  
    wire done_flag_ctrl;                    // 总完成标志  
    wire select_done;                       // 运算数选择完成  
    wire select_error;                      // 运算数选择错误  
    wire format_done;                       // 显示格式化完成  

    // ===== UART接收和解析相关信号 =====  
    wire [7:0] rx_data;                     // UART接收到的字节  
    wire [2:0] dim_m;                       // 解析出的行数  
    wire [2:0] dim_n;                       // 解析出的列数  
    wire [7:0] elem_data;                   // 解析出的元素数据  
    wire [7:0] elem_min;                    // 元素最小值  
    wire [7:0] elem_max;                    // 元素最大值  
    wire [3:0] count;                       // 生成数量  
    wire [3:0] matrix_id_in;                // 输入的矩阵ID  
    wire [3:0] user_id_a;                   // 用户输入的矩阵A ID  
    wire [3:0] user_id_b;                   // 用户输入的矩阵B ID  
    wire rx_valid;                          // 接收数据有效  
    wire data_ready;                        // 解析完成标志  
    wire user_input_valid;                  // 用户输入完成标志  
    wire write_en_parser;                   // 解析器的写使能  
    wire read_en;                           // 读使能（暂未使用）  

    // ===== matrix_storage相关信号 =====  
    wire [7:0] ms_data_in;                  // 存储模块数据输入  
    wire [7:0] ms_data_out;                 // 存储模块数据输出  
    wire [3:0] matrix_id_out;               // 当前读取的矩阵ID  
    wire [7:0] matrix_a [0:24];             // 运算数A缓冲区  
    wire [7:0] matrix_b [0:24];             // 运算数B缓冲区  
    wire [2:0] matrix_a_m;                  // 运算数A行数  
    wire [2:0] matrix_a_n;                  // 运算数A列数  
    wire [2:0] matrix_b_m;                  // 运算数B行数  
    wire [2:0] matrix_b_n;                  // 运算数B列数  
    wire [2:0] list_m [0:9];                // 矩阵列表行数  
    wire [2:0] list_n [0:9];                // 矩阵列表列数  
    wire list_valid [0:9];                  // 矩阵列表有效标志  
    wire [7:0] result_data;                 // 运算结果数据  
    wire meta_info_valid;                   // 元信息有效标志  
    wire error_flag_storage;                // 存储模块错误标志  
    wire gen_done;                          // 生成完成标志  
    wire op_done;                           // 运算完成标志  
    wire busy_flag_ops;                     // 运算模块忙标志  
    wire error_flag_ops;                    // 运算模块错误标志  
    wire load_operands;                     // 加载运算数信号  
    wire req_list_info;                     // 请求列表信息信号  

    // ===== operand_selector相关信号 =====  
    wire [3:0] selected_a;                  // 选择器输出的矩阵A ID  
    wire [3:0] selected_b;                  // 选择器输出的矩阵B ID  
    
    // ===== display_formatter相关信号 =====  
    wire [7:0] tx_data_fmt;                 // 格式化器输出的待发送字节  
    wire tx_valid_fmt;                      // 格式化器发送有效标志  
    wire [7:0] matrix_data_to_fmt;          // 传给格式化器的矩阵数据  
    wire matrix_data_valid_fmt;             // 矩阵数据有效标志  
    
    // ===== rand_matrix_gen相关信号 =====  
    wire [7:0] rand_data_out;               // 随机生成器输出数据  
    wire rand_write_en_internal;            // 随机生成器写使能  
    
    // ===== 其他信号 =====  
    wire [7:0] scalar_k;                    // 标量K（来自开关）  
    assign scalar_k = sw;  
    
    wire tx_busy;                           // UART发送忙标志  
    
    // ==========================================================================  
    // 数据路由逻辑  
    // ==========================================================================  
    
    // ===== 数据输入选择：随机生成 vs 手动输入 =====  
    wire write_en;  
    assign ms_data_in = (start_gen) ? rand_data_out : elem_data;  
    assign write_en = (start_gen) ? rand_write_en_internal : (start_input && write_en_parser);  
    
    // ===== 错误标志汇总 =====  
    assign error_flag_ctrl = error_flag_ops | error_flag_storage | select_error;  
    
    // ===== 忙碌标志汇总 =====  
    assign busy_flag_ctrl = busy_flag_ops;  
    
    // ===== 完成标志汇总 =====  
    assign done_flag_ctrl = op_done | gen_done;  
    
    // ===== 运算数加载信号生成 =====  
    // 检测start_op上升沿，触发一次加载  
    reg load_operands_reg;  
    reg start_op_prev;  
    
    always @(posedge clk or negedge rst_n) begin  
        if (!rst_n) begin  
            load_operands_reg <= 1'b0;  
            start_op_prev <= 1'b0;  
        end else begin  
            start_op_prev <= start_op;  
            // 检测上升沿：从0到1的变化  
            load_operands