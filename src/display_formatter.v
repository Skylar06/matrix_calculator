module display_formatter (
    input wire clk,
    input wire rst_n,
    input wire start_format,           // 启动格式化
    input wire [1:0] display_mode,     // 0=单矩阵, 1=矩阵列表, 2=运算结果
    
    // 单矩阵显示接口
    input wire [3:0] matrix_id,
    input wire [2:0] dim_m,
    input wire [2:0] dim_n,
    input wire [7:0] matrix_data,      // 来自storage的数据流
    input wire matrix_data_valid,
    
    // 矩阵列表接口
    input wire [2:0] list_m [0:9],
    input wire [2:0] list_n [0:9],
    input wire list_valid [0:9],
    
    // UART发送接口
    output reg [7:0] tx_data,
    output reg tx_valid,
    input wire tx_busy,
    
    output reg format_done
);

    // ========== 状态定义 ==========
    localparam IDLE           = 4'd0;
    localparam SEND_HEADER    = 4'd1;   // 发送标题
    localparam SEND_MATRIX    = 4'd2;   // 发送矩阵数据
    localparam SEND_NEWLINE   = 4'd3;   // 发送换行
    localparam SEND_LIST      = 4'd4;   // 发送列表信息
    localparam DONE           = 4'd5;
    
    reg [3:0] state;
    
    // ========== 字符串缓冲区 ==========
    reg [7:0] header_str [0:31];        // 标题字符串缓冲
    reg [4:0] header_len;
    reg [4:0] char_idx;
    
    // ========== 矩阵数据处理 ==========
    reg [4:0] elem_cnt;
    reg [4:0] elem_total;
    reg [2:0] col_cnt;
    
    // ========== 列表处理 ==========
    reg [3:0] list_idx;
    
    // ========== 数字转ASCII函数 ==========
    function [7:0] digit_to_ascii;
        input [3:0] digit;
        begin
            digit_to_ascii = 8'd48 + digit;  // '0' = 48
        end
    endfunction
    
    // ========== 主状态机 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            tx_data <= 8'd0;
            tx_valid <= 1'b0;
            format_done <= 1'b0;
            char_idx <= 5'd0;
            elem_cnt <= 5'd0;
            col_cnt <= 3'd0;
            list_idx <= 4'd0;
        end else begin
            case (state)
                IDLE: begin
                    format_done <= 1'b0;
                    tx_valid <= 1'b0;
                    char_idx <= 5'd0;
                    elem_cnt <= 5'd0;
                    col_cnt <= 3'd0;
                    list_idx <= 4'd0;
                    
                    if (start_format) begin
                        case (display_mode)
                            2'd0: begin  // 单矩阵显示
                                // 构建标题: "Matrix X (MxN):\n"
                                prepare_matrix_header(matrix_id, dim_m, dim_n);
                                elem_total <= dim_m * dim_n;
                                state <= SEND_HEADER;
                            end
                            2'd1: begin  // 矩阵列表
                                prepare_list_header();
                                state <= SEND_HEADER;
                            end
                            2'd2: begin  // 运算结果
                                prepare_result_header(dim_m, dim_n);
                                elem_total <= dim_m * dim_n;
                                state <= SEND_HEADER;
                            end
                            default: state <= IDLE;
                        endcase
                    end
                end
                
                SEND_HEADER: begin
                    if (!tx_busy) begin
                        if (char_idx < header_len) begin
                            tx_data <= header_str[char_idx];
                            tx_valid <= 1'b1;
                            char_idx <= char_idx + 1;
                        end else begin
                            tx_valid <= 1'b0;
                            char_idx <= 5'd0;
                            
                            if (display_mode == 2'd1)
                                state <= SEND_LIST;
                            else
                                state <= SEND_MATRIX;
                        end
                    end else begin
                        tx_valid <= 1'b0;
                    end
                end
                
                SEND_MATRIX: begin
                    if (matrix_data_valid && !tx_busy) begin
                        // 发送数字的十位
                        if (char_idx == 0) begin
                            if (matrix_data >= 10) begin
                                tx_data <= digit_to_ascii(matrix_data / 10);
                                tx_valid <= 1'b1;
                                char_idx <= 5'd1;
                            end else begin
                                char_idx <= 5'd1;  // 跳过十位
                            end
                        end
                        // 发送数字的个位
                        else if (char_idx == 1) begin
                            tx_data <= digit_to_ascii(matrix_data % 10);
                            tx_valid <= 1'b1;
                            char_idx <= 5'd2;
                        end
                        // 发送空格或换行
                        else if (char_idx == 2) begin
                            col_cnt <= col_cnt + 1;
                            elem_cnt <= elem_cnt + 1;
                            
                            if (col_cnt >= dim_n - 1) begin
                                tx_data <= 8'd10;  // '\n'
                                col_cnt <= 3'd0;
                            end else begin
                                tx_data <= 8'd32;  // ' '
                            end
                            tx_valid <= 1'b1;
                            char_idx <= 5'd0;
                            
                            // 检查是否完成
                            if (elem_cnt >= elem_total - 1) begin
                                state <= SEND_NEWLINE;
                            end
                        end
                    end else begin
                        tx_valid <= 1'b0;
                    end
                end
                
                SEND_LIST: begin
                    if (!tx_busy) begin
                        if (list_idx < 10) begin
                            // 发送 "[X] "
                            if (char_idx == 0) begin
                                tx_data <= 8'd91;  // '['
                                tx_valid <= 1'b1;
                                char_idx <= 5'd1;
                            end
                            else if (char_idx == 1) begin
                                tx_data <= digit_to_ascii(list_idx);
                                tx_valid <= 1'b1;
                                char_idx <= 5'd2;
                            end
                            else if (char_idx == 2) begin
                                tx_data <= 8'd93;  // ']'
                                tx_valid <= 1'b1;
                                char_idx <= 5'd3;
                            end
                            else if (char_idx == 3) begin
                                tx_data <= 8'd32;  // ' '
                                tx_valid <= 1'b1;
                                char_idx <= 5'd4;
                            end
                            // 发送维度或"Empty"
                            else if (char_idx == 4) begin
                                if (list_valid[list_idx]) begin
                                    // 发送 "MxN - Valid\n"
                                    send_dimension_string(list_m[list_idx], list_n[list_idx]);
                                end else begin
                                    // 发送 "Empty\n"
                                    send_empty_string();
                                end
                                char_idx <= 5'd0;
                                list_idx <= list_idx + 1;
                            end
                        end else begin
                            state <= DONE;
                        end
                    end else begin
                        tx_valid <= 1'b0;
                    end
                end
                
                SEND_NEWLINE: begin
                    if (!tx_busy) begin
                        tx_data <= 8'd10;  // '\n'
                        tx_valid <= 1'b1;
                        state <= DONE;
                    end else begin
                        tx_valid <= 1'b0;
                    end
                end
                
                DONE: begin
                    tx_valid <= 1'b0;
                    format_done <= 1'b1;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
    // ========== 辅助任务 - 准备标题字符串 ==========
    task prepare_matrix_header;
        input [3:0] id;
        input [2:0] m;
        input [2:0] n;
        begin
            // "Matrix X (MxN):\n"
            header_str[0]  <= 8'd77;  // 'M'
            header_str[1]  <= 8'd97;  // 'a'
            header_str[2]  <= 8'd116; // 't'
            header_str[3]  <= 8'd114; // 'r'
            header_str[4]  <= 8'd105; // 'i'
            header_str[5]  <= 8'd120; // 'x'
            header_str[6]  <= 8'd32;  // ' '
            header_str[7]  <= digit_to_ascii(id);
            header_str[8]  <= 8'd32;  // ' '
            header_str[9]  <= 8'd40;  // '('
            header_str[10] <= digit_to_ascii(m);
            header_str[11] <= 8'd120; // 'x'
            header_str[12] <= digit_to_ascii(n);
            header_str[13] <= 8'd41;  // ')'
            header_str[14] <= 8'd58;  // ':'
            header_str[15] <= 8'd10;  // '\n'
            header_len <= 5'd16;
        end
    endtask
    
    task prepare_list_header;
        begin
            // "Available Matrices:\n"
            header_str[0]  <= 8'd65;  // 'A'
            header_str[1]  <= 8'd118; // 'v'
            header_str[2]  <= 8'd97;  // 'a'
            header_str[3]  <= 8'd105; // 'i'
            header_str[4]  <= 8'd108; // 'l'
            header_str[5]  <= 8'd97;  // 'a'
            header_str[6]  <= 8'd98;  // 'b'
            header_str[7]  <= 8'd108; // 'l'
            header_str[8]  <= 8'd101; // 'e'
            header_str[9]  <= 8'd32;  // ' '
            header_str[10] <= 8'd77;  // 'M'
            header_str[11] <= 8'd97;  // 'a'
            header_str[12] <= 8'd116; // 't'
            header_str[13] <= 8'd114; // 'r'
            header_str[14] <= 8'd105; // 'i'
            header_str[15] <= 8'd99;  // 'c'
            header_str[16] <= 8'd101; // 'e'
            header_str[17] <= 8'd115; // 's'
            header_str[18] <= 8'd58;  // ':'
            header_str[19] <= 8'd10;  // '\n'
            header_len <= 5'd20;
        end
    endtask
    
    task prepare_result_header;
        input [2:0] m;
        input [2:0] n;
        begin
            // "Result (MxN):\n"
            header_str[0]  <= 8'd82;  // 'R'
            header_str[1]  <= 8'd101; // 'e'
            header_str[2]  <= 8'd115; // 's'
            header_str[3]  <= 8'd117; // 'u'
            header_str[4]  <= 8'd108; // 'l'
            header_str[5]  <= 8'd116; // 't'
            header_str[6]  <= 8'd32;  // ' '
            header_str[7]  <= 8'd40;  // '('
            header_str[8]  <= digit_to_ascii(m);
            header_str[9]  <= 8'd120; // 'x'
            header_str[10] <= digit_to_ascii(n);
            header_str[11] <= 8'd41;  // ')'
            header_str[12] <= 8'd58;  // ':'
            header_str[13] <= 8'd10;  // '\n'
            header_len <= 5'd14;
        end
    endtask
    
    task send_dimension_string;
        input [2:0] m;
        input [2:0] n;
        begin
            // 简化实现：直接发送 "MxN\n"
            // 实际应该发送完整字符串
            tx_data <= digit_to_ascii(m);
            tx_valid <= 1'b1;
        end
    endtask
    
    task send_empty_string;
        begin
            // "Empty\n"
            tx_data <= 8'd69;  // 'E'
            tx_valid <= 1'b1;
        end
    endtask

endmodule