/******************************************************************************
 * 模块名称: uart_cmd_parser
 * 功能描述: UART命令解析器
 *          - 解析矩阵输入/生成/运算数选择命令
 *          - 【新增】解析CONFIG SCALAR命令
 ******************************************************************************/
module uart_cmd_parser (
    input wire clk,
    input wire rst_n,
    input wire [7:0] rx_data,
    input wire rx_valid,
    input wire [1:0] mode_sel,
    input wire start_input,
    input wire start_gen,
    input wire in_operand_select,
    
    // ========== 矩阵输入/生成输出 ==========
    output reg [2:0] dim_m,
    output reg [2:0] dim_n,
    output reg [7:0] elem_data,
    output reg [7:0] elem_min,
    output reg [7:0] elem_max,
    output reg [3:0] count,
    output reg [3:0] matrix_id,
    output reg write_en,
    output reg data_ready,
    
    // ========== 运算数选择输出 ==========
    output reg [3:0] user_id_a,
    output reg [3:0] user_id_b,
    output reg user_input_valid,
    
    // ========== CONFIG命令输出 ==========
    output reg config_valid,
    output reg [2:0] config_type,
    output reg signed [7:0] config_value1,
    output reg signed [7:0] config_value2
);

    // ==========================================================================
    // 状态机定义
    // ==========================================================================
    localparam IDLE         = 4'd0;
    localparam WAIT_M       = 4'd1;
    localparam WAIT_N       = 4'd2;
    localparam WAIT_DATA    = 4'd3;
    localparam WAIT_ID_A    = 4'd4;
    localparam WAIT_ID_B    = 4'd5;
    localparam DONE         = 4'd6;
    localparam CONFIG_CMD   = 4'd7;
    localparam CONFIG_VAL1  = 4'd8;
    localparam CONFIG_VAL2  = 4'd9;

    reg [3:0] state, next_state;
    
    reg [4:0] data_cnt;
    reg [4:0] data_total;
    reg [7:0] num_buffer;
    reg num_building;
    reg is_negative;
    
    // ==========================================================================
    // ASCII码定义
    // ==========================================================================
    localparam ASCII_SPACE = 8'd32;
    localparam ASCII_0 = 8'd48;
    localparam ASCII_9 = 8'd57;
    localparam ASCII_MINUS = 8'd45;   // '-'
    localparam ASCII_CR = 8'd13;
    localparam ASCII_LF = 8'd10;
    
    // CONFIG命令关键字符
    localparam ASCII_C = 8'd67;
    localparam ASCII_O = 8'd79;
    localparam ASCII_N = 8'd78;
    localparam ASCII_F = 8'd70;
    localparam ASCII_I = 8'd73;
    localparam ASCII_G = 8'd71;
    localparam ASCII_M = 8'd77;
    localparam ASCII_A = 8'd65;
    localparam ASCII_X = 8'd88;
    localparam ASCII_R = 8'd82;
    localparam ASCII_E = 8'd69;
    localparam ASCII_T = 8'd84;
    localparam ASCII_U = 8'd85;
    localparam ASCII_S = 8'd83;       // 【新增】'S' for SCALAR
    localparam ASCII_L = 8'd76;       // 【新增】'L' for SCALAR
    
    // 命令识别缓冲区
    reg [47:0] cmd_buffer;            // 存储 "CONFIG" (6字符)
    reg [47:0] sub_buffer;            // 存储子命令 "MAX" / "RANGE" / "COUNT" / "SCALAR"
    
    reg cmd_detected;                 // 命令检测标志
    reg [2:0] detected_type;          // 检测到的命令类型

    // ==========================================================================
    // 状态转换逻辑
    // ==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        next_state = state;
        
        case (state)
            IDLE: begin
                if (cmd_detected)
                    next_state = CONFIG_VAL1;
                else if (in_operand_select)
                    next_state = WAIT_ID_A;
                else if (start_input || start_gen)
                    next_state = WAIT_M;
                // 修复：如果已经在INPUT或GEN模式且收到数字，自动进入WAIT_M（处理start_input/start_gen脉冲已过的情况）
                // 关键修复：只要在INPUT或GEN模式，且收到数字字符，就进入WAIT_M状态
                else if ((mode_sel == 2'b01 || mode_sel == 2'b10) && rx_valid && rx_data >= 8'h30 && rx_data <= 8'h39)
                    next_state = WAIT_M;
            end
            
            WAIT_M: begin
                // 修复：如果收到数字，继续在WAIT_M状态解析M值
                // 如果收到空格/换行，进入WAIT_N
                if (rx_valid && (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF))
                    next_state = WAIT_N;
                // 如果收到数字，保持在WAIT_M状态（数据解析在always块中处理）
            end
            
            WAIT_N: begin
                if (rx_valid && (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF)) begin
                    case (mode_sel)
                        2'b01, 2'b10: next_state = WAIT_DATA;
                        default: next_state = DONE;
                    endcase
                end
            end
            
            WAIT_DATA: begin
                case (mode_sel)
                    2'b01: begin
                        if (data_cnt >= data_total)
                            next_state = DONE;
                    end
                    2'b10: begin
                        if (data_cnt >= 1)
                            next_state = DONE;
                    end
                    default: next_state = DONE;
                endcase
            end
            
            WAIT_ID_A: begin
                if (rx_valid && (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF))
                    next_state = WAIT_ID_B;
            end
            
            WAIT_ID_B: begin
                if (rx_valid && (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF))
                    next_state = DONE;
            end
            
            CONFIG_VAL1: begin
                if (rx_valid && (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF)) begin
                    // 如果是RANGE命令，需要第二个值
                    if (detected_type == 3'd1)
                        next_state = CONFIG_VAL2;
                    else
                        next_state = DONE;
                end
            end
            
            CONFIG_VAL2: begin
                if (rx_valid && (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF))
                    next_state = DONE;
            end
            
            DONE: begin
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end

    // ==========================================================================
    // 输出逻辑
    // ==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dim_m <= 3'd0;
            dim_n <= 3'd0;
            elem_data <= 8'd0;
            elem_min <= 8'd0;
            elem_max <= 8'd9;
            count <= 4'd0;
            matrix_id <= 4'd0;
            write_en <= 1'b0;
            data_ready <= 1'b0;
            data_cnt <= 5'd0;
            data_total <= 5'd0;
            num_buffer <= 8'd0;
            num_building <= 1'b0;
            is_negative <= 1'b0;
            user_id_a <= 4'd0;
            user_id_b <= 4'd0;
            user_input_valid <= 1'b0;
            
            config_valid <= 1'b0;
            config_type <= 3'd0;
            config_value1 <= 8'sd0;
            config_value2 <= 8'sd0;
            cmd_buffer <= 48'd0;
            sub_buffer <= 48'd0;
            cmd_detected <= 1'b0;
            detected_type <= 3'd0;
            
        end else begin
            // ===== 默认清除单周期信号 =====
            write_en <= 1'b0;
            data_ready <= 1'b0;
            user_input_valid <= 1'b0;
            config_valid <= 1'b0;
            cmd_detected <= 1'b0;
            
            // ===== 命令缓冲区滚动更新 =====
            if (rx_valid && state == IDLE) begin
                cmd_buffer <= {cmd_buffer[39:0], rx_data};
                sub_buffer <= {sub_buffer[39:0], rx_data};
                
                // ========== 检测 "CONFIG" 命令 ==========
                if (cmd_buffer[47:40] == ASCII_C &&
                    cmd_buffer[39:32] == ASCII_O &&
                    cmd_buffer[31:24] == ASCII_N &&
                    cmd_buffer[23:16] == ASCII_F &&
                    cmd_buffer[15:8]  == ASCII_I &&
                    rx_data == ASCII_G) begin
                    // 进入等待子命令状态
                    sub_buffer <= 48'd0;
                end
                
                // ========== 检测子命令 ==========
                // 前提：已识别到 "CONFIG "
                if (cmd_buffer[47:8] == {ASCII_C, ASCII_O, ASCII_N, ASCII_F, ASCII_I, ASCII_G, ASCII_SPACE, 8'd0}) begin
                    
                    // 检测 "MAX" (3字符)
                    if (sub_buffer[23:16] == ASCII_M &&
                        sub_buffer[15:8]  == ASCII_A &&
                        rx_data == ASCII_X) begin
                        detected_type <= 3'd0;  // CONFIG_MAX_PER_SIZE
                        cmd_detected <= 1'b1;
                    end
                    
                    // 检测 "RANGE" (5字符)
                    else if (sub_buffer[39:32] == ASCII_R &&
                             sub_buffer[31:24] == ASCII_A &&
                             sub_buffer[23:16] == ASCII_N &&
                             sub_buffer[15:8]  == ASCII_G &&
                             rx_data == ASCII_E) begin
                        detected_type <= 3'd1;  // CONFIG_ELEM_RANGE
                        cmd_detected <= 1'b1;
                    end
                    
                    // 检测 "COUNT" (5字符)
                    else if (sub_buffer[39:32] == ASCII_C &&
                             sub_buffer[31:24] == ASCII_O &&
                             sub_buffer[23:16] == ASCII_U &&
                             sub_buffer[15:8]  == ASCII_N &&
                             rx_data == ASCII_T) begin
                        detected_type <= 3'd2;  // CONFIG_COUNTDOWN
                        cmd_detected <= 1'b1;
                    end
                    
                    // 【新增】检测 "SCALAR" (6字符)
                    else if (sub_buffer[47:40] == ASCII_S &&
                             sub_buffer[39:32] == ASCII_C &&
                             sub_buffer[31:24] == ASCII_A &&
                             sub_buffer[23:16] == ASCII_L &&
                             sub_buffer[15:8]  == ASCII_A &&
                             rx_data == ASCII_R) begin
                        detected_type <= 3'd4;  // CONFIG_SCALAR
                        cmd_detected <= 1'b1;
                    end
                end
            end
            
            case (state)
                IDLE: begin
                    data_cnt <= 5'd0;
                    data_total <= 5'd0;
                    num_buffer <= 8'd0;
                    num_building <= 1'b0;
                    is_negative <= 1'b0;
                end
                
                WAIT_M: begin
                    if (rx_valid) begin
                        if (rx_data >= ASCII_0 && rx_data <= ASCII_9) begin
                            if (num_building) begin
                                num_buffer <= num_buffer * 10 + (rx_data - ASCII_0);
                            end else begin
                                num_buffer <= rx_data - ASCII_0;
                                num_building <= 1'b1;
                            end
                        end
                        else if (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF) begin
                            dim_m <= num_buffer[2:0];
                            num_buffer <= 8'd0;
                            num_building <= 1'b0;
                        end
                    end
                end
                
                WAIT_N: begin
                    if (rx_valid) begin
                        if (rx_data >= ASCII_0 && rx_data <= ASCII_9) begin
                            if (num_building) begin
                                num_buffer <= num_buffer * 10 + (rx_data - ASCII_0);
                            end else begin
                                num_buffer <= rx_data - ASCII_0;
                                num_building <= 1'b1;
                            end
                        end
                        else if (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF) begin
                            dim_n <= num_buffer[2:0];
                            data_total <= dim_m * num_buffer[2:0];
                            num_buffer <= 8'd0;
                            num_building <= 1'b0;
                        end
                    end
                end
                
                WAIT_DATA: begin
                    if (rx_valid) begin
                        if (rx_data >= ASCII_0 && rx_data <= ASCII_9) begin
                            if (num_building) begin
                                num_buffer <= num_buffer * 10 + (rx_data - ASCII_0);
                            end else begin
                                num_buffer <= rx_data - ASCII_0;
                                num_building <= 1'b1;
                            end
                        end
                        else if (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF) begin
                            case (mode_sel)
                                2'b01: begin
                                    if (data_cnt < data_total) begin
                                        elem_data <= num_buffer;
                                        write_en <= 1'b1;
                                        data_cnt <= data_cnt + 1;
                                    end
                                end
                                2'b10: begin
                                    count <= num_buffer[3:0];
                                    data_cnt <= data_cnt + 1;
                                end
                                default: ;
                            endcase
                            
                            num_buffer <= 8'd0;
                            num_building <= 1'b0;
                        end
                    end
                end
                
                WAIT_ID_A: begin
                    if (rx_valid) begin
                        if (rx_data >= ASCII_0 && rx_data <= ASCII_9) begin
                            if (num_building) begin
                                num_buffer <= num_buffer * 10 + (rx_data - ASCII_0);
                            end else begin
                                num_buffer <= rx_data - ASCII_0;
                                num_building <= 1'b1;
                            end
                        end
                        else if (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF) begin
                            user_id_a <= num_buffer[3:0];
                            num_buffer <= 8'd0;
                            num_building <= 1'b0;
                        end
                    end
                end
                
                WAIT_ID_B: begin
                    if (rx_valid) begin
                        if (rx_data >= ASCII_0 && rx_data <= ASCII_9) begin
                            if (num_building) begin
                                num_buffer <= num_buffer * 10 + (rx_data - ASCII_0);
                            end else begin
                                num_buffer <= rx_data - ASCII_0;
                                num_building <= 1'b1;
                            end
                        end
                        else if (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF) begin
                            user_id_b <= num_buffer[3:0];
                            user_input_valid <= 1'b1;
                            num_buffer <= 8'd0;
                            num_building <= 1'b0;
                        end
                    end
                end
                
                // ========== CONFIG值解析（支持负数）==========
                CONFIG_VAL1: begin
                    if (rx_valid) begin
                        // 检测负号
                        if (rx_data == ASCII_MINUS && !num_building) begin
                            is_negative <= 1'b1;
                        end
                        // 数字累加
                        else if (rx_data >= ASCII_0 && rx_data <= ASCII_9) begin
                            if (num_building) begin
                                num_buffer <= num_buffer * 10 + (rx_data - ASCII_0);
                            end else begin
                                num_buffer <= rx_data - ASCII_0;
                                num_building <= 1'b1;
                            end
                        end
                        // 分隔符：保存值
                        else if (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF) begin
                            if (is_negative)
                                config_value1 <= -$signed(num_buffer);
                            else
                                config_value1 <= $signed(num_buffer);
                            
                            config_type <= detected_type;
                            num_buffer <= 8'd0;
                            num_building <= 1'b0;
                            is_negative <= 1'b0;
                            
                            // 如果不是RANGE命令，立即发送
                            if (detected_type != 3'd1) begin
                                config_valid <= 1'b1;
                            end
                        end
                    end
                end
                
                CONFIG_VAL2: begin
                    if (rx_valid) begin
                        if (rx_data == ASCII_MINUS && !num_building) begin
                            is_negative <= 1'b1;
                        end
                        else if (rx_data >= ASCII_0 && rx_data <= ASCII_9) begin
                            if (num_building) begin
                                num_buffer <= num_buffer * 10 + (rx_data - ASCII_0);
                            end else begin
                                num_buffer <= rx_data - ASCII_0;
                                num_building <= 1'b1;
                            end
                        end
                        else if (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF) begin
                            if (is_negative)
                                config_value2 <= -$signed(num_buffer);
                            else
                                config_value2 <= $signed(num_buffer);
                            
                            config_valid <= 1'b1;
                            num_buffer <= 8'd0;
                            num_building <= 1'b0;
                            is_negative <= 1'b0;
                        end
                    end
                end
                
                DONE: begin
                    data_ready <= 1'b1;
                end
                
                default: ;
            endcase
        end
    end

endmodule

/******************************************************************************
 * UART命令使用示例
 * 
 * 1. 矩阵输入：
 *    3 3 1 2 3 4 5 6 7 8 9
 * 
 * 2. 随机生成：
 *    3 3 5
 * 
 * 3. 运算数选择：
 *    2 3
 * 
 * 4. CONFIG命令：
 *    CONFIG MAX 5
 *    CONFIG RANGE -3 20
 *    CONFIG COUNT 15
 *    CONFIG SCALAR 7       【新增】
 *    CONFIG SCALAR -5      【新增】支持负数
 *    CONFIG SHOW
 ******************************************************************************/