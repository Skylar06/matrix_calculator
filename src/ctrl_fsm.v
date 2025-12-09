module ctrl_fsm (
    input wire clk,
    input wire rst_n,
    input wire [5:0] sw,                // sw[7:5]=保留, sw[4:2]=运算类型, sw[1:0]=模式, sw[5]=手动(1)/随机(0)
    input wire [3:0] key,
    input wire error_flag,
    input wire busy_flag,
    input wire done_flag,
    
    // 新增：运算数选择相关
    input wire select_done,
    input wire select_error,
    input wire [3:0] selected_a,
    input wire [3:0] selected_b,
    
    // 新增：显示格式化相关
    input wire format_done,

    output reg [1:0] mode_sel,
    output reg [2:0] op_sel,
    output reg [7:0] countdown_val,
    output reg start_input,
    output reg start_gen,
    output reg start_disp,
    output reg start_op,
    output reg tx_start,
    
    // 新增：运算数选择控制
    output reg start_select,
    output reg manual_mode,
    output reg [3:0] operand_a_id,
    output reg [3:0] operand_b_id,
    
    // 新增：显示控制
    output reg [1:0] display_mode,      // 0=单矩阵, 1=列表, 2=结果
    output reg start_format
);

    // ========== 状态定义 ==========
    localparam S_IDLE           = 4'd0;
    localparam S_MENU           = 4'd1;
    localparam S_INPUT          = 4'd2;
    localparam S_GEN            = 4'd3;
    localparam S_GEN_SHOW       = 4'd4;
    localparam S_DISPLAY        = 4'd5;
    localparam S_OP_SELECT      = 4'd6;
    localparam S_OP_SHOW_LIST   = 4'd7;
    localparam S_OP_OPERAND     = 4'd8;
    localparam S_OP_RUN         = 4'd9;
    localparam S_OP_RESULT      = 4'd10;
    localparam S_ERROR          = 4'd11;

    reg [3:0] state, next_state;
    reg [3:0] prev_state;

    // ========== 按键和开关信号 ==========
    wire key_ok = ~key[0];
    wire key_back = ~key[1];
    wire key_next = ~key[2];
    wire key_quick_menu = ~key[3];
    
    wire [1:0] mode_sel_sw = sw[1:0];
    wire [2:0] op_sel_sw = sw[4:2];
    wire manual_select_mode = sw[5];

    // ========== 倒计时控制 ==========
    reg [7:0] countdown_cfg;
    reg [25:0] timer_cnt;
    localparam CLK_FREQ = 100_000_000;
    
    reg show_done;
    
    // ========== 状态寄存器更新 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            prev_state <= S_IDLE;
        end else begin
            prev_state <= state;
            state <= next_state;
        end
    end

    // ========== 状态转换组合逻辑 ==========
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
                        2'b00: next_state = S_INPUT;
                        2'b01: next_state = S_GEN;
                        2'b10: next_state = S_DISPLAY;
                        2'b11: next_state = S_OP_SELECT;
                        default: next_state = S_MENU;
                    endcase
                end
            end

            S_INPUT: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (key_back)
                    next_state = S_MENU;
                else if (key_ok)
                    next_state = S_INPUT;
            end

            S_GEN: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (done_flag)
                    next_state = S_GEN_SHOW;
                else if (key_back)
                    next_state = S_MENU;
            end

            S_GEN_SHOW: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (format_done && key_ok)
                    next_state = S_GEN;
                else if (key_back)
                    next_state = S_MENU;
            end

            S_DISPLAY: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (key_next)
                    next_state = S_DISPLAY;
                else if (key_back)
                    next_state = S_MENU;
            end

            S_OP_SELECT: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (key_back)
                    next_state = S_MENU;
                else if (key_ok)
                    next_state = S_OP_SHOW_LIST;
            end

            S_OP_SHOW_LIST: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (key_back)
                    next_state = S_OP_SELECT;
                else if (format_done || key_ok)
                    next_state = S_OP_OPERAND;
            end

            S_OP_OPERAND: begin
                if (error_flag || select_error)
                    next_state = S_ERROR;
                else if (key_back)
                    next_state = S_OP_SELECT;
                else if (select_done && key_ok)
                    next_state = S_OP_RUN;
            end

            S_OP_RUN: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (done_flag)
                    next_state = S_OP_RESULT;
            end

            S_OP_RESULT: begin
                if (format_done && key_ok)
                    next_state = S_OP_OPERAND;
                else if (key_next)
                    next_state = S_OP_SELECT;
                else if (key_back)
                    next_state = S_MENU;
            end

            S_ERROR: begin
                if (countdown_val == 0 || key_back)
                    next_state = S_OP_OPERAND;
            end

            default: next_state = S_IDLE;
        endcase
        
        if (key_quick_menu && state != S_IDLE && state != S_MENU) begin
            next_state = S_MENU;
        end
    end

    // ========== 输出控制时序逻辑 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mode_sel <= 2'b00;
            op_sel <= 3'b000;
            countdown_val <= 8'd0;
            countdown_cfg <= 8'd10;
            timer_cnt <= 26'd0;
            start_input <= 1'b0;
            start_gen <= 1'b0;
            start_disp <= 1'b0;
            start_op <= 1'b0;
            tx_start <= 1'b0;
            show_done <= 1'b0;
            start_select <= 1'b0;
            manual_mode <= 1'b0;
            operand_a_id <= 4'd0;
            operand_b_id <= 4'd0;
            display_mode <= 2'd0;
            start_format <= 1'b0;
        end else begin
            // 默认关闭所有脉冲信号
            start_input <= 1'b0;
            start_gen <= 1'b0;
            start_disp <= 1'b0;
            start_op <= 1'b0;
            tx_start <= 1'b0;
            show_done <= 1'b0;
            start_select <= 1'b0;
            start_format <= 1'b0;

            // 倒计时处理
            if (state == S_ERROR && countdown_val > 0) begin
                if (timer_cnt >= CLK_FREQ - 1) begin
                    timer_cnt <= 26'd0;
                    countdown_val <= countdown_val - 1;
                end else begin
                    timer_cnt <= timer_cnt + 1;
                end
            end

            case (state)
                S_MENU: begin
                    mode_sel <= 2'b00;
                    countdown_val <= 8'd0;
                    timer_cnt <= 26'd0;
                end

                S_INPUT: begin
                    mode_sel <= 2'b01;
                    if (prev_state != S_INPUT)
                        start_input <= 1'b1;
                end

                S_GEN: begin
                    mode_sel <= 2'b10;
                    if (prev_state != S_GEN)
                        start_gen <= 1'b1;
                end

                S_GEN_SHOW: begin
                    mode_sel <= 2'b10;
                    if (prev_state != S_GEN_SHOW) begin
                        display_mode <= 2'd0;      // 单矩阵显示
                        start_format <= 1'b1;
                    end
                end

                S_DISPLAY: begin
                    mode_sel <= 2'b11;
                    if (prev_state != S_DISPLAY || key_next) begin
                        display_mode <= 2'd0;
                        start_format <= 1'b1;
                    end
                end

                S_OP_SELECT: begin
                    mode_sel <= 2'b11;
                    op_sel <= op_sel_sw;
                end

                S_OP_SHOW_LIST: begin
                    mode_sel <= 2'b11;
                    if (prev_state != S_OP_SHOW_LIST) begin
                        display_mode <= 2'd1;      // 列表显示
                        start_format <= 1'b1;
                    end
                end

                S_OP_OPERAND: begin
                    mode_sel <= 2'b11;
                    manual_mode <= manual_select_mode;
                    
                    if (prev_state != S_OP_OPERAND) begin
                        start_select <= 1'b1;
                    end
                    
                    if (select_done) begin
                        operand_a_id <= selected_a;
                        operand_b_id <= selected_b;
                    end
                end

                S_OP_RUN: begin
                    mode_sel <= 2'b11;
                    if (prev_state != S_OP_RUN)
                        start_op <= 1'b1;
                end

                S_OP_RESULT: begin
                    mode_sel <= 2'b11;
                    if (prev_state != S_OP_RESULT) begin
                        display_mode <= 2'd2;      // 结果显示
                        start_format <= 1'b1;
                    end
                end

                S_ERROR: begin
                    mode_sel <= 2'b00;
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