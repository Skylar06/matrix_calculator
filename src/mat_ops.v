/******************************************************************************
 * 模块名称: mat_ops
 * 功能描述: 矩阵运算模块
 *          - 支持转置、加法、标量乘、矩阵乘法、卷积
 *          - 【修改】接口改为接收完整数组
 ******************************************************************************/
module mat_ops (
    input wire clk,
    input wire rst_n,
    input wire start_op,                    // 开始运算信号
    input wire [2:0] op_sel,                // 运算类型选择
    
    // ========== 【关键修改】改为数组接口 ==========
    input wire [7:0] matrix_a [0:24],       // 矩阵A完整数据（25个元素）
    input wire [7:0] matrix_b [0:24],       // 矩阵B完整数据（25个元素）
    input wire [2:0] dim_a_m,               // 【新增】矩阵A行数
    input wire [2:0] dim_a_n,               // 【新增】矩阵A列数
    input wire [2:0] dim_b_m,               // 【新增】矩阵B行数
    input wire [2:0] dim_b_n,               // 【新增】矩阵B列数
    
    input wire signed [7:0] scalar_k,       // 标量K
    
    output reg op_done,                     // 运算完成标志
    output reg [7:0] result_data,           // 运算结果数据
    output reg [2:0] result_m,              // 【新增】结果矩阵行数
    output reg [2:0] result_n,              // 【新增】结果矩阵列数
    output reg busy_flag,                   // 忙碌标志
    output reg error_flag                   // 错误标志
);

    // ==========================================================================
    // 运算类型定义
    // ==========================================================================
    localparam OP_TRANSPOSE = 3'b000;       // T - 转置
    localparam OP_ADD       = 3'b001;       // A - 加法
    localparam OP_SCALAR    = 3'b010;       // b - 标量乘
    localparam OP_MULTIPLY  = 3'b011;       // C - 矩阵乘法
    localparam OP_CONV      = 3'b100;       // J - 卷积
    
    // ==========================================================================
    // 状态定义
    // ==========================================================================
    localparam IDLE         = 3'd0;
    localparam LOAD_DATA    = 3'd1;
    localparam COMPUTE      = 3'd2;
    localparam WRITE_RESULT = 3'd3;
    localparam DONE         = 3'd4;
    localparam ERROR        = 3'd5;
    
    reg [2:0] state;
    
    // ==========================================================================
    // 矩阵数据缓存（内部工作副本）
    // ==========================================================================
    reg [7:0] mat_a [0:24];                 // 矩阵A工作副本
    reg [7:0] mat_b [0:24];                 // 矩阵B工作副本
    reg signed [15:0] mat_c [0:24];         // 结果矩阵C（16位防止溢出）
    
    // ==========================================================================
    // 结果矩阵维度
    // ==========================================================================
    reg [2:0] dim_c_m, dim_c_n;
    
    // ==========================================================================
    // 计算控制变量
    // ==========================================================================
    reg [4:0] compute_idx;                  // 计算索引
    reg [4:0] write_idx;                    // 写入索引
    reg [4:0] total_elements;               // 结果元素总数
    
    integer i, j, k;                        // 循环变量
    integer idx;
    
    /**************************************************************************
     * 主状态机
     **************************************************************************/
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // ===== 复位所有寄存器 =====
            state <= IDLE;
            op_done <= 1'b0;
            busy_flag <= 1'b0;
            error_flag <= 1'b0;
            result_data <= 8'd0;
            result_m <= 3'd0;
            result_n <= 3'd0;
            compute_idx <= 5'd0;
            write_idx <= 5'd0;
            total_elements <= 5'd0;
            dim_c_m <= 3'd0;
            dim_c_n <= 3'd0;
            
            // ===== 初始化数组 =====
            for (idx = 0; idx < 25; idx = idx + 1) begin
                mat_a[idx] <= 8'd0;
                mat_b[idx] <= 8'd0;
                mat_c[idx] <= 16'd0;
            end
            
        end else begin
            case (state)
                // ========== 状态0：空闲 ==========
                IDLE: begin
                    op_done <= 1'b0;
                    busy_flag <= 1'b0;
                    error_flag <= 1'b0;
                    
                    if (start_op) begin
                        busy_flag <= 1'b1;
                        
                        // 【关键】检查运算合法性并设置结果维度
                        case (op_sel)
                            OP_TRANSPOSE: begin
                                // 转置：C = A^T，维度变为 (n×m)
                                dim_c_m <= dim_a_n;
                                dim_c_n <= dim_a_m;
                                total_elements <= dim_a_m * dim_a_n;
                                state <= LOAD_DATA;
                            end
                            
                            OP_ADD: begin
                                // 加法：要求两矩阵维度相同
                                if (dim_a_m != dim_b_m || dim_a_n != dim_b_n) begin
                                    state <= ERROR;
                                    error_flag <= 1'b1;
                                end else begin
                                    dim_c_m <= dim_a_m;
                                    dim_c_n <= dim_a_n;
                                    total_elements <= dim_a_m * dim_a_n;
                                    state <= LOAD_DATA;
                                end
                            end
                            
                            OP_SCALAR: begin
                                // 标量乘：维度不变
                                dim_c_m <= dim_a_m;
                                dim_c_n <= dim_a_n;
                                total_elements <= dim_a_m * dim_a_n;
                                state <= LOAD_DATA;
                            end
                            
                            OP_MULTIPLY: begin
                                // 矩阵乘法：要求 A的列数 = B的行数
                                if (dim_a_n != dim_b_m) begin
                                    state <= ERROR;
                                    error_flag <= 1'b1;
                                end else begin
                                    dim_c_m <= dim_a_m;
                                    dim_c_n <= dim_b_n;
                                    total_elements <= dim_a_m * dim_b_n;
                                    state <= LOAD_DATA;
                                end
                            end
                            
                            OP_CONV: begin
                                // 卷积：这里简化为有效卷积 (valid convolution)
                                // 假设B是卷积核，A是输入
                                if (dim_a_m < dim_b_m || dim_a_n < dim_b_n) begin
                                    state <= ERROR;
                                    error_flag <= 1'b1;
                                end else begin
                                    dim_c_m <= dim_a_m - dim_b_m + 1;
                                    dim_c_n <= dim_a_n - dim_b_n + 1;
                                    total_elements <= (dim_a_m - dim_b_m + 1) * 
                                                     (dim_a_n - dim_b_n + 1);
                                    state <= LOAD_DATA;
                                end
                            end
                            
                            default: begin
                                state <= ERROR;
                                error_flag <= 1'b1;
                            end
                        endcase
                    end
                end
                
                // ========== 状态1：加载数据 ==========
                LOAD_DATA: begin
                    // 【关键】从输入端口复制数据到内部缓存
                    for (idx = 0; idx < 25; idx = idx + 1) begin
                        mat_a[idx] <= matrix_a[idx];
                        mat_b[idx] <= matrix_b[idx];
                    end
                    
                    compute_idx <= 5'd0;
                    state <= COMPUTE;
                end
                
                // ========== 状态2：计算 ==========
                COMPUTE: begin
                    case (op_sel)
                        // ===== 转置运算 =====
                        OP_TRANSPOSE: begin
                            // C[j][i] = A[i][j]
                            for (i = 0; i < dim_a_m; i = i + 1) begin
                                for (j = 0; j < dim_a_n; j = j + 1) begin
                                    mat_c[j * dim_c_n + i] <= mat_a[i * dim_a_n + j];
                                end
                            end
                            write_idx <= 5'd0;
                            state <= WRITE_RESULT;
                        end
                        
                        // ===== 加法运算 =====
                        OP_ADD: begin
                            // C[i][j] = A[i][j] + B[i][j]
                            for (idx = 0; idx < total_elements; idx = idx + 1) begin
                                mat_c[idx] <= $signed(mat_a[idx]) + $signed(mat_b[idx]);
                            end
                            write_idx <= 5'd0;
                            state <= WRITE_RESULT;
                        end
                        
                        // ===== 标量乘运算 =====
                        OP_SCALAR: begin
                            // C[i][j] = k * A[i][j]
                            for (idx = 0; idx < total_elements; idx = idx + 1) begin
                                mat_c[idx] <= scalar_k * $signed(mat_a[idx]);
                            end
                            write_idx <= 5'd0;
                            state <= WRITE_RESULT;
                        end
                        
                        // ===== 矩阵乘法运算 =====
                        OP_MULTIPLY: begin
                            if (compute_idx < total_elements) begin
                                i = compute_idx / dim_c_n;  // 行索引
                                j = compute_idx % dim_c_n;  // 列索引
                                
                                // 计算 C[i][j] = Σ(A[i][k] * B[k][j])
                                mat_c[compute_idx] <= compute_multiply_elem(i, j);
                                compute_idx <= compute_idx + 1;
                            end else begin
                                write_idx <= 5'd0;
                                state <= WRITE_RESULT;
                            end
                        end
                        
                        // ===== 卷积运算 =====
                        OP_CONV: begin
                            if (compute_idx < total_elements) begin
                                i = compute_idx / dim_c_n;  // 输出行
                                j = compute_idx % dim_c_n;  // 输出列
                                
                                mat_c[compute_idx] <= compute_conv_elem(i, j);
                                compute_idx <= compute_idx + 1;
                            end else begin
                                write_idx <= 5'd0;
                                state <= WRITE_RESULT;
                            end
                        end
                        
                        default: state <= ERROR;
                    endcase
                end
                
                // ========== 状态3：输出结果 ==========
                WRITE_RESULT: begin
                    if (write_idx < total_elements) begin
                        // 输出一个元素（饱和处理防止溢出）
                        if (mat_c[write_idx] > 127)
                            result_data <= 8'd127;
                        else if (mat_c[write_idx] < -128)
                            result_data <= 8'd128;  // -128的补码表示
                        else
                            result_data <= mat_c[write_idx][7:0];
                        
                        write_idx <= write_idx + 1;
                    end else begin
                        result_m <= dim_c_m;
                        result_n <= dim_c_n;
                        state <= DONE;
                    end
                end
                
                // ========== 状态4：完成 ==========
                DONE: begin
                    op_done <= 1'b1;
                    busy_flag <= 1'b0;
                    state <= IDLE;
                end
                
                // ========== 状态5：错误 ==========
                ERROR: begin
                    error_flag <= 1'b1;
                    busy_flag <= 1'b0;
                    if (start_op)
                        state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
    /**************************************************************************
     * 辅助函数：矩阵乘法元素计算
     * 计算 C[row][col] = Σ(A[row][k] * B[k][col])
     **************************************************************************/
    function signed [15:0] compute_multiply_elem;
        input [4:0] row;
        input [4:0] col;
        integer ki;
        reg signed [15:0] sum;
        begin
            sum = 16'sd0;
            for (ki = 0; ki < dim_a_n; ki = ki + 1) begin
                sum = sum + $signed(mat_a[row * dim_a_n + ki]) * 
                           $signed(mat_b[ki * dim_b_n + col]);
            end
            compute_multiply_elem = sum;
        end
    endfunction
    
    /**************************************************************************
     * 辅助函数：卷积元素计算
     * 计算 C[out_row][out_col] = Σ(A[...] * B[...])
     **************************************************************************/
    function signed [15:0] compute_conv_elem;
        input [4:0] out_row;
        input [4:0] out_col;
        integer ki, kj;
        reg signed [15:0] sum;
        begin
            sum = 16'sd0;
            for (ki = 0; ki < dim_b_m; ki = ki + 1) begin
                for (kj = 0; kj < dim_b_n; kj = kj + 1) begin
                    sum = sum + $signed(mat_a[(out_row + ki) * dim_a_n + (out_col + kj)]) *
                               $signed(mat_b[ki * dim_b_n + kj]);
                end
            end
            compute_conv_elem = sum;
        end
    endfunction

endmodule

/******************************************************************************
 * 接口说明
 * 
 * 输入：
 *   matrix_a[0:24]  - 矩阵A完整数据（按行主序存储）
 *   matrix_b[0:24]  - 矩阵B完整数据
 *   dim_a_m/n       - 矩阵A维度
 *   dim_b_m/n       - 矩阵B维度
 *   scalar_k        - 标量乘法的系数
 *   op_sel          - 运算类型
 * 
 * 输出：
 *   result_data     - 结果数据（逐个元素输出）
 *   result_m/n      - 结果矩阵维度
 *   op_done         - 完成标志
 *   busy_flag       - 忙碌标志
 *   error_flag      - 错误标志
 * 
 * 运算类型：
 *   000 - 转置
 *   001 - 加法
 *   010 - 标量乘
 *   011 - 矩阵乘法
 *   100 - 卷积
 ******************************************************************************/