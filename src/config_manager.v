/******************************************************************************
 * 模块名称: config_manager
 * 功能描述: 系统参数集中管理模块
 *          - 统一管理所有可配置参数
 *          - 提供参数广播和查询接口
 *          - 参数持久化（运行期间保持）
 ******************************************************************************/
module config_manager (
    input wire clk,
    input wire rst_n,
    
    // ========== 配置命令接口 ==========
    input wire config_valid,                // 配置命令有效标志
    input wire [2:0] config_type,           // 配置类型
    input wire signed [7:0] config_value1,  // 配置值1
    input wire signed [7:0] config_value2,  // 配置值2（可选）
    
    // ========== 参数输出（广播到需要的模块）==========
    output reg signed [7:0] elem_min,       // 元素最小值
    output reg signed [7:0] elem_max,       // 元素最大值
    output reg [7:0] countdown_init,        // 倒计时初始值
    
    // ========== 参数查询接口（按需读取）==========
    input wire query_max_per_size,          // 查询请求：每种规格最大个数
    output reg [3:0] max_per_size_out,      // 查询结果输出
    
    // ========== 状态输出 ==========
    output reg config_done,                 // 配置成功标志
    output reg config_error,                // 配置错误标志
    
    // ========== 参数回显（用于UART显示）==========
    output reg [7:0] show_max_per_size,     // 用于显示的参数值
    output reg signed [7:0] show_elem_min,
    output reg signed [7:0] show_elem_max,
    output reg [7:0] show_countdown
);

    // ==========================================================================
    // 参数默认值定义
    // ==========================================================================
    localparam DEFAULT_MAX_PER_SIZE = 4'd2;
    localparam DEFAULT_ELEM_MIN = 8'sd0;
    localparam DEFAULT_ELEM_MAX = 8'sd9;
    localparam DEFAULT_COUNTDOWN = 8'd10;
    
    // ==========================================================================
    // 参数合法性范围定义
    // ==========================================================================
    localparam MIN_MAX_PER_SIZE = 4'd1;
    localparam MAX_MAX_PER_SIZE = 4'd10;
    localparam ELEM_ABS_MIN = 8'sd-128;
    localparam ELEM_ABS_MAX = 8'sd127;
    localparam MIN_COUNTDOWN = 8'd1;
    localparam MAX_COUNTDOWN = 8'd99;

    // ==========================================================================
    // 配置类型定义
    // ==========================================================================
    localparam CONFIG_MAX_PER_SIZE = 3'd0;
    localparam CONFIG_ELEM_RANGE   = 3'd1;
    localparam CONFIG_COUNTDOWN    = 3'd2;
    localparam CONFIG_SHOW         = 3'd3;

    // ==========================================================================
    // 内部寄存器
    // ==========================================================================
    reg [3:0] max_per_size;

    /**************************************************************************
     * 主配置逻辑
     **************************************************************************/
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // ===== 复位：加载默认值 =====
            max_per_size <= DEFAULT_MAX_PER_SIZE;
            elem_min <= DEFAULT_ELEM_MIN;
            elem_max <= DEFAULT_ELEM_MAX;
            countdown_init <= DEFAULT_COUNTDOWN;
            
            max_per_size_out <= DEFAULT_MAX_PER_SIZE;
            config_done <= 1'b0;
            config_error <= 1'b0;
            
            show_max_per_size <= DEFAULT_MAX_PER_SIZE;
            show_elem_min <= DEFAULT_ELEM_MIN;
            show_elem_max <= DEFAULT_ELEM_MAX;
            show_countdown <= DEFAULT_COUNTDOWN;
            
        end else begin
            // ===== 默认清除单周期标志 =====
            config_done <= 1'b0;
            config_error <= 1'b0;
            
            // ===== 处理查询请求 =====
            if (query_max_per_size) begin
                max_per_size_out <= max_per_size;
            end
            
            // ===== 处理配置命令 =====
            if (config_valid) begin
                case (config_type)
                    CONFIG_MAX_PER_SIZE: begin
                        if (config_value1 >= MIN_MAX_PER_SIZE && 
                            config_value1 <= MAX_MAX_PER_SIZE) begin
                            max_per_size <= config_value1[3:0];
                            show_max_per_size <= config_value1;
                            config_done <= 1'b1;
                        end else begin
                            config_error <= 1'b1;
                        end
                    end
                    
                    CONFIG_ELEM_RANGE: begin
                        if ($signed(config_value1) >= ELEM_ABS_MIN && 
                            $signed(config_value2) <= ELEM_ABS_MAX &&
                            $signed(config_value1) <= $signed(config_value2)) begin
                            elem_min <= $signed(config_value1);
                            elem_max <= $signed(config_value2);
                            show_elem_min <= $signed(config_value1);
                            show_elem_max <= $signed(config_value2);
                            config_done <= 1'b1;
                        end else begin
                            config_error <= 1'b1;
                        end
                    end
                    
                    CONFIG_COUNTDOWN: begin
                        if (config_value1 >= MIN_COUNTDOWN && 
                            config_value1 <= MAX_COUNTDOWN) begin
                            countdown_init <= config_value1;
                            show_countdown <= config_value1;
                            config_done <= 1'b1;
                        end else begin
                            config_error <= 1'b1;
                        end
                    end
                    
                    CONFIG_SHOW: begin
                        show_max_per_size <= max_per_size;
                        show_elem_min <= elem_min;
                        show_elem_max <= elem_max;
                        show_countdown <= countdown_init;
                        config_done <= 1'b1;
                    end
                    
                    default: begin
                        config_error <= 1'b1;
                    end
                endcase
            end
        end
    end

endmodule