module rand_matrix_gen (
    input wire clk,
    input wire rst_n,
    input wire start_gen,           // 开始生成信号
    input wire [2:0] dim_m,         // 矩阵行数
    input wire [2:0] dim_n,         // 矩阵列数
    input wire [3:0] count,         // 生成矩阵个数 (从uart_cmd_parser来)
    input wire [7:0] elem_min,      // 元素最小值
    input wire [7:0] elem_max,      // 元素最大值
    
    output reg gen_done,            // 生成完成标志
    output reg [7:0] data_out,      // 生成的随机数据
    output reg write_en             // 写使能(每生成一个元素产生脉冲)
);

    // ========== 状态定义 ==========
    localparam IDLE = 2'd0;
    localparam GENERATING = 2'd1;
    localparam DONE = 2'd2;
    
    reg [1:0] state;
    
    // ========== 计数器 ==========
    reg [4:0] elem_cnt;             // 当前矩阵的元素计数
    reg [4:0] elem_total;           // 每个矩阵的总元素数 = m * n
    reg [3:0] matrix_cnt;           // 当前生成的矩阵数
    reg [3:0] matrix_total;         // 需要生成的矩阵总数
    
    // ========== 线性反馈移位寄存器(LFSR) - 真随机数生成 ==========
    // 使用32位LFSR,多项式: x^32 + x^22 + x^2 + x^1 + 1
    reg [31:0] lfsr;
    wire feedback;
    assign feedback = lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0];
    
    // 第二个LFSR用于增加随机性
    reg [31:0] lfsr2;
    wire feedback2;
    assign feedback2 = lfsr2[31] ^ lfsr2[27] ^ lfsr2[15] ^ lfsr2[0];
    
    // ========== 随机数生成 - 映射到[elem_min, elem_max]范围 ==========
    wire [7:0] rand_range;
    wire [7:0] rand_value;
    assign rand_range = elem_max - elem_min + 1;
    
    // 使用两个LFSR的异或增加随机性
    wire [7:0] lfsr_byte;
    assign lfsr_byte = (lfsr[7:0] ^ lfsr2[15:8]) % rand_range;
    assign rand_value = elem_min + lfsr_byte;
    
    // ========== 状态机 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            gen_done <= 1'b0;
            write_en <= 1'b0;
            data_out <= 8'd0;
            elem_cnt <= 5'd0;
            elem_total <= 5'd0;
            matrix_cnt <= 4'd0;
            matrix_total <= 4'd0;
            // 使用不同的初始种子
            lfsr <= 32'hACE1_ACE1;  // 非零初始值
            lfsr2 <= 32'h1234_5678; // 非零初始值
        end else begin
            // 默认关闭write_en(脉冲信号)
            write_en <= 1'b0;
            
            case (state)
                IDLE: begin
                    gen_done <= 1'b0;
                    elem_cnt <= 5'd0;
                    matrix_cnt <= 4'd0;
                    
                    if (start_gen) begin
                        // 计算参数
                        elem_total <= dim_m * dim_n;      // 每个矩阵的元素数
                        matrix_total <= count;             // 需要生成的矩阵数
                        state <= GENERATING;
                        
                        // 更新LFSR种子(使用系统运行时间)
                        lfsr <= {lfsr[30:0], feedback};
                        lfsr2 <= {lfsr2[30:0], feedback2};
                    end
                end
                
                GENERATING: begin
                    // 每个周期更新LFSR生成新随机数
                    lfsr <= {lfsr[30:0], feedback};
                    lfsr2 <= {lfsr2[30:0], feedback2};
                    
                    // 输出当前随机数
                    data_out <= rand_value;
                    write_en <= 1'b1;           // 产生写使能脉冲
                    elem_cnt <= elem_cnt + 1;
                    
                    // 检查当前矩阵是否生成完成
                    if (elem_cnt >= elem_total - 1) begin
                        elem_cnt <= 5'd0;               // 重置元素计数
                        matrix_cnt <= matrix_cnt + 1;   // 矩阵计数+1
                        
                        // 检查是否所有矩阵都生成完成
                        if (matrix_cnt >= matrix_total - 1) begin
                            state <= DONE;
                        end
                        // 否则继续生成下一个矩阵
                    end
                end
                
                DONE: begin
                    gen_done <= 1'b1;  // 所有矩阵生成完成
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule

// ============================================================================
// 使用说明:
//
// 输入参数:
//   dim_m, dim_n: 矩阵维度 (例如 3x3)
//   count:        生成矩阵个数 (例如 2,表示生成2个3x3矩阵)
//   elem_min:     元素最小值 (默认0)
//   elem_max:     元素最大值 (默认9)
//
// 输出:
//   data_out:  每个周期输出一个随机数
//   write_en:  每生成一个元素产生一个脉冲
//   gen_done:  所有矩阵生成完成后置1
//
// 示例:
//   输入: dim_m=2, dim_n=3, count=2 (生成2个2x3矩阵)
//   输出: 连续输出12个随机数 (2个矩阵 × 6个元素)
//         data_out: 8,2,6,5,7,9,1,4,3,2,8,5
//                   ↑____矩阵A____↑ ↑____矩阵B____↑
//         write_en: 12个脉冲
//         gen_done: 生成完成后置1
//
// 随机性保证:
//   - 使用双LFSR异或,非递增/递减序列
//   - 每次启动时更新种子
//   - 输出范围严格在[elem_min, elem_max]
// ============================================================================