/******************************************************************************
 * 模块名称: uart_cmd_parser
 * 功能描述: UART命令解析器
 *          - 解析矩阵输入命令
 *          - 解析生成命令
 *          - 解析运算数选择命令
 *          - 【新增】解析CONFIG配置命令
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
    
    // ========== 【新增】CONFIG命令输出 ==========
    output reg config_valid,                // 配置命令有效标志
    output reg [2:0] config_type,           // 配置类型
    output reg signed [7:0] config_value1,  // 配置值1
    output reg signed [7:0] config_value2   // 配置值2
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
    localparam CONFIG_CMD   = 4'd7;   // 【新增】CONFIG命令状态
    localparam CONFIG_VAL1  = 4'd8;   // 【新增】等待配置值1
    localparam CONFIG_VAL2  = 4'd9;   // 【新增】等待配置值2

    reg [3:0] state, next_state;
    
    reg [4:0] data_cnt;
    reg [4:0] data_total;
    reg [7:0] num_buffer;
    reg num_building;
    reg is_negative;              // 【新增】负数标志
    
    // ==========================================================================
    // ASCII码定义
    // ==========================================================================
    localparam ASCII_SPACE = 8'd32;
    localparam ASCII_0 = 8'd48;
    localparam ASCII_9 = 8'd57;
    localparam ASCII_MINUS = 8'd45;   // '-'
    localparam ASCII_CR = 8'd13;
    localparam ASCII_LF = 8'd10;
    
    // 【新增】CONFIG命令关键字符
    localparam ASCII_C = 8'd67;       // 'C'
    localparam ASCII_O = 8'd79;       // 'O'
    localparam ASCII_N = 8'd78;       // 'N'
    localparam ASCII_F = 8'd70;       // 'F'
    localparam ASCII_I = 8'd73;       // 'I'
    localparam ASCII_G = 8'd71;       // 'G'
    localparam ASCII_M = 8'd77;       // 'M'
    localparam ASCII_A = 8'd65;       // 'A'
    localparam ASCII_X = 8'd88;       // 'X'
    localparam ASCII_R = 8'd82;       // 'R'
    localparam ASCII_E = 8'd69;       // 'E'
    localparam ASCII_T = 8'd84;       // 'T'
    localparam ASCII_U = 8'd85;       // 'U'
    
    // 【新增】命令识别缓冲区
    reg [47:0] cmd_buffer;            // 存储最近6个字符 "CONFIG"
    reg [31:0] sub_buffer;            // 存储子命令 "MAX" / "RANGE" / "COUNT"

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
                if (in_operand_select)
                    next_state = WAIT_ID_A;
                else if (start_input || start_gen)
                    next_state = WAIT_M;
                // 【新增】检测到CONFIG命令（在输出逻辑中识别）
            end
            
            WAIT_M: begin
                if (rx_valid && (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF))
                    next_state = WAIT_N;
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
                    2'b01: begin  // INPUT
                        if (data_cnt >= data_total)
                            next_state = DONE;
                    end
                    2'b10: begin  // GEN
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
            
            // 【新增】CONFIG命令解析状态
            CONFIG_CMD: begin
                // 等待第一个配置值
                next_state = CONFIG_VAL1;
            end
            
            CONFIG_VAL1: begin
                if (rx_valid && (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF)) begin
                    // 如果是RANGE命令，需要第二个值
                    if (config_type == 3'd1)  // RANGE
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
            // ===== 初始化所有输出 =====
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
            
            // 【新增】CONFIG相关初始化
            config_valid <= 1'b0;
            config_type <= 3'd0;
            config_value1 <= 8'sd0;
            config_value2 <= 8'sd0;
            cmd_buffer <= 48'd0;
            sub_buffer <= 32'd0;
            
        end else begin
            // ===== 默认清除单周期信号 =====
            write_en <= 1'b0;
            data_ready <= 1'b0;
            user_input_valid <= 1'b0;
            config_valid <= 1'b0;
            
            // 【新增】命令缓冲区滚动更新（持续检测CONFIG命令）
            if (rx_valid && state == IDLE) begin
                cmd_buffer <= {cmd_buffer[39:0], rx_data};
                
                // 检测 "CONFIG" 命令 (6个字符)
                if (cmd_buffer[47:40] == ASCII_C &&
                    cmd_buffer[39:32] == ASCII_O &&
                    cmd_buffer[31:24] == ASCII_N &&
                    cmd_buffer[23:16] == ASCII_F &&
                    cmd_buffer[15:8]  == ASCII_I &&
                    rx_data == ASCII_G) begin
                    // 识别到CONFIG命令，准备解析子命令
                    sub_buffer <= 32'd0;
                end
            end
            
            case (state)
                IDLE: begin
                    data_cnt <= 5'd0;
                    data_total <= 5'd0;
                    num_buffer <= 8'd0;
                    num_building <= 1'b0;
                    is_negative <= 1'b0;
                    
                    // 【新增】检测CONFIG子命令
                    if (rx_valid && cmd_buffer[47:8] == {ASCII_C, ASCII_O, ASCII_N, ASCII_F, ASCII_I, ASCII_G}) begin
                        sub_buffer <= {sub_buffer[23:0], rx_data};
                        
                        // 识别 "MAX" (CONFIG MAX)
                        if (sub_buffer[23:16] == ASCII_M &&
                            sub_buffer[15:8]  == ASCII_A &&
                            rx_data == ASCII_X) begin
                            config_type <= 3'd0;  // MAX_PER_SIZE
                        end
                        // 识别 "RANGE" (CONFIG RANGE)
                        else if (sub_buffer[31:24] == ASCII_R &&
                                 sub_buffer[23:16] == ASCII_A &&
                                 sub_buffer[15:8]  == ASCII_N &&
                                 sub_buffer[7:0]   == ASCII_G &&
                                 rx_data == ASCII_E) begin
                            config_type <= 3'd1;  // ELEM_RANGE
                        end
                        // 识别 "COUNT" (CONFIG COUNT)
                        else if (sub_buffer[31:24] == ASCII_C &&
                                 sub_buffer[23:16] == ASCII_O &&
                                 sub_buffer[15:8]  == ASCII_U &&
                                 sub_buffer[7:0]   == ASCII_N &&
                                 rx_data == ASCII_T) begin
                            config_type <= 3'd2;  // COUNTDOWN
                        end
                    end
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
                                2'b01: begin  // INPUT
                                    if (data_cnt < data_total) begin
                                        elem_data <= num_buffer;
                                        write_en <= 1'b1;
                                        data_cnt <= data_cnt + 1;
                                    end
                                end
                                2'b10: begin  // GEN
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
                
                // 【新增】CONFIG值解析
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
                            
                            num_buffer <= 8'd0;
                            num_building <= 1'b0;
                            is_negative <= 1'b0;
                            
                            // 如果不是RANGE命令，立即发送
                            if (config_type != 3'd1) begin
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
                            
                            config_valid <= 1'b1;  // 发送配置命令
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