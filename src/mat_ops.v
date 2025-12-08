module mat_ops (
    input wire clk,
    input wire rst_n,
    input wire start_op,            // 开始运算信号
    input wire [2:0] op_sel,        // 运算类型选择
    input wire [7:0] matrix_a,      // 矩阵A数据
    input wire [7:0] matrix_b,      // 矩阵B数据
    input wire [7:0] scalar_k,      // 标量K
    
    output reg op_done,             // 运算完成标志
    output reg [7:0] result_data,   // 运算结果数据
    output reg busy_flag,           // 忙碌标志
    output reg error_flag           // 错误标志
);

    // 运算类型定义
    localparam OP_TRANSPOSE = 3'b000;   // T - 转置
    localparam OP_ADD       = 3'b001;   // A - 加法
    localparam OP_SCALAR    = 3'b010;   // b - 标量乘
    localparam OP_MULTIPLY  = 3'b011;   // C - 矩阵乘法
    localparam OP_CONV      = 3'b100;   // J - 卷积
    
    // 状态定义
    localparam IDLE = 3'd0;
    localparam LOAD_DATA = 3'd1;
    localparam COMPUTE = 3'd2;
    localparam WRITE_RESULT = 3'd3;
    localparam DONE = 3'd4;
    localparam ERROR = 3'd5;
    
    reg [2:0] state;
    
    // 矩阵维度信息(从storage模块获取或配置)
    reg [2:0] dim_a_m, dim_a_n;     // 矩阵A维度
    reg [2:0] dim_b_m, dim_b_n;     // 矩阵B维度
    reg [2:0] dim_c_m, dim_c_n;     // 结果矩阵C维度
    
    // 矩阵数据缓存
    reg [7:0] mat_a [0:24];         // 矩阵A缓存(最大5x5=25)
    reg [7:0] mat_b [0:24];         // 矩阵B缓存
    reg [7:0] mat_c [0:24];         // 结果矩阵C
    
    // 计算控制
    reg [4:0] load_idx;             // 加载索引
    reg [4:0] compute_idx;          // 计算索引
    reg [4:0] write_idx;            // 写入索引
    reg [4:0] i, j, k;              // 循环变量
    
    integer idx;
    
    // 主状态机
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            op_done <= 1'b0;
            busy_flag <= 1'b0;
            error_flag <= 1'b0;
            result_data <= 8'd0;
            load_idx <= 5'd0;
            compute_idx <= 5'd0;
            write_idx <= 5'd0;
            
            // 初始化数组
            for (idx = 0; idx < 25; idx = idx + 1) begin
                mat_a[idx] <= 8'd0;
                mat_b[idx] <= 8'd0;
                mat_c[idx] <= 8'd0;
            end
        end else begin
            case (state)
                IDLE: begin
                    op_done <= 1'b0;
                    busy_flag <= 1'b0;
                    error_flag <= 1'b0;
                    
                    if (start_op) begin
                        busy_flag <= 1'b1;
                        load_idx <= 5'd0;
                        
                        // 根据运算类型设置维度(这里简化处理,实际应从storage获取)
                        dim_a_m <= 3'd2;  // 示例:2x3矩阵
                        dim_a_n <= 3'd3;
                        dim_b_m <= 3'd3;  // 示例:3x2矩阵
                        dim_b_n <= 3'd2;
                        
                        // 检查运算合法性
                        case (op_sel)
                            OP_ADD: begin
                                // 加法要求两矩阵维度相同
                                if (dim_a_m != dim_b_m || dim_a_n != dim_b_n) begin
                                    state <= ERROR;
                                    error_flag <= 1'b1;
                                end else begin
                                    dim_c_m <= dim_a_m;
                                    dim_c_n <= dim_a_n;
                                    state <= LOAD_DATA;
                                end
                            end
                            
                            OP_MULTIPLY: begin
                                // 矩阵乘法要求A的列数=B的行数
                                if (dim_a_n != dim_b_m) begin
                                    state <= ERROR;
                                    error_flag <= 1'b1;
                                end else begin
                                    dim_c_m <= dim_a_m;
                                    dim_c_n <= dim_b_n;
                                    state <= LOAD_DATA;
                                end
                            end
                            
                            OP_TRANSPOSE: begin
                                // 转置只需要一个矩阵
                                dim_c_m <= dim_a_n;
                                dim_c_n <= dim_a_m;
                                state <= LOAD_DATA;
                            end
                            
                            OP_SCALAR: begin
                                // 标量乘法
                                dim_c_m <= dim_a_m;
                                dim_c_n <= dim_a_n;
                                state <= LOAD_DATA;
                            end
                            
                            OP_CONV: begin
                                // 卷积(这里简化,实际需要更复杂的处理)
                                state <= LOAD_DATA;
                            end
                            
                            default: begin
                                state <= ERROR;
                                error_flag <= 1'b1;
                            end
                        endcase
                    end
                end
                
                LOAD_DATA: begin
                    // 加载矩阵数据(简化处理,实际应从storage读取)
                    // 这里假设matrix_a和matrix_b每个时钟提供一个元素
                    mat_a[load_idx] <= matrix_a;
                    if (op_sel != OP_TRANSPOSE && op_sel != OP_SCALAR) begin
                        mat_b[load_idx] <= matrix_b;
                    end
                    
                    load_idx <= load_idx + 1;
                    
                    // 判断是否加载完成
                    if (load_idx >= dim_a_m * dim_a_n - 1) begin
                        state <= COMPUTE;
                        compute_idx <= 5'd0;
                        i <= 5'd0;
                        j <= 5'd0;
                        k <= 5'd0;
                    end
                end
                
                COMPUTE: begin
                    case (op_sel)
                        OP_TRANSPOSE: begin
                            // 转置运算: C[j][i] = A[i][j]
                            for (i = 0; i < dim_a_m; i = i + 1) begin
                                for (j = 0; j < dim_a_n; j = j + 1) begin
                                    mat_c[j * dim_a_m + i] <= mat_a[i * dim_a_n + j];
                                end
                            end
                            state <= WRITE_RESULT;
                        end
                        
                        OP_ADD: begin
                            // 加法运算: C[i][j] = A[i][j] + B[i][j]
                            for (i = 0; i < dim_a_m * dim_a_n; i = i + 1) begin
                                mat_c[i] <= mat_a[i] + mat_b[i];
                            end
                            state <= WRITE_RESULT;
                        end
                        
                        OP_SCALAR: begin
                            // 标量乘法: C[i][j] = k * A[i][j]
                            for (i = 0; i < dim_a_m * dim_a_n; i = i + 1) begin
                                mat_c[i] <= scalar_k * mat_a[i];
                            end
                            state <= WRITE_RESULT;
                        end
                        
                        OP_MULTIPLY: begin
                            // 矩阵乘法: C[i][j] = Σ(A[i][k] * B[k][j])
                            // 这里需要多个时钟周期完成
                            if (compute_idx < dim_c_m * dim_c_n) begin
                                i <= compute_idx / dim_c_n;  // 行索引
                                j <= compute_idx % dim_c_n;  // 列索引
                                
                                // 计算C[i][j]
                                mat_c[compute_idx] <= multiply_elem(i, j);
                                compute_idx <= compute_idx + 1;
                            end else begin
                                state <= WRITE_RESULT;
                            end
                        end
                        
                        OP_CONV: begin
                            // 卷积运算(简化实现)
                            state <= WRITE_RESULT;
                        end
                        
                        default: state <= ERROR;
                    endcase
                end
                
                WRITE_RESULT: begin
                    // 输出结果数据
                    if (write_idx < dim_c_m * dim_c_n) begin
                        result_data <= mat_c[write_idx];
                        write_idx <= write_idx + 1;
                    end else begin
                        state <= DONE;
                    end
                end
                
                DONE: begin
                    op_done <= 1'b1;
                    busy_flag <= 1'b0;
                    state <= IDLE;
                end
                
                ERROR: begin
                    error_flag <= 1'b1;
                    busy_flag <= 1'b0;
                    // 保持在错误状态,等待复位或新命令
                    if (start_op)
                        state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
    // 矩阵乘法辅助函数: 计算C[row][col] = Σ(A[row][k] * B[k][col])
    function [7:0] multiply_elem;
        input [4:0] row;
        input [4:0] col;
        integer ki;
        reg [15:0] sum;
        begin
            sum = 16'd0;
            for (ki = 0; ki < dim_a_n; ki = ki + 1) begin
                sum = sum + mat_a[row * dim_a_n + ki] * mat_b[ki * dim_b_n + col];
            end
            multiply_elem = sum[7:0]; // 取低8位(可能溢出,需要注意)
        end
    endfunction

endmodule