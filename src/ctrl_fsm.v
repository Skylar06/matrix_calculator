module ctrl_fsm (
    input wire clk,                 // 系统时钟 100MHz
    input wire rst_n,               // 复位信号,低电平有效
    input wire [4:0] sw,            // 拨码开关 [4:2]=运算类型, [1:0]=模式选择
    input wire [3:0] key,           // 按键输入,低电平有效
    input wire error_flag,          // 错误标志
    input wire busy_flag,           // 忙碌标志
    input wire done_flag,           // 完成标志

    output reg [1:0] mode_sel,      // 模式选择输出
    output reg [2:0] op_sel,        // 运算类型输出
    output reg [7:0] countdown_val, // 倒计时值(用于错误恢复)
    output reg start_input,         // 启动输入模式
    output reg start_gen,           // 启动生成模式
    output reg start_disp,          // 启动显示模式
    output reg start_op,            // 启动运算模式
    output reg tx_start             // 启动UART发送
);

    // ========== 状态定义 ==========
    localparam S_IDLE           = 4'd0;   // 空闲状态
    localparam S_MENU           = 4'd1;   // 主菜单
    localparam S_INPUT          = 4'd2;   // 输入矩阵
    localparam S_GEN            = 4'd3;   // 生成矩阵
    localparam S_GEN_SHOW       = 4'd4;   // 生成后展示
    localparam S_DISPLAY        = 4'd5;   // 独立浏览模式
    localparam S_OP_SELECT      = 4'd6;   // 选择运算类型
    localparam S_OP_SHOW_LIST   = 4'd7;   // 显示可选矩阵列表
    localparam S_OP_OPERAND     = 4'd8;   // 选择运算数
    localparam S_OP_RUN         = 4'd9;   // 运算中
    localparam S_OP_RESULT      = 4'd10;  // 运算结果展示
    localparam S_ERROR          = 4'd11;  // 错误处理

    // ========== 状态寄存器 ==========
    reg [3:0] state, next_state;
    reg [3:0] prev_state;               // 记录前一个状态,用于检测状态变化

    // ========== 按键和开关信号定义 ==========
    // 按键信号(低电平有效,取反后变为正逻辑)
    wire key_ok = ~key[0];              // V1:  确认键
    wire key_back = ~key[1];            // R17: 返回键
    wire key_next = ~key[2];            // R11: 浏览/下一个键
    wire key_quick_menu = ~key[3];      // U4:  快速返回主菜单(可选)
    
    // 拨码开关信号
    wire [1:0] mode_sel_sw = sw[1:0];   // P5-P4: 主菜单模式选择
    wire [2:0] op_sel_sw = sw[4:2];     // M4-N4-R1: 运算类型选择

    // ========== 倒计时控制 ==========
    reg [7:0] countdown_cfg;            // 可配置的倒计时时间(5-15秒)
    reg [25:0] timer_cnt;               // 定时器计数器(用于1秒计时)
    localparam CLK_FREQ = 100_000_000;  // 100MHz时钟频率
    
    // ========== 显示控制 ==========
    reg show_done;                      // 展示完成标志
    
    // ========== 状态寄存器更新 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            prev_state <= S_IDLE;
        end else begin
            prev_state <= state;        // 保存前一个状态
            state <= next_state;        // 更新到下一个状态
        end
    end

    // ========== 状态转换组合逻辑 ==========
    always @(*) begin
        // 默认保持当前状态
        next_state = state;

        case (state)
            // ===== 初始状态 =====
            S_IDLE: begin
                next_state = S_MENU;    // 开机后自动进入主菜单
            end

            // ===== 主菜单 =====
            S_MENU: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (key_ok) begin
                    // 根据拨码开关选择工作模式
                    case (mode_sel_sw)
                        2'b00: next_state = S_INPUT;      // 00 = 输入矩阵
                        2'b01: next_state = S_GEN;        // 01 = 生成矩阵
                        2'b10: next_state = S_DISPLAY;    // 10 = 展示矩阵
                        2'b11: next_state = S_OP_SELECT;  // 11 = 矩阵运算
                        default: next_state = S_MENU;
                    endcase
                end
            end

            // ===== 输入模式 =====
            S_INPUT: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (key_back)
                    next_state = S_MENU;
                else if (key_ok)
                    next_state = S_INPUT;       // 继续输入新矩阵
            end

            // ===== 生成模式 =====
            S_GEN: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (done_flag)
                    next_state = S_GEN_SHOW;  // 生成完成后自动展示
                else if (key_back)
                    next_state = S_MENU;
            end

            S_GEN_SHOW: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (key_ok)
                    next_state = S_GEN;       // 继续生成新矩阵
                else if (key_back)
                    next_state = S_MENU;      // 返回主菜单
            end

            // ===== 展示模式 =====
            S_DISPLAY: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (key_next)
                    next_state = S_DISPLAY;   // 保持在DISPLAY,切换矩阵
                else if (key_back)
                    next_state = S_MENU;
            end

            // ===== 运算模式 =====
            S_OP_SELECT: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (key_back)
                    next_state = S_MENU;
                else if (key_ok)
                    next_state = S_OP_SHOW_LIST;  // 确认后显示矩阵列表
            end

            S_OP_SHOW_LIST: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (key_back)
                    next_state = S_OP_SELECT;     // 返回运算类型选择
                else if (show_done || key_ok)
                    next_state = S_OP_OPERAND;    // 进入运算数选择
            end

            S_OP_OPERAND: begin
                if (error_flag)
                    next_state = S_ERROR;         // 运算数不合法时进入错误处理
                else if (key_back)
                    next_state = S_OP_SELECT;
                else if (key_ok)
                    next_state = S_OP_RUN;        // 开始运算
            end

            S_OP_RUN: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (done_flag)
                    next_state = S_OP_RESULT;     // 运算完成后展示结果
            end

            S_OP_RESULT: begin
                if (key_ok)
                    next_state = S_OP_OPERAND;    // 继续当前运算类型
                else if (key_next)
                    next_state = S_OP_SELECT;     // 切换运算类型
                else if (key_back)
                    next_state = S_MENU;          // 返回主菜单
            end

            // ===== 错误处理 =====
            S_ERROR: begin
                // 倒计时结束或按返回键退出错误状态
                if (countdown_val == 0 || key_back)
                    next_state = S_OP_OPERAND;    // 返回运算数选择(让用户重新选)
            end

            default: next_state = S_IDLE;
        endcase
        
        // ===== 快速返回主菜单功能(可选) =====
        // 在任何状态下按U4键都返回主菜单
        if (key_quick_menu && state != S_IDLE && state != S_MENU) begin
            next_state = S_MENU;
        end
    end

    // ========== 输出控制时序逻辑 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // ===== 复位时初始化所有输出 =====
            mode_sel <= 2'b00;
            op_sel <= 3'b000;
            countdown_val <= 8'd0;
            countdown_cfg <= 8'd10;         // 默认10秒倒计时
            timer_cnt <= 26'd0;
            start_input <= 1'b0;
            start_gen <= 1'b0;
            start_disp <= 1'b0;
            start_op <= 1'b0;
            tx_start <= 1'b0;
            show_done <= 1'b0;
        end else begin
            // ===== 默认关闭所有脉冲信号 =====
            // 这些信号只需要高电平一个周期
            start_input <= 1'b0;
            start_gen <= 1'b0;
            start_disp <= 1'b0;
            start_op <= 1'b0;
            tx_start <= 1'b0;
            show_done <= 1'b0;

            // ===== 倒计时处理 =====
            if (state == S_ERROR && countdown_val > 0) begin
                if (timer_cnt >= CLK_FREQ - 1) begin
                    timer_cnt <= 26'd0;
                    countdown_val <= countdown_val - 1;  // 每秒减1
                end else begin
                    timer_cnt <= timer_cnt + 1;
                end
            end

            // ===== 根据当前状态设置输出 =====
            case (state)
                S_MENU: begin
                    mode_sel <= 2'b00;
                    countdown_val <= 8'd0;
                    timer_cnt <= 26'd0;
                end

                S_INPUT: begin
                    mode_sel <= 2'b01;
                    // 脉冲信号: 只在刚进入状态时产生一个周期的高电平
                    if (prev_state != S_INPUT)
                        start_input <= 1'b1;
                end

                S_GEN: begin
                    mode_sel <= 2'b10;
                    // 脉冲信号: 只在刚进入状态时启动生成
                    if (prev_state != S_GEN)
                        start_gen <= 1'b1;
                end

                S_GEN_SHOW: begin
                    mode_sel <= 2'b10;
                    // 持续信号: 调用display功能展示刚生成的矩阵
                    start_disp <= 1'b1;     // 告诉storage输出数据
                    tx_start <= 1'b1;       // 告诉uart_tx发送数据
                end

                S_DISPLAY: begin
                    mode_sel <= 2'b11;
                    // 持续信号: 独立浏览模式,需要持续读取和发送
                    start_disp <= 1'b1;
                    tx_start <= 1'b1;
                end

                S_OP_SELECT: begin
                    mode_sel <= 2'b11;
                    op_sel <= op_sel_sw;    // 从拨码开关读取运算类型
                end

                S_OP_SHOW_LIST: begin
                    mode_sel <= 2'b11;
                    // 脉冲信号: 调用display功能显示矩阵列表
                    if (prev_state != S_OP_SHOW_LIST) begin
                        start_disp <= 1'b1;
                        tx_start <= 1'b1;
                        show_done <= 1'b1;  // 简化处理: 立即标记完成
                    end
                end

                S_OP_OPERAND: begin
                    mode_sel <= 2'b11;
                    // 等待用户通过UART输入运算数编号
                end

                S_OP_RUN: begin
                    mode_sel <= 2'b11;
                    // 脉冲信号: 只在刚进入状态时启动运算
                    if (prev_state != S_OP_RUN)
                        start_op <= 1'b1;
                end

                S_OP_RESULT: begin
                    mode_sel <= 2'b11;
                    // 持续信号: 调用display功能展示运算结果
                    start_disp <= 1'b1;     // 告诉storage输出结果
                    tx_start <= 1'b1;       // 告诉uart_tx发送结果
                end

                S_ERROR: begin
                    mode_sel <= 2'b00;
                    // 启动倒计时
                    if (prev_state != S_ERROR) begin
                        countdown_val <= countdown_cfg;
                        timer_cnt <= 26'd0;
                    end
                end

                default: ;
            endcase
        end
    end

