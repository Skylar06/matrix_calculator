module operand_selector (
    input wire clk,
    input wire rst_n,
    input wire start_select,           // 启动选择
    input wire manual_mode,            // 1=手动, 0=随机
    input wire [2:0] op_type,          // 运算类型
    
    // 手动模式输入
    input wire [3:0] user_id_a,
    input wire [3:0] user_id_b,
    input wire user_input_valid,
    
    // 矩阵存储信息
    input wire [2:0] meta_m [0:9],
    input wire [2:0] meta_n [0:9],
    input wire meta_valid [0:9],
    
    // 输出
    output reg [3:0] selected_a,
    output reg [3:0] selected_b,
    output reg select_done,
    output reg select_error            // 选择错误标志
);

    // ========== 运算类型定义 ==========
    localparam OP_TRANSPOSE = 3'b000;   // 只需要一个矩阵
    localparam OP_ADD       = 3'b001;   // 需要维度相同
    localparam OP_SCALAR    = 3'b010;   // 只需要一个矩阵
    localparam OP_MULTIPLY  = 3'b011;   // A的列数=B的行数
    localparam OP_CONV      = 3'b100;   // 卷积核<=被卷积矩阵
    
    // ========== 状态定义 ==========
    localparam IDLE      = 3'd0;
    localparam WAIT_INPUT = 3'd1;
    localparam RANDOM_GEN = 3'd2;
    localparam VALIDATE   = 3'd3;
    localparam DONE       = 3'd4;
    localparam ERROR      = 3'd5;
    
    reg [2:0] state;
    
    // ========== LFSR随机数生成 ==========
    reg [15:0] lfsr;
    wire [3:0] random_id;
    wire lfsr_feedback;
    
    assign lfsr_feedback = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];
    assign random_id = lfsr[3:0] % 10;  // 0-9
    
    // ========== 随机选择计数器 ==========
    reg [3:0] try_cnt;                  // 尝试次数
    localparam MAX_TRIES = 4'd10;       // 最多尝试10次
    reg selecting_a;                     // 正在选择A
    
    // ========== 主状态机 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            selected_a <= 4'd0;
            selected_b <= 4'd0;
            select_done <= 1'b0;
            select_error <= 1'b0;
            lfsr <= 16'hACE1;
            try_cnt <= 4'd0;
            selecting_a <= 1'b1;
        end else begin
            // LFSR持续运行
            lfsr <= {lfsr[14:0], lfsr_feedback};
            
            case (state)
                IDLE: begin
                    select_done <= 1'b0;
                    select_error <= 1'b0;
                    try_cnt <= 4'd0;
                    selecting_a <= 1'b1;
                    
                    if (start_select) begin
                        if (manual_mode)
                            state <= WAIT_INPUT;
                        else
                            state <= RANDOM_GEN;
                    end
                end
                
                WAIT_INPUT: begin
                    if (user_input_valid) begin
                        selected_a <= user_id_a;
                        selected_b <= user_id_b;
                        state <= VALIDATE;
                    end
                end
                
                RANDOM_GEN: begin
                    if (try_cnt >= MAX_TRIES) begin
                        select_error <= 1'b1;
                        state <= ERROR;
                    end else begin
                        // 生成随机ID
                        if (selecting_a) begin
                            if (meta_valid[random_id]) begin
                                selected_a <= random_id;
                                selecting_a <= 1'b0;
                                try_cnt <= 4'd0;
                            end else begin
                                try_cnt <= try_cnt + 1;
                            end
                        end else begin
                            if (meta_valid[random_id]) begin
                                selected_b <= random_id;
                                state <= VALIDATE;
                            end else begin
                                try_cnt <= try_cnt + 1;
                            end
                        end
                    end
                end
                
                VALIDATE: begin
                    // 验证选择的合法性
                    select_error <= 1'b0;
                    
                    // 检查矩阵是否存在
                    if (!meta_valid[selected_a]) begin
                        select_error <= 1'b1;
                        state <= ERROR;
                    end
                    // 单操作数运算
                    else if (op_type == OP_TRANSPOSE || op_type == OP_SCALAR) begin
                        state <= DONE;
                    end
                    // 双操作数运算
                    else if (!meta_valid[selected_b]) begin
                        select_error <= 1'b1;
                        state <= ERROR;
                    end
                    // 加法：维度必须相同
                    else if (op_type == OP_ADD) begin
                        if (meta_m[selected_a] == meta_m[selected_b] &&
                            meta_n[selected_a] == meta_n[selected_b]) begin
                            state <= DONE;
                        end else begin
                            select_error <= 1'b1;
                            state <= ERROR;
                        end
                    end
                    // 矩阵乘法：A的列数 = B的行数
                    else if (op_type == OP_MULTIPLY) begin
                        if (meta_n[selected_a] == meta_m[selected_b]) begin
                            state <= DONE;
                        end else begin
                            select_error <= 1'b1;
                            state <= ERROR;
                        end
                    end
                    // 卷积：B的维度 <= A的维度
                    else if (op_type == OP_CONV) begin
                        if (meta_m[selected_b] <= meta_m[selected_a] &&
                            meta_n[selected_b] <= meta_n[selected_a]) begin
                            state <= DONE;
                        end else begin
                            select_error <= 1'b1;
                            state <= ERROR;
                        end
                    end
                    else begin
                        state <= DONE;
                    end
                end
                
                DONE: begin
                    select_done <= 1'b1;
                    state <= IDLE;
                end
                
                ERROR: begin
                    select_error <= 1'b1;
                    // 保持错误状态,等待重新选择
                    if (start_select)
                        state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule