module ctrl_fsm (
    input clk,
    input rst_n,
    input [3:0] sw,        
    input [3:0] key,       
    input error_flag,
    input busy_flag,
    input done_flag,

    output reg [1:0] mode_sel,
    output reg [2:0] op_sel,
    output reg [7:0] countdown_val,
    output reg start_input,
    output reg start_gen,
    output reg start_disp,     // 修复: tart_disp -> start_disp
    output reg start_op,
    output reg tx_start
);

    // ========== 状态定义 ==========
    localparam S_IDLE        = 4'd0;
    localparam S_MENU        = 4'd1;
    localparam S_INPUT       = 4'd2;
    localparam S_GEN         = 4'd3;
    localparam S_DISPLAY     = 4'd4;
    localparam S_OP_SELECT   = 4'd5;
    localparam S_OP_OPERAND  = 4'd6;
    localparam S_OP_RUN      = 4'd7;
    localparam S_OP_RESULT   = 4'd8;
    localparam S_ERROR       = 4'd9;

    reg [3:0] state, next_state;

    // ========== 按键和开关信号定义 ==========
    wire key_ok = ~key[0];          // 确认键(低电平有效)
    wire key_back = ~key[1];        // 返回键(低电平有效)
    wire [1:0] mode_sel_sw = sw[1:0];  // 主菜单模式选择
    wire [2:0] op_sel_sw = sw[4:2];    // 运算类型选择(3位)

    // ========== 倒计时控制 ==========
    reg [7:0] countdown_cfg;        // 可配置的倒计时时间(5-15秒)
    reg [25:0] timer_cnt;           // 定时器计数器
    localparam CLK_FREQ = 100_000_000;  // 100MHz
    
    // ========== 状态寄存器 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    // ========== 状态转换逻辑 ==========
    always @(*) begin
        next_state = state;

        case (state)
            S_IDLE: begin
                next_state = S_MENU;
            end

            S_MENU: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (key_ok) begin
                    case (mode_sel_sw)
                        2'b00: next_state = S_INPUT;      // 输入矩阵
                        2'b01: next_state = S_GEN;        // 生成矩阵
                        2'b10: next_state = S_DISPLAY;    // 展示矩阵
                        2'b11: next_state = S_OP_SELECT;  // 矩阵运算
                        default: next_state = S_MENU;
                    endcase
                end
            end

            S_INPUT: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (key_back)
                    next_state = S_MENU;
            end

            S_GEN: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (done_flag || key_back)
                    next_state = S_MENU;
            end

            S_DISPLAY: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (key_back)
                    next_state = S_MENU;
            end

            S_OP_SELECT: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (key_back)
                    next_state = S_MENU;
                else if (key_ok)
                    next_state = S_OP_OPERAND;
            end

            S_OP_OPERAND: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (key_back)
                    next_state = S_MENU;
                else if (key_ok)
                    next_state = S_OP_RUN;
            end

            S_OP_RUN: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (done_flag)
                    next_state = S_OP_RESULT;
            end

            S_OP_RESULT: begin
                if (key_ok || key_back)
                    next_state = S_MENU;
            end

            S_ERROR: begin
                // 倒计时结束或按返回键退出错误状态
                if (countdown_val == 0 || key_back)
                    next_state = S_MENU;
            end

            default: next_state = S_IDLE;
        endcase
    end

    // ========== 输出控制逻辑 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mode_sel <= 2'b00;
            op_sel <= 3'b000;
            countdown_val <= 8'd0;
            countdown_cfg <= 8'd10;     // 默认10秒倒计时
            timer_cnt <= 26'd0;
            start_input <= 1'b0;
            start_gen <= 1'b0;
            start_disp <= 1'b0;
            start_op <= 1'b0;
            tx_start <= 1'b0;
        end else begin
            // 默认关闭所有启动信号(脉冲信号)
            start_input <= 1'b0;
            start_gen <= 1'b0;
            start_disp <= 1'b0;
            start_op <= 1'b0;
            tx_start <= 1'b0;

            // ========== 倒计时处理 ==========
            if (state == S_ERROR && countdown_val > 0) begin
                if (timer_cnt >= CLK_FREQ - 1) begin
                    timer_cnt <= 26'd0;
                    countdown_val <= countdown_val - 1;
                end else begin
                    timer_cnt <= timer_cnt + 1;
                end
            end

            // ========== 根据状态设置输出 ==========
            case (next_state)
                S_MENU: begin
                    mode_sel <= 2'b00;
                    countdown_val <= 8'd0;
                    timer_cnt <= 26'd0;
                end

                S_INPUT: begin
                    mode_sel <= 2'b01;
                    start_input <= 1'b1;
                end

                S_GEN: begin
                    mode_sel <= 2'b10;
                    start_gen <= 1'b1;
                end

                S_DISPLAY: begin
                    mode_sel <= 2'b11;
                    start_disp <= 1'b1;
                    tx_start <= 1'b1;  // 同时启动UART发送
                end

                S_OP_SELECT: begin
                    mode_sel <= 2'b11;
                    op_sel <= op_sel_sw;  // 从开关读取运算类型
                end

                S_OP_OPERAND: begin
                    // 保持在运算模式,等待用户选择运算数
                end

                S_OP_RUN: begin
                    start_op <= 1'b1;
                end

                S_OP_RESULT: begin
                    tx_start <= 1'b1;  // 发送运算结果
                end

                S_ERROR: begin
                    mode_sel <= 2'b00;
                    // 启动倒计时
                    if (state != S_ERROR) begin
                        countdown_val <= countdown_cfg;
                        timer_cnt <= 26'd0;
                    end
                end

                default: ;
            endcase
        end
    end

endmodule