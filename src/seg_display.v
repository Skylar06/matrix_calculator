module seg_display (
    input wire clk,
    input wire rst_n,
    input wire [1:0] mode_sel,          // 模式选择
    input wire [2:0] op_sel,            // 运算类型选择
    input wire [7:0] countdown_val,     // 倒计时值(秒, 5-15)
    input wire [3:0] matrix_id_out,     // 当前矩阵编号
    
    output reg [3:0] seg_sel,           // 数码管片选 (共阴极,高电平有效)
    output reg [7:0] seg_data           // 数码管段选 (共阴极,高电平点亮)
);

    // ========== 动态扫描参数 ==========
    localparam SCAN_FREQ = 1000;        // 1kHz扫描频率
    localparam CLK_FREQ = 100_000_000;  // 100MHz系统时钟
    localparam SCAN_DIV = CLK_FREQ / (SCAN_FREQ * 4); // 4个数码管
    
    reg [15:0] scan_cnt;                // 扫描分频计数器
    reg [1:0] scan_idx;                 // 当前扫描索引 (0-3)
    
    // ========== 显示内容寄存器 ==========
    // digit[0]=G6(最右)  digit[1]=G1  digit[2]=H1  digit[3]=G2(最左)
    reg [3:0] digit [0:3];
    
    // 用于字母显示的特殊标记
    reg show_op_type;                   // 是否显示运算类型
    
    // ========== 段码查找表 (共阴极,高电平点亮) ==========
    // 段码格式: {DP, G, F, E, D, C, B, A}
    //            小数点                a
    //                            f   b
    //                              g
    //                            e   c
    //                              d   dp
    
    function [7:0] hex_to_seg;
        input [3:0] hex;
        begin
            case (hex)
                4'h0: hex_to_seg = 8'b0011_1111; // 0
                4'h1: hex_to_seg = 8'b0000_0110; // 1
                4'h2: hex_to_seg = 8'b0101_1011; // 2
                4'h3: hex_to_seg = 8'b0100_1111; // 3
                4'h4: hex_to_seg = 8'b0110_0110; // 4
                4'h5: hex_to_seg = 8'b0110_1101; // 5
                4'h6: hex_to_seg = 8'b0111_1101; // 6
                4'h7: hex_to_seg = 8'b0000_0111; // 7
                4'h8: hex_to_seg = 8'b0111_1111; // 8
                4'h9: hex_to_seg = 8'b0110_1111; // 9
                default: hex_to_seg = 8'b0000_0000; // 全灭
            endcase
        end
    endfunction
    
    // 字母/符号段码
    function [7:0] char_to_seg;
        input [7:0] char;
        begin
            case (char)
                "I": char_to_seg = 8'b0000_0110; // I (INPUT模式)
                "G": char_to_seg = 8'b0011_1101; // G (GEN模式)
                "T": char_to_seg = 8'b0111_1000; // T (转置)
                "A": char_to_seg = 8'b0111_0111; // A (加法)
                "b": char_to_seg = 8'b0111_1100; // b (标量乘)
                "C": char_to_seg = 8'b0011_1001; // C (矩阵乘)
                "J": char_to_seg = 8'b0001_1110; // J (卷积)
                " ": char_to_seg = 8'b0000_0000; // 空格(全灭)
                default: char_to_seg = 8'b0000_0000;
            endcase
        end
    endfunction
    
    // ========== 动态扫描计数器 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_cnt <= 16'd0;
            scan_idx <= 2'd0;
        end else begin
            if (scan_cnt >= SCAN_DIV - 1) begin
                scan_cnt <= 16'd0;
                scan_idx <= scan_idx + 1;  // 0→1→2→3→0...
            end else begin
                scan_cnt <= scan_cnt + 1;
            end
        end
    end
    
    // ========== 准备显示内容 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            digit[0] <= 4'd0;
            digit[1] <= 4'd0;
            digit[2] <= 4'd0;
            digit[3] <= 4'd0;
            show_op_type <= 1'b0;
        end else begin
            // 默认不显示运算类型
            show_op_type <= 1'b0;
            
            case (mode_sel)
                // ===== MENU模式 / ERROR模式 =====
                2'b00: begin
                    // 如果有倒计时,显示倒计时 (ERROR状态)
                    if (countdown_val > 0) begin
                        digit[3] <= 4'd15;              // 空格
                        digit[2] <= countdown_val / 10; // 十位
                        digit[1] <= countdown_val % 10; // 个位
                        digit[0] <= 4'd15;              // 空格
                    end
                    // 否则全灭 (正常MENU状态)
                    else begin
                        digit[3] <= 4'd15;
                        digit[2] <= 4'd15;
                        digit[1] <= 4'd15;
                        digit[0] <= 4'd15;
                    end
                end
                
                // ===== INPUT模式: 显示 "I   " (I + 3个空格) =====
                2'b01: begin
                    digit[3] <= 4'd10;  // 10 = 'I' 的标记
                    digit[2] <= 4'd15;  // 空格
                    digit[1] <= 4'd15;  // 空格
                    digit[0] <= 4'd15;  // 空格
                end
                
                // ===== GEN模式: 显示 "G   " (G + 3个空格) =====
                2'b10: begin
                    digit[3] <= 4'd11;  // 11 = 'G' 的标记
                    digit[2] <= 4'd15;  // 空格
                    digit[1] <= 4'd15;  // 空格
                    digit[0] <= 4'd15;  // 空格
                end
                
                // ===== DISPLAY/OPERATION模式 =====
                2'b11: begin
                    // 最右边: 矩阵编号 (G6)
                    digit[0] <= matrix_id_out;
                    
                    // 最左边: 显示运算类型 (G2)
                    digit[3] <= op_sel[2:0];  // 存储op_sel用于后续转换
                    show_op_type <= 1'b1;     // 标记需要显示字母
                    
                    // 中间两位: 空格
                    digit[2] <= 4'd15;
                    digit[1] <= 4'd15;
                end
                
                default: begin
                    digit[3] <= 4'hF;
                    digit[2] <= 4'hF;
                    digit[1] <= 4'hF;
                    digit[0] <= 4'hF;
                end
            endcase
        end
    end
    
    // ========== 输出片选和段选 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            seg_sel <= 4'b0000;
            seg_data <= 8'b0000_0000;
        end else begin
            // ===== 片选信号 (高电平有效) =====
            case (scan_idx)
                2'd0: seg_sel <= 4'b0001;  // digit[0] - G6 (最右)
                2'd1: seg_sel <= 4'b0010;  // digit[1] - G1
                2'd2: seg_sel <= 4'b0100;  // digit[2] - H1
                2'd3: seg_sel <= 4'b1000;  // digit[3] - G2 (最左)
                default: seg_sel <= 4'b0000;
            endcase
            
            // ===== 段选信号 =====
            // 判断当前位置需要显示什么
            if (digit[scan_idx] == 4'd10) begin
                // 显示 'I'
                seg_data <= char_to_seg("I");
            end
            else if (digit[scan_idx] == 4'd11) begin
                // 显示 'G'
                seg_data <= char_to_seg("G");
            end
            else if (digit[scan_idx] == 4'd15) begin
                // 显示空格(全灭)
                seg_data <= char_to_seg(" ");
            end
            // 特殊处理: 最左边数码管显示运算类型字母
            else if (show_op_type && scan_idx == 2'd3) begin
                case (digit[3])
                    3'd0: seg_data <= char_to_seg("T");  // 000 = 转置
                    3'd1: seg_data <= char_to_seg("A");  // 001 = 加法
                    3'd2: seg_data <= char_to_seg("b");  // 010 = 标量乘
                    3'd3: seg_data <= char_to_seg("C");  // 011 = 矩阵乘
                    3'd4: seg_data <= char_to_seg("J");  // 100 = 卷积
                    default: seg_data <= char_to_seg(" ");
                endcase
            end
            // 正常显示数字 (0-9)
            else begin
                seg_data <= hex_to_seg(digit[scan_idx]);
            end
        end
    end

endmodule

// ============================================================================
// 显示示例:
//
// MENU模式:        [空] [空] [空] [空]  (全灭)
//
// INPUT模式:       [I]  [空] [空] [空]  (I表示INPUT)
//
// GEN模式:         [G]  [空] [空] [空]  (G表示GEN)
//
// OPERATION模式 (无倒计时,选择加法,矩阵ID=2):
//                  [A]  [空] [空] [2]
//                   ↑              ↑
//                 加法运算      矩阵编号
//
// OPERATION模式 (倒计时15秒,矩阵ID=2):
//                  [空] [1]  [5]  [2]
//                        ↑    ↑    ↑
//                      倒计时    矩阵编号
//
// ERROR模式 (倒计时10秒):
//                  [空] [1]  [0]  [空]
//                        ↑    ↑
//                      倒计时
//
// 数字编码说明:
//   0-9:  正常数字
//   10:   'I' 字母
//   11:   'G' 字母
//   15:   空格(全灭)
// ============================================================================