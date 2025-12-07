module seg_display (
    input wire clk,
    input wire rst_n,
    input wire [1:0] mode_sel,          // 模式选择
    input wire [2:0] op_sel,            // 运算类型选择
    input wire [7:0] countdown_val,     // 倒计时值(秒)
    input wire [3:0] matrix_id_out,     // 当前矩阵编号
    
    output reg [3:0] seg_sel,           // 数码管片选(低电平有效,但我们需要输出高电平)
    output reg [7:0] seg_data           // 数码管段选(共阴极,高电平点亮)
);

    // 分频计数器 - 用于数码管动态扫描(约1kHz刷新率)
    localparam SCAN_FREQ = 1000;        // 1kHz扫描频率
    localparam CLK_FREQ = 100_000_000;  // 100MHz系统时钟
    localparam SCAN_DIV = CLK_FREQ / (SCAN_FREQ * 4); // 除以4是因为有4个数码管
    
    reg [15:0] scan_cnt;
    reg [1:0] scan_idx;                 // 当前扫描的数码管索引(0-3)
    
    // 当前要显示的4位数字
    reg [3:0] digit [0:3];              // digit[0]最右边, digit[3]最左边
    
    // 数码管段码表(共阴极,高电平点亮)
    // 段码格式: {DP, G, F, E, D, C, B, A}
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
                4'hA: hex_to_seg = 8'b0111_0111; // A
                4'hB: hex_to_seg = 8'b0111_1100; // b
                4'hC: hex_to_seg = 8'b0011_1001; // C
                4'hD: hex_to_seg = 8'b0101_1110; // d
                4'hE: hex_to_seg = 8'b0111_1001; // E
                4'hF: hex_to_seg = 8'b0111_0001; // F
                default: hex_to_seg = 8'b0000_0000; // 全灭
            endcase
        end
    endfunction
    
    // 字母显示函数
    function [7:0] char_to_seg;
        input [7:0] char;
        begin
            case (char)
                "T": char_to_seg = 8'b0111_1000; // T (转置)
                "A": char_to_seg = 8'b0111_0111; // A (加法)
                "b": char_to_seg = 8'b0111_1100; // b (标量乘)
                "C": char_to_seg = 8'b0011_1001; // C (矩阵乘)
                "J": char_to_seg = 8'b0001_1110; // J (卷积)
                "-": char_to_seg = 8'b0100_0000; // 横杠
                " ": char_to_seg = 8'b0000_0000; // 空格
                default: char_to_seg = 8'b0000_0000;
            endcase
        end
    endfunction
    
    // 动态扫描计数器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_cnt <= 16'd0;
            scan_idx <= 2'd0;
        end else begin
            if (scan_cnt >= SCAN_DIV - 1) begin
                scan_cnt <= 16'd0;
                scan_idx <= scan_idx + 1;
            end else begin
                scan_cnt <= scan_cnt + 1;
            end
        end
    end
    
    // 根据当前状态准备要显示的内容
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            digit[0] <= 4'd0;
            digit[1] <= 4'd0;
            digit[2] <= 4'd0;
            digit[3] <= 4'd0;
        end else begin
            // 根据模式选择显示内容
            case (mode_sel)
                2'b00: begin // IDLE/MENU模式
                    digit[3] <= 4'd0;
                    digit[2] <= 4'd0;
                    digit[1] <= 4'd0;
                    digit[0] <= 4'd0;
                end
                
                2'b01: begin // INPUT模式 - 显示 "----"
                    digit[3] <= 4'hF; // 显示横杠标记
                    digit[2] <= 4'hF;
                    digit[1] <= 4'hF;
                    digit[0] <= 4'hF;
                end
                
                2'b10: begin // GEN模式 - 显示 "GEN "
                    digit[3] <= 4'hF; // 特殊标记,后面转换为字母
                    digit[2] <= 4'hF;
                    digit[1] <= 4'hF;
                    digit[0] <= 4'hF;
                end
                
                2'b11: begin // DISPLAY/OPERATION模式
                    // 如果countdown_val > 0, 显示倒计时
                    if (countdown_val > 0) begin
                        // 显示倒计时(最大15秒,用两位数显示)
                        digit[3] <= 4'd0;
                        digit[2] <= 4'd0;
                        digit[1] <= countdown_val / 10;
                        digit[0] <= countdown_val % 10;
                    end 
                    // 否则根据op_sel显示运算类型
                    else begin
                        // 左边3个数码管显示运算符号,最右边显示矩阵编号
                        digit[0] <= matrix_id_out; // 矩阵编号
                        digit[1] <= 4'hF; // 空格
                        digit[2] <= 4'hF; // 空格
                        
                        // 最左边显示运算类型
                        case (op_sel)
                            3'b000: digit[3] <= 4'hA; // T(转置) - 用特殊编码
                            3'b001: digit[3] <= 4'hB; // A(加法)
                            3'b010: digit[3] <= 4'hC; // b(标量乘)
                            3'b011: digit[3] <= 4'hD; // C(矩阵乘)
                            3'b100: digit[3] <= 4'hE; // J(卷积)
                            default: digit[3] <= 4'hF; // 空格
                        endcase
                    end
                end
                
                default: begin
                    digit[3] <= 4'd0;
                    digit[2] <= 4'd0;
                    digit[1] <= 4'd0;
                    digit[0] <= 4'd0;
                end
            endcase
        end
    end
    
    // 输出片选和段选信号
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            seg_sel <= 4'b0000;
            seg_data <= 8'b0000_0000;
        end else begin
            // 片选信号(高电平有效,因为经过三极管驱动)
            case (scan_idx)
                2'd0: seg_sel <= 4'b0001; // 最右边数码管
                2'd1: seg_sel <= 4'b0010;
                2'd2: seg_sel <= 4'b0100;
                2'd3: seg_sel <= 4'b1000; // 最左边数码管
                default: seg_sel <= 4'b0000;
            endcase
            
            // 段选信号 - 根据当前扫描的数码管和要显示的内容
            // 特殊处理运算符号显示
            if (mode_sel == 2'b11 && countdown_val == 0 && scan_idx == 2'd3) begin
                // 显示运算类型字母
                case (op_sel)
                    3'b000: seg_data <= char_to_seg("T"); // 转置
                    3'b001: seg_data <= char_to_seg("A"); // 加法
                    3'b010: seg_data <= char_to_seg("b"); // 标量乘
                    3'b011: seg_data <= char_to_seg("C"); // 矩阵乘
                    3'b100: seg_data <= char_to_seg("J"); // 卷积
                    default: seg_data <= 8'b0000_0000;
                endcase
            end
            else if (digit[scan_idx] == 4'hF) begin
                // 显示横杠或空格
                seg_data <= char_to_seg("-");
            end
            else begin
                // 正常显示数字
                seg_data <= hex_to_seg(digit[scan_idx]);
            end
        end
    end

endmodule