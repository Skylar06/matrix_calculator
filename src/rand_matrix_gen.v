module rand_matrix_gen (
    input wire clk,
    input wire rst_n,
    
    // ========== 【新增】配置参数输入 ==========
    input wire signed [7:0] elem_min_cfg,       // 来自config_manager
    input wire signed [7:0] elem_max_cfg,       // 来自config_manager
    
    // ========== 控制接口 ==========
    input wire start_gen,
    input wire [2:0] dim_m,
    input wire [2:0] dim_n,
    input wire [3:0] count,
    
    // ========== 输出接口 ==========
    output reg gen_done,
    output reg [7:0] data_out,
    output reg write_en
);

    // ==========================================================================
    // 状态定义
    // ==========================================================================
    localparam IDLE = 2'd0;
    localparam GENERATING = 2'd1;
    localparam DONE = 2'd2;
    
    reg [1:0] state;
    
    // ==========================================================================
    // LFSR随机数生成器
    // ==========================================================================
    reg [15:0] lfsr;
    wire lfsr_feedback;
    assign lfsr_feedback = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];
    
    // ==========================================================================
    // 计数器
    // ==========================================================================
    reg [3:0] matrix_count;
    reg [4:0] elem_count;
    reg [4:0] elem_total;
    
    /**************************************************************************
     * 主状态机
     **************************************************************************/
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            lfsr <= 16'hACE1;
            matrix_count <= 4'd0;
            elem_count <= 5'd0;
            elem_total <= 5'd0;
            gen_done <= 1'b0;
            data_out <= 8'd0;
            write_en <= 1'b0;
        end else begin
            // ===== LFSR持续更新 =====
            lfsr <= {lfsr[14:0], lfsr_feedback};
            
            gen_done <= 1'b0;
            write_en <= 1'b0;
            
            case (state)
                IDLE: begin
                    if (start_gen) begin
                        matrix_count <= 4'd0;
                        elem_count <= 5'd0;
                        elem_total <= dim_m * dim_n;
                        state <= GENERATING;
                    end
                end
                
                GENERATING: begin
                    if (elem_count < elem_total) begin
                        // ===== 【关键修改】使用config_manager的参数生成随机数 =====
                        reg signed [15:0] range;
                        reg signed [15:0] random_value;
                        reg signed [15:0] lfsr_signed;
                        
                        // 计算范围：[elem_min_cfg, elem_max_cfg]
                        range = elem_max_cfg - elem_min_cfg + 1;
                        lfsr_signed = $signed({1'b0, lfsr[14:0]});  // 转有符号
                        
                        // 确保正数
                        if (lfsr_signed < 0) begin
                            lfsr_signed = -lfsr_signed;
                        end
                        
                        // 映射到目标范围
                        random_value = elem_min_cfg + (lfsr_signed % range);
                        
                        // 边界保护
                        if (random_value > elem_max_cfg) begin
                            random_value = elem_max_cfg;
                        end
                        if (random_value < elem_min_cfg) begin
                            random_value = elem_min_cfg;
                        end
                        
                        data_out <= random_value[7:0];
                        write_en <= 1'b1;
                        elem_count <= elem_count + 1;
                    end else begin
                        // ===== 当前矩阵生成完成 =====
                        matrix_count <= matrix_count + 1;
                        
                        if (matrix_count >= count - 1) begin
                            state <= DONE;
                        end else begin
                            elem_count <= 5'd0;  // 重置计数器，生成下一个矩阵
                        end
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