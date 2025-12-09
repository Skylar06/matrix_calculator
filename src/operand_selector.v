module operand_selector (
    input wire clk,
    input wire rst_n,
    
    // ========== 控制信号 ==========
    input wire start_select,                // 启动选择流程
    input wire manual_mode,                 // 1=手动模式, 0=随机模式
    input wire [2:0] op_type,               // 运算类型
    
    // ========== 手动模式输入 ==========
    input wire [3:0] user_id_a,             // 用户输入的矩阵A的ID
    input wire [3:0] user_id_b,             // 用户输入的矩阵B的ID
    input wire user_input_valid,            // 用户输入有效标志
    
    // ========== 矩阵存储信息（来自storage）==========
    input wire [2:0] meta_m [0:9],          // 各矩阵的行数
    input wire [2:0] meta_n [0:9],          // 各矩阵的列数
    input wire meta_valid [0:9],            // 各矩阵的有效标志
    
    // ========== 输出 ==========
    output reg [3:0] selected_a,            // 选中的矩阵A的ID
    output reg [3:0] selected_b,            // 选中的矩阵B的ID
    output reg select_done,                 // 选择完成标志
    output reg select_error                 // 选择错误标志（不合法）
);

    // ========== 运算类型定义 ==========
    localparam OP_TRANSPOSE = 3'b000;       // 转置（单矩阵）
    localparam OP_ADD       = 3'b001;       // 加法（需要维度相同）
    localparam OP_SCALAR    = 3'b010;       // 标量乘（单矩阵）
    localparam OP_MULTIPLY  = 3'b011;       // 矩阵乘法（A列数=B行数）
    localparam OP_CONV      = 3'b100;       // 卷积（B<=A）
    
    // ========== 状态定义 ==========
    localparam IDLE      = 3'd0;            // 空闲状态
    localparam WAIT_INPUT = 3'd1;           // 等待用户输入
    localparam RANDOM_GEN = 3'd2;           // 随机生成ID
    localparam VALIDATE   = 3'd3;           // 验证合法性
    localparam DONE       = 3'd4;           // 完成
    localparam ERROR      = 3'd5;           // 错误
    
    reg [2:0] state;
    
    // ========== LFSR随机数生成器 ==========
    // 16位线性反馈移位寄存器，生成伪随机序列
    reg [15:0] lfsr;
    wire [3:0] random_id;                   // 生成的随机ID (0-9)
    wire lfsr_feedback;                     // 反馈位
    
    // 反馈多项式：x^16 + x^14 + x^13 + x^11 + 1
    assign lfsr_feedback = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];
    
    // 将16位LFSR映射到0-9范围
    assign random_id = (lfsr[3:0] >= 10) ? (lfsr[3:0] - 10) : lfsr[3:0];
    
    // ========== 随机选择控制变量 ==========
    reg [3:0] try_cnt;                      // 尝试次数计数器
    localparam MAX_TRIES = 4'd10;           // 最多尝试10次
    reg selecting_a;                        // 当前正在选择A（1）还是B（0）
    
    // ========== 临时存储变量 ==========
    // 用于在验证阶段缓存矩阵信息，避免数组动态索引问题
    reg [2:0] temp_m_a, temp_n_a;           // 矩阵A的维度
    reg [2:0] temp_m_b, temp_n_b;           // 矩阵B的维度
    reg temp_valid_a, temp_valid_b;         // 矩阵A/B的有效性
    
    /**************************************************************************
     * 主状态机
     **************************************************************************/
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // ===== 复位初始化 =====
            state <= IDLE;
            selected_a <= 4'd0;
            selected_b <= 4'd0;
            select_done <= 1'b0;
            select_error <= 1'b0;
            lfsr <= 16'hACE1;               // LFSR种子值
            try_cnt <= 4'd0;
            selecting_a <= 1'b1;
            temp_m_a <= 3'd0;
            temp_n_a <= 3'd0;
            temp_m_b <= 3'd0;
            temp_n_b <= 3'd0;
            temp_valid_a <= 1'b0;
            temp_valid_b <= 1'b0;
        end else begin
            // ===== LFSR持续运行（每个时钟周期更新）=====
            lfsr <= {lfsr[14:0], lfsr_feedback};
            
            case (state)
                // ========== 状态0：空闲 ==========
                IDLE: begin
                    select_done <= 1'b0;
                    select_error <= 1'b0;
                    try_cnt <= 4'd0;
                    selecting_a <= 1'b1;    // 先选择矩阵A
                    
                    if (start_select) begin
                        if (manual_mode)
                            state <= WAIT_INPUT;    // 手动模式：等待输入
                        else
                            state <= RANDOM_GEN;    // 随机模式：开始生成
                    end
                end
                
                // ========== 状态1：等待用户输入 ==========
                WAIT_INPUT: begin
                    if (user_input_valid) begin
                        // 用户输入完成，保存ID和元信息
                        selected_a <= user_id_a;
                        selected_b <= user_id_b;
                        temp_valid_a <= meta_valid[user_id_a];
                        temp_valid_b <= meta_valid[user_id_b];
                        temp_m_a <= meta_m[user_id_a];
                        temp_n_a <= meta_n[user_id_a];
                        temp_m_b <= meta_m[user_id_b];
                        temp_n_b <= meta_n[user_id_b];
                        state <= VALIDATE;
                    end
                end
                
                // ========== 状态2：随机生成ID ==========
                RANDOM_GEN: begin
                    // 防止无限循环：超过最大尝试次数则报错
                    if (try_cnt >= MAX_TRIES) begin
                        select_error <= 1'b1;
                        state <= ERROR;
                    end else begin
                        if (selecting_a) begin
                            // ===== 阶段1：选择矩阵A =====
                            temp_valid_a <= meta_valid[random_id];
                            
                            // 检查随机生成的ID是否对应有效矩阵
                            if (meta_valid[random_id]) begin
                                selected_a <= random_id;
                                temp_m_a <= meta_m[random_id];
                                temp_n_a <= meta_n[random_id];
                                selecting_a <= 1'b0;    // 切换到选择B
                                try_cnt <= 4'd0;        // 重置尝试计数
                            end else begin
                                try_cnt <= try_cnt + 1; // 继续尝试
                            end
                        end else begin
                            // ===== 阶段2：选择矩阵B =====
                            temp_valid_b <= meta_valid[random_id];
                            
                            if (meta_valid[random_id]) begin
                                selected_b <= random_id;
                                temp_m_b <= meta_m[random_id];
                                temp_n_b <= meta_n[random_id];
                                state <= VALIDATE;      // 进入验证阶段
                            end else begin
                                try_cnt <= try_cnt + 1;
                            end
                        end
                    end
                end
                
                // ========== 状态3：验证合法性 ==========
                VALIDATE: begin
                    select_error <= 1'b0;
                    
                    // ===== 检查1：矩阵A必须存在 =====
                    if (!temp_valid_a) begin
                        select_error <= 1'b1;
                        state <= ERROR;
                    end
                    // ===== 检查2：单操作数运算（转置/标量乘）=====
                    else if (op_type == OP_TRANSPOSE || op_type == OP_SCALAR) begin
                        state <= DONE;  // 只需要A存在即可
                    end
                    // ===== 检查3：双操作数运算，B必须存在 =====
                    else if (!temp_valid_b) begin
                        select_error <= 1'b1;
                        state <= ERROR;
                    end
                    // ===== 检查4：加法运算 - 维度必须完全相同 =====
                    else if (op_type == OP_ADD) begin
                        if (temp_m_a == temp_m_b && temp_n_a == temp_n_b) begin
                            state <= DONE;  // 维度匹配，合法
                        end else begin
                            select_error <= 1'b1;
                            state <= ERROR;
                        end
                    end
                    // ===== 检查5：矩阵乘法 - A的列数 = B的行数 =====
                    else if (op_type == OP_MULTIPLY) begin
                        if (temp_n_a == temp_m_b) begin
                            state <= DONE;  // 维度兼容，合法
                        end else begin
                            select_error <= 1'b1;
                            state <= ERROR;
                        end
                    end
                    // ===== 检查6：卷积 - 卷积核不能大于被卷积矩阵 =====
                    else if (op_type == OP_CONV) begin
                        if (temp_m_b <= temp_m_a && temp_n_b <= temp_n_a) begin
                            state <= DONE;  // 尺寸合法
                        end else begin
                            select_error <= 1'b1;
                            state <= ERROR;
                        end
                    end
                    // ===== 默认：未知运算类型，通过 =====
                    else begin
                        state <= DONE;
                    end
                end
                
                // ========== 状态4：完成 ==========
                DONE: begin
                    select_done <= 1'b1;    // 标记选择完成
                    state <= IDLE;           // 返回空闲状态
                end
                
                // ========== 状态5：错误 ==========
                ERROR: begin
                    select_error <= 1'b1;    // 保持错误标志
                    // 等待重新启动选择
                    if (start_select)
                        state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule