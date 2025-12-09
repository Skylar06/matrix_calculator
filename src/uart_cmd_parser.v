module uart_cmd_parser (
    input wire clk,
    input wire rst_n,
    input wire [7:0] rx_data,       // 从uart_rx接收的字节
    input wire rx_valid,            // 接收数据有效标志
    input wire [1:0] mode_sel,      // 当前模式(从ctrl_fsm来)
    input wire start_input,         // INPUT模式启动信号
    input wire start_gen,           // GEN模式启动信号
    
    output reg [2:0] dim_m,         // 矩阵行数
    output reg [2:0] dim_n,         // 矩阵列数
    output reg [7:0] elem_data,     // 矩阵元素数据
    output reg [7:0] elem_min,      // 元素最小值(用于生成)
    output reg [7:0] elem_max,      // 元素最大值(用于生成)
    output reg [3:0] count,         // 矩阵个数(用于生成)
    output reg [3:0] matrix_id,     // 矩阵编号(用于运算数选择)
    output reg write_en,            // 写使能
    output reg data_ready           // 数据准备完成标志
);

    // ========== 解析状态定义 ==========
    localparam IDLE         = 3'd0;
    localparam WAIT_M       = 3'd1;  // 等待行数
    localparam WAIT_N       = 3'd2;  // 等待列数
    localparam WAIT_DATA    = 3'd3;  // 等待数据(元素/个数/ID)
    localparam DONE         = 3'd4;

    reg [2:0] state, next_state;
    
    // ========== 数据处理相关 ==========
    reg [4:0] data_cnt;              // 数据计数
    reg [4:0] data_total;            // 数据总数
    reg [7:0] num_buffer;            // 数字缓冲(用于解析多位数)
    reg num_building;                // 正在构建数字
    
    // ASCII码定义
    localparam ASCII_SPACE = 8'd32;
    localparam ASCII_0 = 8'd48;
    localparam ASCII_9 = 8'd57;
    localparam ASCII_MINUS = 8'd45;
    localparam ASCII_CR = 8'd13;     // 回车 \r
    localparam ASCII_LF = 8'd10;     // 换行 \n

    // ========== 状态机时序逻辑 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // ========== 状态转换组合逻辑 ==========
    always @(*) begin
        next_state = state;
        
        case (state)
            IDLE: begin
                // 根据模式启动信号进入相应状态
                if (start_input || start_gen)
                    next_state = WAIT_M;
            end
            
            WAIT_M: begin
                // 接收到行数后
                if (rx_valid && (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF))
                    next_state = WAIT_N;
            end
            
            WAIT_N: begin
                // 接收到列数后
                if (rx_valid && (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF)) begin
                    // 根据模式决定下一步
                    case (mode_sel)
                        2'b00: next_state = WAIT_DATA;  // INPUT: 等待矩阵元素
                        2'b01: next_state = WAIT_DATA;  // GEN: 等待个数
                        default: next_state = DONE;
                    endcase
                end
            end
            
            WAIT_DATA: begin
                // 根据模式判断是否完成
                case (mode_sel)
                    2'b01: begin  // INPUT模式: 接收 m*n 个元素
                        if (data_cnt >= data_total)
                            next_state = DONE;
                    end
                    2'b10: begin  // GEN模式: 接收1个数(个数)
                        if (data_cnt >= 1)
                            next_state = DONE;
                    end
                    default: next_state = DONE;
                endcase
            end
            
            DONE: begin
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end

    // ========== 数据处理时序逻辑 ==========
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
        end else begin
            // 默认关闭控制信号
            write_en <= 1'b0;
            data_ready <= 1'b0;
            
            case (state)
                IDLE: begin
                    data_cnt <= 5'd0;
                    data_total <= 5'd0;
                    num_buffer <= 8'd0;
                    num_building <= 1'b0;
                end
                
                WAIT_M: begin
                    if (rx_valid) begin
                        if (rx_data >= ASCII_0 && rx_data <= ASCII_9) begin
                            // 构建多位数
                            if (num_building) begin
                                num_buffer <= num_buffer * 10 + (rx_data - ASCII_0);
                            end else begin
                                num_buffer <= rx_data - ASCII_0;
                                num_building <= 1'b1;
                            end
                        end
                        else if (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF) begin
                            // 空格/回车表示数字结束
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
                            data_total <= dim_m * num_buffer[2:0];  // 计算总元素数
                            num_buffer <= 8'd0;
                            num_building <= 1'b0;
                        end
                    end
                end
                
                WAIT_DATA: begin
                    if (rx_valid) begin
                        if (rx_data >= ASCII_0 && rx_data <= ASCII_9) begin
                            // 构建数字
                            if (num_building) begin
                                num_buffer <= num_buffer * 10 + (rx_data - ASCII_0);
                            end else begin
                                num_buffer <= rx_data - ASCII_0;
                                num_building <= 1'b1;
                            end
                        end
                        else if (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF) begin
                            // 数字结束,根据模式处理
                            case (mode_sel)
                                2'b01: begin  // INPUT模式: 存储矩阵元素
                                    // 只在未超过总数时输出
                                    if (data_cnt < data_total) begin
                                        elem_data <= num_buffer;
                                        write_en <= 1'b1;  // 产生写使能脉冲
                                        data_cnt <= data_cnt + 1;
                                    end
                                    // 超过总数的元素自动忽略
                                end
                                2'b10: begin  // GEN模式: 存储个数
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
                
                DONE: begin
                    data_ready <= 1'b1;  // 标记数据准备完成
                end
                
                default: ;
            endcase
        end
    end

endmodule

// ============================================================================
// 使用说明:
//
// INPUT模式 (mode_sel = 2'b01):
//   用户输入: "2 3 1 2 3 4 5 6" 或 "2 3 1 2 3 4 5 6\n"
//   解析结果: dim_m=2, dim_n=3, 依次输出elem_data=1,2,3,4,5,6
//   每个元素产生一个write_en脉冲
//
//   注意: 所有合法性检测由matrix_storage负责!
//   - 维度检测 (1-5): storage检查
//   - 数值检测 (0-9): storage检查
//   - 元素不足: storage自动填0
//   - 元素超出: parser只输出前N个
//
// GEN模式 (mode_sel = 2'b10):
//   用户输入: "3 3 2" 或 "3 3 2\n"
//   解析结果: dim_m=3, dim_n=3, count=2
//   data_ready=1标记完成
//
// 支持多位数:
//   输入 "12 25" → dim_m=12, dim_n=25 (storage会检测并报错)
//
// 分隔符:
//   支持空格、回车(\r)、换行(\n)作为分隔符
// ============================================================================