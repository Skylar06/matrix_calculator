module display_formatter (
    input wire clk,
    input wire rst_n,
    
    // ========== 控制信号 ==========
    input wire start_format,                // 启动格式化流程
    input wire [1:0] display_mode,          // 显示模式选择
    
    // ========== 单矩阵显示接口 ==========
    input wire [3:0] matrix_id,             // 矩阵ID
    input wire [2:0] dim_m,                 // 行数
    input wire [2:0] dim_n,                 // 列数
    input wire [7:0] matrix_data,           // 矩阵数据流
    input wire matrix_data_valid,           // 数据有效标志
    
    // ========== 矩阵列表接口（打包向量，便于综合）==========
    input wire [3*10-1:0] list_m_flat,      // 10个3bit 行
    input wire [3*10-1:0] list_n_flat,      // 10个3bit 列
    input wire [10-1:0]   list_valid_flat,  // 10个有效位
    
    // ========== UART发送接口 ==========
    output reg [7:0] tx_data,               // 待发送的字符
    output reg tx_valid,                    // 发送有效标志
    input wire tx_busy,                     // UART忙标志
    output reg data_req,                    // 【新增】请求下一数据的脉冲
    
    // ========== 输出 ==========
    output reg format_done                  // 格式化完成标志
);

    // ========== 状态定义 ==========
    localparam IDLE           = 4'd0;       // 空闲状态
    localparam SEND_HEADER    = 4'd1;       // 发送标题字符串
    localparam SEND_MATRIX    = 4'd2;       // 发送矩阵数据
    localparam SEND_NEWLINE   = 4'd3;       // 发送换行符
    localparam SEND_LIST      = 4'd4;       // 发送列表信息
    localparam DONE           = 4'd5;       // 完成
    
    reg [3:0] state;
    
    // ========== 标题字符串缓冲区 ==========
    reg [7:0] header_buffer [0:31];         // 最多32字节的标题
    reg [4:0] header_len;                   // 标题长度
    reg [4:0] char_idx;                     // 当前发送的字符索引
    
    // ========== 矩阵数据处理变量 ==========
    reg [4:0] elem_cnt;                     // 已处理的元素计数
    reg [4:0] elem_total;                   // 元素总数
    reg [2:0] col_cnt;                      // 当前列计数（用于换行判断）
    
    // ========== 列表处理变量 ==========
    reg [3:0] list_idx;                     // 当前处理的列表索引
    wire [2:0] list_m [0:9];
    wire [2:0] list_n [0:9];
    wire       list_valid [0:9];
    // 解包列表向量
    genvar li;
    generate
        for (li = 0; li < 10; li = li + 1) begin : GEN_UNPACK_LIST
            assign list_m[li]     = list_m_flat[li*3 +: 3];
            assign list_n[li]     = list_n_flat[li*3 +: 3];
            assign list_valid[li] = list_valid_flat[li];
        end
    endgenerate
    
    // ========== 缓存当前矩阵信息 ==========
    reg [2:0] current_m, current_n;         // 当前矩阵的维度
    reg [3:0] current_id;                   // 当前矩阵的ID
    reg [7:0] current_data;                 // 【新增】缓存当前元素
    reg waiting_data;                       // 【新增】等待新数据标志
    reg signed [7:0] abs_data;              // 【新增】用于计算绝对值的临时变量
    
    /**************************************************************************
     * 函数：数字转ASCII
     * 输入：0-9的数字
     * 输出：对应的ASCII码 ('0'=48, '1'=49, ...)
     **************************************************************************/
    function [7:0] digit_to_ascii;
        input [3:0] digit;
        begin
            digit_to_ascii = 8'd48 + digit;
        end
    endfunction
    
    /**************************************************************************
     * 主状态机
     **************************************************************************/
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // ===== 复位初始化 =====
            state <= IDLE;
            tx_data <= 8'd0;
            tx_valid <= 1'b0;
            format_done <= 1'b0;
            char_idx <= 5'd0;
            elem_cnt <= 5'd0;
            col_cnt <= 3'd0;
            list_idx <= 4'd0;
            header_len <= 5'd0;
            current_m <= 3'd0;
            current_n <= 3'd0;
            current_id <= 4'd0;
            current_data <= 8'd0;
            waiting_data <= 1'b0;
            data_req <= 1'b0;
        end else begin
            data_req <= 1'b0;  // 默认拉低请求
            case (state)
                // ========== 状态0：空闲 ==========
                IDLE: begin
                    format_done <= 1'b0;
                    tx_valid <= 1'b0;
                    char_idx <= 5'd0;
                    elem_cnt <= 5'd0;
                    col_cnt <= 3'd0;
                    list_idx <= 4'd0;
                    waiting_data <= 1'b0;
                    
                    if (start_format) begin
                        // 缓存矩阵信息
                        current_m <= dim_m;
                        current_n <= dim_n;
                        current_id <= matrix_id;
                        elem_total <= dim_m * dim_n;
                        
                        case (display_mode)
                            // ===== 模式0：单矩阵显示 =====
                            2'd0: begin
                                // 构建标题："Matrix X (MxN):\n"
                                header_buffer[0]  <= 8'd77;   // 'M'
                                header_buffer[1]  <= 8'd97;   // 'a'
                                header_buffer[2]  <= 8'd116;  // 't'
                                header_buffer[3]  <= 8'd114;  // 'r'
                                header_buffer[4]  <= 8'd105;  // 'i'
                                header_buffer[5]  <= 8'd120;  // 'x'
                                header_buffer[6]  <= 8'd32;   // ' '
                                header_buffer[7]  <= digit_to_ascii(matrix_id);
                                header_buffer[8]  <= 8'd32;   // ' '
                                header_buffer[9]  <= 8'd40;   // '('
                                header_buffer[10] <= digit_to_ascii(dim_m);
                                header_buffer[11] <= 8'd120;  // 'x'
                                header_buffer[12] <= digit_to_ascii(dim_n);
                                header_buffer[13] <= 8'd41;   // ')'
                                header_buffer[14] <= 8'd58;   // ':'
                                header_buffer[15] <= 8'd10;   // '\n'
                                header_len <= 5'd16;
                                state <= SEND_HEADER;
                            end
                            
                            // ===== 模式1：矩阵列表 =====
                            2'd1: begin
                                // 构建标题："Available Matrices:\n"
                                header_buffer[0]  <= 8'd65;   // 'A'
                                header_buffer[1]  <= 8'd118;  // 'v'
                                header_buffer[2]  <= 8'd97;   // 'a'
                                header_buffer[3]  <= 8'd105;  // 'i'
                                header_buffer[4]  <= 8'd108;  // 'l'
                                header_buffer[5]  <= 8'd97;   // 'a'
                                header_buffer[6]  <= 8'd98;   // 'b'
                                header_buffer[7]  <= 8'd108;  // 'l'
                                header_buffer[8]  <= 8'd101;  // 'e'
                                header_buffer[9]  <= 8'd32;   // ' '
                                header_buffer[10] <= 8'd77;   // 'M'
                                header_buffer[11] <= 8'd97;   // 'a'
                                header_buffer[12] <= 8'd116;  // 't'
                                header_buffer[13] <= 8'd114;  // 'r'
                                header_buffer[14] <= 8'd105;  // 'i'
                                header_buffer[15] <= 8'd99;   // 'c'
                                header_buffer[16] <= 8'd101;  // 'e'
                                header_buffer[17] <= 8'd115;  // 's'
                                header_buffer[18] <= 8'd58;   // ':'
                                header_buffer[19] <= 8'd10;   // '\n'
                                header_len <= 5'd20;
                                state <= SEND_HEADER;
                            end
                            
                            // ===== 模式2：运算结果 =====
                            2'd2: begin
                                // 构建标题："Result (MxN):\n"
                                header_buffer[0]  <= 8'd82;   // 'R'
                                header_buffer[1]  <= 8'd101;  // 'e'
                                header_buffer[2]  <= 8'd115;  // 's'
                                header_buffer[3]  <= 8'd117;  // 'u'
                                header_buffer[4]  <= 8'd108;  // 'l'
                                header_buffer[5]  <= 8'd116;  // 't'
                                header_buffer[6]  <= 8'd32;   // ' '
                                header_buffer[7]  <= 8'd40;   // '('
                                header_buffer[8]  <= digit_to_ascii(dim_m);
                                header_buffer[9]  <= 8'd120;  // 'x'
                                header_buffer[10] <= digit_to_ascii(dim_n);
                                header_buffer[11] <= 8'd41;   // ')'
                                header_buffer[12] <= 8'd58;   // ':'
                                header_buffer[13] <= 8'd10;   // '\n'
                                header_len <= 5'd14;
                                state <= SEND_HEADER;
                            end
                            
                            default: state <= IDLE;
                        endcase
                    end
                end
                
                // ========== 状态1：发送标题字符串 ==========
                SEND_HEADER: begin
                    if (!tx_busy) begin
                        if (char_idx < header_len) begin
                            // 逐字符发送标题
                            tx_data <= header_buffer[char_idx];
                            tx_valid <= 1'b1;
                            char_idx <= char_idx + 1;
                        end else begin
                            // 标题发送完成
                            tx_valid <= 1'b0;
                            char_idx <= 5'd0;
                            
                            // 根据模式选择下一状态
                            if (display_mode == 2'd1) begin
                                state <= SEND_LIST;     // 列表模式
                            end else begin
                                // 准备请求第一组数据
                                waiting_data <= 1'b1;
                                data_req <= 1'b1;
                                state <= SEND_MATRIX;   // 矩阵模式
                            end
                        end
                    end else begin
                        tx_valid <= 1'b0;  // UART忙，等待
                    end
                end
                
                // ========== 状态2：发送矩阵数据 ==========
                // 格式：每个数字后跟空格，行末换行
                // 例如："1 2 3\n4 5 6\n"
                SEND_MATRIX: begin
                    // 等待新的数据到来
                    if (waiting_data) begin
                        if (matrix_data_valid) begin
                            current_data <= matrix_data;
                            waiting_data <= 1'b0;
                            char_idx <= 5'd0;
                        end else begin
                            data_req <= 1'b1; // 继续请求
                        end
                    end
                    // 数据已缓存，按字符发送
                    else if (!tx_busy) begin
                        // ===== 支持有符号数显示（支持负数，支持-128到127）=====
                        // 计算绝对值（在状态0时计算一次，后续状态复用）
                        if (char_idx == 0) begin
                            if ($signed(current_data) < 0) begin
                                abs_data <= -$signed(current_data);
                            end else begin
                                abs_data <= $signed(current_data);
                            end
                        end
                        
                        // 子状态0：发送负号（如果是负数）
                        if (char_idx == 0) begin
                            if ($signed(current_data) < 0) begin
                                tx_data <= 8'd45;  // '-' 负号
                                tx_valid <= 1'b1;
                            end
                            char_idx <= 5'd1;
                        end
                        // ===== 子状态1：发送百位数字（如果需要，支持-128到127）=====
                        else if (char_idx == 1) begin
                            if (abs_data >= 100) begin
                                tx_data <= digit_to_ascii(abs_data / 100);
                                tx_valid <= 1'b1;
                            end
                            char_idx <= 5'd2;
                        end
                        // ===== 子状态2：发送十位数字（如果需要）=====
                        else if (char_idx == 2) begin
                            if (abs_data >= 10) begin
                                tx_data <= digit_to_ascii((abs_data / 10) % 10);
                                tx_valid <= 1'b1;
                            end
                            char_idx <= 5'd3;
                        end
                        // ===== 子状态3：发送个位数字 =====
                        else if (char_idx == 3) begin
                            tx_data <= digit_to_ascii(abs_data % 10);
                            tx_valid <= 1'b1;
                            char_idx <= 5'd4;
                        end
                        // ===== 子状态4：发送分隔符（空格或换行）=====
                        else if (char_idx == 4) begin
                            col_cnt <= col_cnt + 1;
                            elem_cnt <= elem_cnt + 1;
                            
                            // 判断是行末还是行中
                            if (col_cnt >= current_n - 1) begin
                                tx_data <= 8'd10;  // '\n' 换行
                                col_cnt <= 3'd0;
                            end else begin
                                tx_data <= 8'd32;  // ' ' 空格
                            end
                            tx_valid <= 1'b1;
                            char_idx <= 5'd0;      // 重置子状态
                            
                            // 检查是否全部发送完成
                            if (elem_cnt >= elem_total - 1) begin
                                state <= SEND_NEWLINE;
                            end else begin
                                waiting_data <= 1'b1;
                                data_req <= 1'b1;   // 请求下一个元素
                            end
                        end
                    end else begin
                        tx_valid <= 1'b0;
                    end
                end
                
                // ========== 状态4：发送列表信息 ==========
                // 格式："[0] 3x3\n [1] Empty\n ..."
                SEND_LIST: begin
                    if (!tx_busy) begin
                        if (list_idx < 10) begin
                            // ===== 子状态：发送 "[X] " =====
                            if (char_idx == 0) begin
                                tx_data <= 8'd91;        // '['
                                tx_valid <= 1'b1;
                                char_idx <= 5'd1;
                            end
                            else if (char_idx == 1) begin
                                tx_data <= digit_to_ascii(list_idx);
                                tx_valid <= 1'b1;
                                char_idx <= 5'd2;
                            end
                            else if (char_idx == 2) begin
                                tx_data <= 8'd93;        // ']'
                                tx_valid <= 1'b1;
                                char_idx <= 5'd3;
                            end
                            else if (char_idx == 3) begin
                                tx_data <= 8'd32;        // ' '
                                tx_valid <= 1'b1;
                                char_idx <= 5'd4;
                            end
                            // ===== 子状态：发送维度或"Empty" =====
                            else if (char_idx == 4) begin
                                if (list_valid[list_idx]) begin
                                    // 发送 "MxN"
                                    tx_data <= digit_to_ascii(list_m[list_idx]);
                                    tx_valid <= 1'b1;
                                    char_idx <= 5'd5;
                                end else begin
                                    // 发送 "Empty"
                                    tx_data <= 8'd69;    // 'E'
                                    tx_valid <= 1'b1;
                                    char_idx <= 5'd9;    // 跳转到Empty流程
                                end
                            end
                            else if (char_idx == 5) begin
                                tx_data <= 8'd120;       // 'x'
                                tx_valid <= 1'b1;
                                char_idx <= 5'd6;
                            end
                            else if (char_idx == 6) begin
                                tx_data <= digit_to_ascii(list_n[list_idx]);
                                tx_valid <= 1'b1;
                                char_idx <= 5'd7;
                            end
                            else if (char_idx == 7) begin
                                tx_data <= 8'd10;        // '\n'
                                tx_valid <= 1'b1;
                                char_idx <= 5'd0;
                                list_idx <= list_idx + 1;
                            end
                            // ===== "Empty"字符串发送 =====
                            else if (char_idx == 9) begin
                                tx_data <= 8'd109;       // 'm'
                                tx_valid <= 1'b1;
                                char_idx <= 5'd10;
                            end
                            else if (char_idx == 10) begin
                                tx_data <= 8'd112;       // 'p'
                                tx_valid <= 1'b1;
                                char_idx <= 5'd11;
                            end
                            else if (char_idx == 11) begin
                                tx_data <= 8'd116;       // 't'
                                tx_valid <= 1'b1;
                                char_idx <= 5'd12;
                            end
                            else if (char_idx == 12) begin
                                tx_data <= 8'd121;       // 'y'
                                tx_valid <= 1'b1;
                                char_idx <= 5'd13;
                            end
                            else if (char_idx == 13) begin
                                tx_data <= 8'd10;        // '\n'
                                tx_valid <= 1'b1;
                                char_idx <= 5'd0;
                                list_idx <= list_idx + 1;
                            end
                        end else begin
                            // 所有列表项发送完成
                            state <= DONE;
                        end
                    end else begin
                        tx_valid <= 1'b0;
                    end
                end
                
                // ========== 状态3：发送最后换行 ==========
                SEND_NEWLINE: begin
                    if (!tx_busy) begin
                        tx_data <= 8'd10;  // '\n'
                        tx_valid <= 1'b1;
                        state <= DONE;
                    end else begin
                        tx_valid <= 1'b0;
                    end
                end
                
                // ========== 状态5：完成 ==========
                DONE: begin
                    tx_valid <= 1'b0;
                    format_done <= 1'b1;  // 通知上层完成
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule