/******************************************************************************
 * ???????: mat_ops
 * ????????: ???????????
 *          - ????????????????????????????????
 *          - ???????????????????????
 ******************************************************************************/
module mat_ops (
    input wire clk,
    input wire rst_n,
    input wire start_op,                    // ??????????
    input wire [2:0] op_sel,                // ???????????
    
    // ========== ?????????????????????????????? ==========
    input wire [8*25-1:0] matrix_a_flat,    // ????A?????????25??????8bit??
    input wire [8*25-1:0] matrix_b_flat,    // ????B???????
    input wire [2:0] dim_a_m,               // ????????????A????
    input wire [2:0] dim_a_n,               // ????????????A????
    input wire [2:0] dim_b_m,               // ????????????B????
    input wire [2:0] dim_b_n,               // ????????????B????
    
    input wire signed [7:0] scalar_k,       // ????K
    
    output reg op_done,                     // ?????????
    output reg [7:0] result_data,           // ??????????
    output reg [2:0] result_m,              // ???????????????????
    output reg [2:0] result_n,              // ???????????????????
    output reg busy_flag,                   // ?????
    output reg error_flag                   // ??????
);

    // ==========================================================================
    // ???????????
    // ==========================================================================
    localparam OP_TRANSPOSE = 3'b000;       // T - ???
    localparam OP_ADD       = 3'b001;       // A - ???
    localparam OP_SCALAR    = 3'b010;       // b - ??????
    localparam OP_MULTIPLY  = 3'b011;       // C - ??????
    localparam OP_CONV      = 3'b100;       // J - ????
    
    // ==========================================================================
    // ??????
    // ==========================================================================
    localparam IDLE         = 3'd0;
    localparam LOAD_DATA    = 3'd1;
    localparam COMPUTE      = 3'd2;
    localparam WRITE_RESULT = 3'd3;
    localparam DONE         = 3'd4;
    localparam ERROR        = 3'd5;
    
    reg [2:0] state;
    
    // ==========================================================================
    // ?????????????????????????
    // ==========================================================================
    reg [7:0] mat_a [0:24];                 // ????A????????
    reg [7:0] mat_b [0:24];                 // ????B????????
    reg signed [15:0] mat_c [0:24];         // ???????C??16??????????
    
    // ==========================================================================
    // ??????????
    // ==========================================================================
    reg [2:0] dim_c_m, dim_c_n;
    
    // ==========================================================================
    // ??????????
    // ==========================================================================
    reg [4:0] compute_idx;                  // ????????
    reg [4:0] write_idx;                    // ????????
    reg [4:0] total_elements;               // ??????????
    
    integer i, j, k;                        // ???????
    integer idx;
    
    /**************************************************************************
     * ??????
     **************************************************************************/
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // ===== ????????????? =====
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
            
            // ===== ????????? =====
            for (idx = 0; idx < 25; idx = idx + 1) begin
                mat_a[idx] <= 8'd0;
                mat_b[idx] <= 8'd0;
                mat_c[idx] <= 16'd0;
            end
            
        end else begin
            case (state)
                // ========== ??0?????? ==========
                IDLE: begin
                    op_done <= 1'b0;
                    busy_flag <= 1'b0;
                    error_flag <= 1'b0;
                    
                    if (start_op) begin
                        busy_flag <= 1'b1;
                        
                        // ????????????????????????????
                        case (op_sel)
                            OP_TRANSPOSE: begin
                                // ????C = A^T??????? (n??m)
                                dim_c_m <= dim_a_n;
                                dim_c_n <= dim_a_m;
                                total_elements <= dim_a_m * dim_a_n;
                                state <= LOAD_DATA;
                            end
                            
                            OP_ADD: begin
                                // ????????????????????
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
                                // ?????????????
                                dim_c_m <= dim_a_m;
                                dim_c_n <= dim_a_n;
                                total_elements <= dim_a_m * dim_a_n;
                                state <= LOAD_DATA;
                            end
                            
                            OP_MULTIPLY: begin
                                // ??????????? A?????? = B??????
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
                                // 卷积功能已禁用（节省资源）
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
                
                // ========== ??1?????????? ==========
                LOAD_DATA: begin
                    // ???????????????????????????????????
                    for (idx = 0; idx < 25; idx = idx + 1) begin
                        mat_a[idx] <= matrix_a_flat[idx*8 +: 8];
                        mat_b[idx] <= matrix_b_flat[idx*8 +: 8];
                    end
                    
                    compute_idx <= 5'd0;
                    state <= COMPUTE;
                end
                
                // ========== ??2?????? ==========
                COMPUTE: begin
                    case (op_sel)
                        // ===== ???????????????????????????=====
                        OP_TRANSPOSE: begin
                            if (compute_idx < total_elements) begin
                                i = compute_idx / dim_a_n;  // ???????
                                j = compute_idx % dim_a_n;  // ???????
                                // C[j][i] = A[i][j]
                                mat_c[j * dim_c_n + i] <= mat_a[i * dim_a_n + j];
                                compute_idx <= compute_idx + 1;
                            end else begin
                                write_idx <= 5'd0;
                                state <= WRITE_RESULT;
                            end
                        end
                        
                        // ===== ???????????????????????????=====
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
                        
                        // ===== ??????????????????????????????=====
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
                        
                        // ===== ?????????? =====
                        OP_MULTIPLY: begin
                            if (compute_idx < total_elements) begin
                                i = compute_idx / dim_c_n;  // ??????
                                j = compute_idx % dim_c_n;  // ??????
                                
                                // ???? C[i][j] = ??(A[i][k] * B[k][j])
                                mat_c[compute_idx] <= compute_multiply_elem(i, j);
                                compute_idx <= compute_idx + 1;
                            end else begin
                                write_idx <= 5'd0;
                                state <= WRITE_RESULT;
                            end
                        end
                        
                        // ===== 卷积运算（已禁用）=====
                        OP_CONV: begin
                            // 卷积功能已禁用（节省资源）
                            state <= ERROR;
                            error_flag <= 1'b1;
                        end
                        
                        default: state <= ERROR;
                    endcase
                end
                
                // ========== ??3???????? ==========
                WRITE_RESULT: begin
                    if (write_idx < total_elements) begin
                        // ?????????????????????????
                        if (mat_c[write_idx] > 127)
                            result_data <= 8'd127;
                        else if (mat_c[write_idx] < -128)
                            result_data <= 8'h80;  // -128???????
                        else
                            result_data <= mat_c[write_idx][7:0];
                        
                        write_idx <= write_idx + 1;
                    end else begin
                        result_m <= dim_c_m;
                        result_n <= dim_c_n;
                        state <= DONE;
                    end
                end
                
                // ========== ??4????? ==========
                DONE: begin
                    op_done <= 1'b1;
                    busy_flag <= 1'b0;
                    state <= IDLE;
                end
                
                // ========== ??5?????? ==========
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
     * ??????????????????????
     * ???? C[row][col] = ??(A[row][k] * B[k][col])
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
     * 卷积运算函数（已禁用以节省资源）
     * 功能 C[out_row][out_col] = 求和(A[...] * B[...])
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
 * ??????
 * 
 * ????
 *   matrix_a[0:24]  - ????A?????????????????????
 *   matrix_b[0:24]  - ????B????????
 *   dim_a_m/n       - ????A???
 *   dim_b_m/n       - ????B???
 *   scalar_k        - ????????????
 *   op_sel          - ????????
 * 
 * ?????
 *   result_data     - ???????????????????
 *   result_m/n      - ??????????
 *   op_done         - ?????
 *   busy_flag       - ?????
 *   error_flag      - ??????
 * 
 * ?????????
 *   000 - ???
 *   001 - ???
 *   010 - ??????
 *   011 - ??????
 *   100 - ????
 ******************************************************************************/