module uart_cmd_parser (
    input wire clk,
    input wire rst_n,
    input wire [7:0] rx_data,      // 从uart_rx接收的字节
    input wire rx_valid,            // 接收数据有效标志
    
    output reg [3:0] cmd_type,      // 命令类型: 0=MATRIX, 1=GEN, 2=CONFIG, 3=DISPLAY
    output reg [2:0] dim_m,         // 矩阵行数
    output reg [2:0] dim_n,         // 矩阵列数
    output reg [7:0] elem_data,     // 矩阵元素数据
    output reg [7:0] elem_min,      // 元素最小值(用于生成和配置)
    output reg [7:0] elem_max,      // 元素最大值(用于生成和配置)
    output reg [3:0] matrix_id_in,  // 矩阵编号
    output reg cfg_valid,           // 配置有效标志
    output reg write_en,            // 写使能
    output reg read_en              // 读使能
);

    // 命令类型定义
    localparam CMD_MATRIX  = 4'd0;
    localparam CMD_GEN     = 4'd1;
    localparam CMD_CONFIG  = 4'd2;
    localparam CMD_DISPLAY = 4'd3;
    localparam CMD_END     = 4'd4;

    // 解析状态机
    localparam IDLE        = 4'd0;
    localparam PARSE_CMD   = 4'd1;
    localparam WAIT_DIM_M  = 4'd2;
    localparam WAIT_DIM_N  = 4'd3;
    localparam WAIT_ELEM   = 4'd4;
    localparam WAIT_COUNT  = 4'd5;  // GEN命令等待矩阵个数
    localparam WAIT_MIN    = 4'd6;  // CONFIG等待最小值
    localparam WAIT_MAX    = 4'd7;  // CONFIG等待最大值
    localparam WAIT_END    = 4'd8;

    reg [3:0] state, next_state;
    reg [7:0] cmd_buffer [0:15];  // 命令缓冲区
    reg [3:0] buf_idx;             // 缓冲区索引
    reg [4:0] elem_cnt;            // 当前元素计数
    reg [4:0] elem_total;          // 总元素数 = m * n
    
    // ASCII码定义
    localparam ASCII_M = 8'd77;    // 'M'
    localparam ASCII_A = 8'd65;    // 'A'
    localparam ASCII_T = 8'd84;    // 'T'
    localparam ASCII_R = 8'd82;    // 'R'
    localparam ASCII_I = 8'd73;    // 'I'
    localparam ASCII_X = 8'd88;    // 'X'
    localparam ASCII_G = 8'd71;    // 'G'
    localparam ASCII_E = 8'd69;    // 'E'
    localparam ASCII_N = 8'd78;    // 'N'
    localparam ASCII_C = 8'd67;    // 'C'
    localparam ASCII_O = 8'd79;    // 'O'
    localparam ASCII_F = 8'd70;    // 'F'
    localparam ASCII_D = 8'd68;    // 'D'
    localparam ASCII_SPACE = 8'd32; // ' '
    localparam ASCII_0 = 8'd48;    // '0'
    localparam ASCII_9 = 8'd57;    // '9'
    localparam ASCII_MINUS = 8'd45; // '-'

    // 状态机 - 时序逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // 状态机 - 组合逻辑
    always @(*) begin
        next_state = state;
        
        case (state)
            IDLE: begin
                if (rx_valid) begin
                    // 检测命令开头
                    if (rx_data == ASCII_M)
                        next_state = PARSE_CMD;
                    else if (rx_data == ASCII_G)
                        next_state = PARSE_CMD;
                    else if (rx_data == ASCII_C)
                        next_state = PARSE_CMD;
                    else if (rx_data == ASCII_D)
                        next_state = PARSE_CMD;
                end
            end
            
            PARSE_CMD: begin
                if (rx_valid && rx_data == ASCII_SPACE) begin
                    // 根据命令类型跳转
                    if (cmd_type == CMD_MATRIX || cmd_type == CMD_GEN)
                        next_state = WAIT_DIM_M;
                    else if (cmd_type == CMD_CONFIG)
                        next_state = WAIT_MIN;
                    else if (cmd_type == CMD_DISPLAY)
                        next_state = WAIT_DIM_M;
                end
            end
            
            WAIT_DIM_M: begin
                if (rx_valid && rx_data == ASCII_SPACE)
                    next_state = WAIT_DIM_N;
            end
            
            WAIT_DIM_N: begin
                if (rx_valid && rx_data == ASCII_SPACE) begin
                    if (cmd_type == CMD_GEN)
                        next_state = WAIT_COUNT;
                    else if (cmd_type == CMD_MATRIX)
                        next_state = WAIT_ELEM;
                    else if (cmd_type == CMD_DISPLAY)
                        next_state = WAIT_END;
                end
            end
            
            WAIT_COUNT: begin
                if (rx_valid && rx_data == ASCII_SPACE)
                    next_state = WAIT_END;
            end
            
            WAIT_ELEM: begin
                if (elem_cnt >= elem_total)
                    next_state = WAIT_END;
            end
            
            WAIT_MIN: begin
                if (rx_valid && rx_data == ASCII_SPACE)
                    next_state = WAIT_MAX;
            end
            
            WAIT_MAX: begin
                if (rx_valid && rx_data == ASCII_SPACE)
                    next_state = WAIT_END;
            end
            
            WAIT_END: begin
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end

    // 数据处理逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_type <= 4'd0;
            dim_m <= 3'd0;
            dim_n <= 3'd0;
            elem_data <= 8'd0;
            elem_min <= 8'd0;
            elem_max <= 8'd9;
            matrix_id_in <= 4'd0;
            cfg_valid <= 1'b0;
            write_en <= 1'b0;
            read_en <= 1'b0;
            buf_idx <= 4'd0;
            elem_cnt <= 5'd0;
            elem_total <= 5'd0;
        end else begin
            // 默认关闭控制信号
            cfg_valid <= 1'b0;
            write_en <= 1'b0;
            read_en <= 1'b0;
            
            case (state)
                IDLE: begin
                    if (rx_valid) begin
                        buf_idx <= 4'd1;
                        cmd_buffer[0] <= rx_data;
                        elem_cnt <= 5'd0;
                        
                        // 识别命令类型
                        if (rx_data == ASCII_M)
                            cmd_type <= CMD_MATRIX;
                        else if (rx_data == ASCII_G)
                            cmd_type <= CMD_GEN;
                        else if (rx_data == ASCII_C)
                            cmd_type <= CMD_CONFIG;
                        else if (rx_data == ASCII_D)
                            cmd_type <= CMD_DISPLAY;
                    end
                end
                
                PARSE_CMD: begin
                    if (rx_valid) begin
                        if (rx_data != ASCII_SPACE) begin
                            cmd_buffer[buf_idx] <= rx_data;
                            buf_idx <= buf_idx + 1;
                        end
                    end
                end
                
                WAIT_DIM_M: begin
                    if (rx_valid && rx_data >= ASCII_0 && rx_data <= ASCII_9) begin
                        dim_m <= rx_data - ASCII_0;
                    end
                end
                
                WAIT_DIM_N: begin
                    if (rx_valid && rx_data >= ASCII_0 && rx_data <= ASCII_9) begin
                        dim_n <= rx_data - ASCII_0;
                        elem_total <= (rx_data - ASCII_0) * dim_m;
                    end
                end
                
                WAIT_COUNT: begin
                    if (rx_valid && rx_data >= ASCII_0 && rx_data <= ASCII_9) begin
                        matrix_id_in <= rx_data - ASCII_0;
                    end
                end
                
                WAIT_ELEM: begin
                    if (rx_valid) begin
                        if (rx_data == ASCII_SPACE || 
                            (rx_data >= ASCII_0 && rx_data <= ASCII_9)) begin
                            if (rx_data >= ASCII_0 && rx_data <= ASCII_9) begin
                                elem_data <= rx_data - ASCII_0;
                                write_en <= 1'b1;
                                elem_cnt <= elem_cnt + 1;
                            end
                        end
                        else if (rx_data == ASCII_MINUS) begin
                            // 处理负号(如果需要支持负数)
                        end
                    end
                end
                
                WAIT_MIN: begin
                    if (rx_valid) begin
                        if (rx_data >= ASCII_0 && rx_data <= ASCII_9)
                            elem_min <= rx_data - ASCII_0;
                        else if (rx_data == ASCII_MINUS)
                            elem_min[7] <= 1'b1; // 标记为负数
                    end
                end
                
                WAIT_MAX: begin
                    if (rx_valid) begin
                        if (rx_data >= ASCII_0 && rx_data <= ASCII_9)
                            elem_max <= rx_data - ASCII_0;
                    end
                end
                
                WAIT_END: begin
                    // 命令解析完成,发出相应控制信号
                    if (cmd_type == CMD_CONFIG)
                        cfg_valid <= 1'b1;
                    else if (cmd_type == CMD_DISPLAY)
                        read_en <= 1'b1;
                    else if (cmd_type == CMD_GEN)
                        write_en <= 1'b1;
                end
                
                default: ;
            endcase
        end
    end

endmodule