/******************************************************************************
 * 模块名称: config_manager
 * 功能描述: 系统参数集中管理模块
 *          - 统一管理�?有可配置参数（包括标量K�?
 *          - 提供参数广播和查询接�?
 *          - 参数持久化（运行期间保持�?
 ******************************************************************************/
module config_manager (
    input wire clk,
    input wire rst_n,
    
    // ========== 配置命令接口 ==========
    input wire config_valid,                // 配置命令有效标志
    input wire [2:0] config_type,           // 配置类型
    input wire signed [7:0] config_value1,  // 配置�?1
    input wire signed [7:0] config_value2,  // 配置�?2（可选）
    
    // ========== 参数输出（广播到�?要的模块�?==========
    output reg signed [7:0] elem_min,       // 元素�?小�??
    output reg signed [7:0] elem_max,       // 元素�?大�??
    output reg [7:0] countdown_init,        // 倒计时初始�??
    output reg signed [7:0] scalar_k,       // 【新增�?�标量K
    
    // ========== 参数查询接口（按�?读取�?==========
    input wire query_max_per_size,          // 查询请求：每种规格最大个�?
    output reg [3:0] max_per_size_out,      // 查询结果输出
    
    // ========== 状�?�输�? ==========
    output reg config_done,                 // 配置成功标志
    output reg config_error,                // 配置错误标志
    
    // ========== 参数回显（用于UART显示�?==========
    output reg [7:0] show_max_per_size,     // 用于显示的参数�??
    output reg signed [7:0] show_elem_min,
    output reg signed [7:0] show_elem_max,
    output reg [7:0] show_countdown,
    output reg signed [7:0] show_scalar_k   // 【新增�?�标量K回显
);

    // ==========================================================================
    // 参数默认值定�?
    // ==========================================================================
    localparam DEFAULT_MAX_PER_SIZE = 4'd2;      // 默认每种规格2�?
    localparam DEFAULT_ELEM_MIN = 8'sd0;         // 默认�?小�??0
    localparam DEFAULT_ELEM_MAX = 8'sd9;         // 默认�?大�??9
    localparam DEFAULT_COUNTDOWN = 8'd10;        // 默认倒计�?10�?
    localparam DEFAULT_SCALAR_K = 8'sd3;         // 【新增�?�默认标量K=3
    
    // ==========================================================================
    // 参数合法性范围定�?
    // ==========================================================================
    localparam MIN_MAX_PER_SIZE = 4'd1;          // �?�?1�?
    localparam MAX_MAX_PER_SIZE = 4'd10;         // �?�?10�?
    localparam ELEM_ABS_MIN = -8'sd128;          // 元素�?小�??
    localparam ELEM_ABS_MAX = 8'sd127;           // 元素�?大�??
    localparam MIN_COUNTDOWN = 8'd1;             // 倒计时最小�??
    localparam MAX_COUNTDOWN = 8'd99;            // 倒计时最大�??
    localparam SCALAR_K_MIN = -8'sd128;          // 【新增�?�标量K�?小�??
    localparam SCALAR_K_MAX = 8'sd127;           // 【新增�?�标量K�?大�??

    // ==========================================================================
    // 配置类型定义
    // ==========================================================================
    localparam CONFIG_MAX_PER_SIZE = 3'd0;       // 配置�?大个�?
    localparam CONFIG_ELEM_RANGE   = 3'd1;       // 配置元素范围
    localparam CONFIG_COUNTDOWN    = 3'd2;       // 配置倒计�?
    localparam CONFIG_SHOW         = 3'd3;       // 显示当前配置
    localparam CONFIG_SCALAR_K     = 3'd4;       // 【新增�?�配置标量K

    // ==========================================================================
    // 内部寄存器：实际存储参数
    // ==========================================================================
    reg [3:0] max_per_size;                      // 每种规格�?大个数（内部存储�?

    /**************************************************************************
     * 主配置�?�辑
     **************************************************************************/
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // ===== 复位：加载所有默认�?? =====
            max_per_size <= DEFAULT_MAX_PER_SIZE;
            elem_min <= DEFAULT_ELEM_MIN;
            elem_max <= DEFAULT_ELEM_MAX;
            countdown_init <= DEFAULT_COUNTDOWN;
            scalar_k <= DEFAULT_SCALAR_K;        // 【新增�?�初始化标量K
            
            // ===== 初始化输�? =====
            max_per_size_out <= DEFAULT_MAX_PER_SIZE;
            config_done <= 1'b0;
            config_error <= 1'b0;
            
            // ===== 初始化回显参�? =====
            show_max_per_size <= DEFAULT_MAX_PER_SIZE;
            show_elem_min <= DEFAULT_ELEM_MIN;
            show_elem_max <= DEFAULT_ELEM_MAX;
            show_countdown <= DEFAULT_COUNTDOWN;
            show_scalar_k <= DEFAULT_SCALAR_K;   // 【新增�?�初始化K回显
            
        end else begin
            // ===== 默认：清除单周期标志 =====
            config_done <= 1'b0;
            config_error <= 1'b0;
            
            // ===== 处理查询请求 =====
            if (query_max_per_size) begin
                max_per_size_out <= max_per_size;
            end
            
            // ===== 处理配置命令 =====
            if (config_valid) begin
                case (config_type)
                    // ========== 配置1：每种规格最大个�? ==========
                    // 命令格式：CONFIG MAX <value>
                    // 示例：CONFIG MAX 5
                    CONFIG_MAX_PER_SIZE: begin
                        if (config_value1 >= MIN_MAX_PER_SIZE && 
                            config_value1 <= MAX_MAX_PER_SIZE) begin
                            max_per_size <= config_value1[3:0];
                            show_max_per_size <= config_value1;
                            config_done <= 1'b1;
                        end else begin
                            config_error <= 1'b1;  // 超出允许范围 [1, 10]
                        end
                    end
                    
                    // ========== 配置2：元素数值范�? ==========
                    // 命令格式：CONFIG RANGE <min> <max>
                    // 示例：CONFIG RANGE -3 20
                    CONFIG_ELEM_RANGE: begin
                        // 合法性检查：
                        // 1. min <= max
                        // 2. 在有符号8位范围内 [-128, 127]
                        if ($signed(config_value1) >= ELEM_ABS_MIN && 
                            $signed(config_value2) <= ELEM_ABS_MAX &&
                            $signed(config_value1) <= $signed(config_value2)) begin
                            elem_min <= $signed(config_value1);
                            elem_max <= $signed(config_value2);
                            show_elem_min <= $signed(config_value1);
                            show_elem_max <= $signed(config_value2);
                            config_done <= 1'b1;
                        end else begin
                            config_error <= 1'b1;  // 范围非法
                        end
                    end
                    
                    // ========== 配置3：�?�计时初始�?? ==========
                    // 命令格式：CONFIG COUNT <value>
                    // 示例：CONFIG COUNT 15
                    CONFIG_COUNTDOWN: begin
                        if (config_value1 >= MIN_COUNTDOWN && 
                            config_value1 <= MAX_COUNTDOWN) begin
                            countdown_init <= config_value1;
                            show_countdown <= config_value1;
                            config_done <= 1'b1;
                        end else begin
                            config_error <= 1'b1;  // 超出范围 [1, 99]
                        end
                    end
                    
                    // ========== 【新增�?�配�?4：标量K ==========
                    // 命令格式：CONFIG SCALAR <value>
                    // 示例：CONFIG SCALAR 5
                    //       CONFIG SCALAR -3
                    CONFIG_SCALAR_K: begin
                        // 合法性检查：在有符号8位范围内 [-128, 127]
                        if ($signed(config_value1) >= SCALAR_K_MIN && 
                            $signed(config_value1) <= SCALAR_K_MAX) begin
                            scalar_k <= $signed(config_value1);
                            show_scalar_k <= $signed(config_value1);
                            config_done <= 1'b1;
                        end else begin
                            config_error <= 1'b1;  // 超出范围
                        end
                    end
                    
                    // ========== 配置5：显示当前配�? ==========
                    // 命令格式：CONFIG SHOW
                    CONFIG_SHOW: begin
                        // 更新回显参数（实际上已经实时同步�?
                        show_max_per_size <= max_per_size;
                        show_elem_min <= elem_min;
                        show_elem_max <= elem_max;
                        show_countdown <= countdown_init;
                        show_scalar_k <= scalar_k;
                        config_done <= 1'b1;
                    end
                    
                    // ========== 未知配置类型 ==========
                    default: begin
                        config_error <= 1'b1;
                    end
                endcase
            end
        end
    end

endmodule

// ============================================================================
// 使用示例（UART命令）：
//
// 1. 设置每种规格�?大个数为5�?
//    发�?�：CONFIG MAX 5
//
// 2. 设置元素范围�? [-3, 20]�?
//    发�?�：CONFIG RANGE -3 20
//
// 3. 设置倒计时为15秒：
//    发�?�：CONFIG COUNT 15
//
// 4. 【新增�?�设置标量K�?5�?
//    发�?�：CONFIG SCALAR 5
//
// 5. 【新增�?�设置标量K为负数：
//    发�?�：CONFIG SCALAR -3
//
// 6. 显示当前�?有配置：
//    发�?�：CONFIG SHOW
// ============================================================================