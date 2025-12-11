/******************************************************************************
 * 模块名称: mat_ops
 * 功能描述: 矩阵运算核心
 *          - 支持转置/加法/标量乘/矩阵乘/卷积（卷积未实现占位）
 *          - 输出结果矩阵及忙/完成/错误标志
 ******************************************************************************/
module mat_ops (
    input wire clk,
    input wire rst_n,
    input wire start_op,                    // 启动运算
    input wire [2:0] op_sel,                // 运算类型选择
    
    // ========== 输入矩阵（扁平化向量）==========
    input wire [8*25-1:0] matrix_a_flat,    // 矩阵A，最多25个元素，每个8bit
    input wire [8*25-1:0] matrix_b_flat,    // 矩阵B，同上
    input wire [2:0] dim_a_m,               // 矩阵A行数
    input wire [2:0] dim_a_n,               // 矩阵A列数
    input wire [2:0] dim_b_m,               // 矩阵B行数
    input wire [2:0] dim_b_n,               // 矩阵B列数
    
    input wire signed [7:0] scalar_k,       // 标量K
    
    output reg op_done,                     // 运算完成脉冲
    output reg [7:0] result_data,           // 结果数据流
    output reg [2:0] result_m,              // 结果矩阵行数
    output reg [2:0] result_n,              // 结果矩阵列数
    output reg busy_flag,                   // 忙标志
    output reg error_flag                   // 错误标志
);

    // ==========================================================================
    // 运算类型编码
    // ==========================================================================
    localparam OP_TRANSPOSE = 3'b000;       // T - 转置
    localparam OP_ADD       = 3'b001;       // A - 加法
    localparam OP_SCALAR    = 3'b010;       // b - 标量乘
    localparam OP_MULTIPLY  = 3'b011;       // C - 矩阵乘
    localparam OP_CONV      = 3'b100;       // J - 卷积（占位，未实现）
    
    // ==========================================================================
    // 状态机
    // ==========================================================================
    localparam IDLE         = 3'd0;
    localparam LOAD_DATA    = 3'd1;
    localparam COMPUTE      = 3'd2;
    localparam WRITE_RESULT = 3'd3;
    localparam DONE         = 3'd4;
    localparam ERROR        = 3'd5;
    
    reg [2:0] state;
    
    // ==========================================================================
    // 内部存储的展开矩阵
    // ==========================================================================
    reg [7:0] mat_a [0:24];                 // 矩阵A（8bit）
    reg [7:0] mat_b [0:24];                 // 矩阵B（8bit）
    reg signed [15:0] mat_c [0:24];         // 结果矩阵C（16bit中间值）
    
    // ==========================================================================
    // 结果尺寸
    // ==========================================================================
    reg [2:0] dim_c_m, dim_c_n;
    
    // ==========================================================================
    // 计数索引
    // ==========================================================================
    reg [4:0] compute_idx;                  // 计算用索引
    reg [4:0] write_idx;                    // 输出用索引
    reg [4:0] total_elements;               // 元素总数
    
    integer i, j, k;                        // 循环变量
    integer idx;
    
    /**************************************************************************
     * 主状态机
     **************************************************************************/
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // ===== 复位默认值 =====
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
            
            // ===== 清零矩阵缓存 =====
            for (idx = 0; idx < 25; idx = idx + 1) begin
                mat_a[idx] <= 8'd0;
                mat_b[idx] <= 8'd0;
                mat_c[idx] <= 16'd0;
            end
            
        end else begin
            case (state)
                // ========== 状态0：等待启动 ==========
                IDLE: begin
                    op_done <= 1'b0;
                    busy_flag <= 1'b0;
                    error_flag <= 1'b0;
                    
                    if (start_op) begin
                        busy_flag <= 1'b1;
                        
                        // 预先判定输出尺寸与合法性
                        case (op_sel)
                            OP_TRANSPOSE: begin
                                // 输出 C = A^T （n x m）
                                dim_c_m <= dim_a_n;
                                dim_c_n <= dim_a_m;
                                total_elements <= dim_a_m * dim_a_n;
                                state <= LOAD_DATA;
                            end
                            
                            OP_ADD: begin
                                // 维度必须一致
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
                                // 标量乘
                                dim_c_m <= dim_a_m;
                                dim_c_n <= dim_a_n;
                                total_elements <= dim_a_m * dim_a_n;
                                state <= LOAD_DATA;
                            end
                            
                            OP_MULTIPLY: begin
                                // 矩阵乘要求 A列数 = B行数
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
                                // 卷积尚未实现，暂时报错占位
                                state <= ERROR;
                                error_flag <= 1'b1;
                            end
                            
                            default: begin
                                state <= ERROR;
                                error_flag <= 1'b1;
                            end
                        endcase
                    end
                end
                
                // ========== 状态1：装载输入数据 ==========
                LOAD_DATA: begin
                    // 将扁平化向量拆到数组
                    for (idx = 0; idx < 25; idx = idx + 1) begin
                        mat_a[idx] <= matrix_a_flat[idx*8 +: 8];
                        mat_b[idx] <= matrix_b_flat[idx*8 +: 8];
                    end
                    
                    compute_idx <= 5'd0;
                    state <= COMPUTE;
                end
                
                // ========== 状态2：计算 ==========
                COMPUTE: begin
                    case (op_sel)
                        // ===== 转置 =====
                        OP_TRANSPOSE: begin
                            if (compute_idx < total_elements) begin
                                i = compute_idx / dim_a_n;  // 行
                                j = compute_idx % dim_a_n;  // 列
                                // C[j][i] = A[i][j]
                                mat_c[j * dim_c_n + i] <= mat_a[i * dim_a_n + j];
                                compute_idx <= compute_idx + 1;
                            end else begin
                                write_idx <= 5'd0;
                                state <= WRITE_RESULT;
                            end
                        end
                        
                        // ===== 加法 =====
                        OP_ADD: begin
                            if (compute_idx < total_elements) begin
                                // C[i][j] = A[i][j] + B[i][j]
                                mat_c[compute_idx] <= $signed(mat_a[compute_idx]) + $signed(mat_b[compute_idx]);
                                compute_idx <= compute_idx + 1;
                            end else begin
                                write_idx <= 5'd0;
                                state <= WRITE_RESULT;
                            end
                        end
                        
                        // ===== 标量乘 =====
                        OP_SCALAR: begin
                            if (compute_idx < total_elements) begin
                                // C[i][j] = k * A[i][j]
                                mat_c[compute_idx] <= scalar_k * $signed(mat_a[compute_idx]);
                                compute_idx <= compute_idx + 1;
                            end else begin
                                write_idx <= 5'd0;
                                state <= WRITE_RESULT;
                            end
                        end
                        
                        // ===== 矩阵乘 =====
                        OP_MULTIPLY: begin
                            if (compute_idx < total_elements) begin
                                i = compute_idx / dim_c_n;  // 行
                                j = compute_idx % dim_c_n;  // 列
                                
                                // 计算 C[i][j] = Σ(A[i][k] * B[k][j])
                                mat_c[compute_idx] <= compute_multiply_elem(i, j);
                                compute_idx <= compute_idx + 1;
                            end else begin
                                write_idx <= 5'd0;
                                state <= WRITE_RESULT;
                            end
                        end
                        
                        // ===== 卷积占位（未实现）=====
                        OP_CONV: begin
                            // 未实现：占位直接报错
                            state <= ERROR;
                            error_flag <= 1'b1;
                        end
                        
                        default: state <= ERROR;
                    endcase
                end
                
                // ========== 状态3：输出结果流 ==========
                WRITE_RESULT: begin
                    if (write_idx < total_elements) begin
                        // 饱和到 8bit 输出
                        if (mat_c[write_idx] > 127)
                            result_data <= 8'd127;
                        else if (mat_c[write_idx] < -128)
                            result_data <= 8'h80;  // -128
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
     * 矩阵乘法单元计算
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
     * �������㺯�����ѽ����Խ�ʡ��Դ��
     * ���� C[out_row][out_col] = ���(A[...] * B[...])
     **************************************************************************/
    // function signed [15:0] compute_conv_elem;
    //     input [4:0] out_row;
    //     input [4:0] out_col;
    //     integer ki, kj;
    //     reg signed [15:0] sum;
    //     begin
    //         sum = 16'sd0;
    //         for (ki = 0; ki < dim_b_m; ki = ki + 1) begin
    //             for (kj = 0; kj < dim_b_n; kj = kj + 1) begin
    //                 sum = sum + $signed(mat_a[(out_row + ki) * dim_a_n + (out_col + kj)]) *
    //                            $signed(mat_b[ki * dim_b_n + kj]);
    //             end
    //         end
    //         compute_conv_elem = sum;
    //     end
    // endfunction

endmodule

/******************************************************************************
 * 端口说明
 * 
 * 输入
 *   matrix_a[0:24]  - 矩阵A，最多5x5共25个元素
 *   matrix_b[0:24]  - 矩阵B，同上
 *   dim_a_m/n       - 矩阵A的维度
 *   dim_b_m/n       - 矩阵B的维度
 *   scalar_k        - 标量乘的系数
 *   op_sel          - 运算选择
 * 
 * 输出
 *   result_data     - 结果矩阵数据（按元素流式输出）
 *   result_m/n      - 结果矩阵维度
 *   op_done         - 运算完成脉冲
 *   busy_flag       - 忙标志
 *   error_flag      - 错误标志
 * 
 * 运算编码
 *   000 - 转置
 *   001 - 加法
 *   010 - 标量乘
 *   011 - 矩阵乘
 *   100 - 卷积（未实现）
 ******************************************************************************/