endmodule

// ============================================================================
// 使用说明:
// 1. 拨码开关 sw[1:0]: 主菜单模式选择
//    - 00: INPUT (输入矩阵)
//    - 01: GEN (生成矩阵)
//    - 10: DISPLAY (展示矩阵)
//    - 11: OPERATION (矩阵运算)
//
// 2. 拨码开关 sw[4:2]: 运算类型选择
//    - 000: T (转置)
//    - 001: A (加法)
//    - 010: b (标量乘)
//    - 011: C (矩阵乘)
//    - 100: J (卷积)
//
// 3. 按键功能:
//    - key[0] (V1):  确认键
//    - key[1] (R17): 返回键
//    - key[2] (R11): 浏览/下一个键
//    - key[3] (U4):  快速返回主菜单
//
// 4. 输出信号:
//    - start_input: 脉冲信号,进入INPUT状态时产生
//    - start_gen:   脉冲信号,进入GEN状态时产生
//    - start_disp:  持续信号,在展示状态期间保持高电平
//    - start_op:    脉冲信号,进入OP_RUN状态时产生
//    - tx_start:    持续信号,需要UART发送时保持高电平
//
// 5. 错误处理:
//    - 遇到error_flag时进入S_ERROR状态
//    - 开始倒计时(默认10秒)
//    - 倒计时结束或按返回键退出
// ============================================================================