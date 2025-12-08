module rand_matrix_gen (
    input wire clk,
    input wire rst_n,
    input wire start_gen,           // 开始生成信号
    input wire [2:0] dim_m,         // 矩阵行数
    input wire [2:0] dim_n,         // 矩阵列数
    input wire [7:0] elem_min,      // 元素最小值
    input wire [7:0] elem_max,      // 元素最大值
    
    output reg gen_done,            // 生成完成标志
    output reg [7:0] data_out       // 生成的随机数据
);

    // 状态定义
    localparam IDLE = 2'd0;
    localparam GENERATING = 2'd1;
    localparam DONE = 2'd2;
    
    reg [1:0] state;
    reg [4:0] elem_cnt;             // 当前生成的元素计数
    reg [4:0] elem_total;           // 总元素数 = m * n
    
    // 线性反馈移位寄存器(LFSR) - 用于生成伪随机数
    // 使用32位LFSR,多项式: x^32 + x^22 + x^2 + x^1 + 1
    reg [31:0] lfsr;
    wire feedback;
    assign feedback = lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0];
    
    // 第二个LFSR用于增加随机性
    reg [31:0] lfsr2;
    wire feedback2;
    assign feedback2 = lfsr2[31] ^ lfsr2[27] ^ lfsr2[15] ^ lfsr2[0];
    
    // 随机数生成 - 将LFSR输出映射到[elem_min, elem_max]范围
    wire [7:0] rand_range;
    wire [7:0] rand_value;
    assign rand_range = elem_max - elem_min + 1;
    
    // 使用两个LFSR的异或增加随机性
    wire [7:0] lfsr_byte;
    assign lfsr_byte = (lfsr[7:0] ^ lfsr2[15:8]) % rand_range;
    assign rand_value = elem_min + lfsr_byte;
    
    // 状态机
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            gen_done <= 1'b0;
            data_out <= 8'd0;
            elem_cnt <= 5'd0;
            elem_total <= 5'd0;
            // 使用不同的初始种子
            lfsr <= 32'hACE1_ACE1;  // 非零初始值
            lfsr2 <= 32'h1234_5678; // 非零初始值
        end else begin
            case (state)
                IDLE: begin
                    gen_done <= 1'b0;
                    elem_cnt <= 5'd0;
                    
                    if (start_gen) begin
                        // 计算总元素数
                        elem_total <= dim_m * dim_n;
                        state <= GENERATING;
                        
                        // 使用当前时间戳(系统运行周期)作为种子的一部分
                        lfsr <= {lfsr[30:0], feedback};
                        lfsr2 <= {lfsr2[30:0], feedback2};
                    end
                end
                
                GENERATING: begin
                    // 更新LFSR以生成新的随机数
                    lfsr <= {lfsr[30:0], feedback};
                    lfsr2 <= {lfsr2[30:0], feedback2};
                    
                    // 输出当前随机数
                    data_out <= rand_value;
                    elem_cnt <= elem_cnt + 1;
                    
                    // 检查是否生成完所有元素
                    if (elem_cnt >= elem_total - 1) begin
                        state <= DONE;
                    end
                end
                
                DONE: begin
                    gen_done <= 1'b1;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule