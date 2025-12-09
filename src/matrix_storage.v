module matrix_storage (
    input wire clk,
    input wire rst_n,
    
    // ========== 写入接口 ==========
    input wire write_en,                    // 写使能
    input wire [2:0] dim_m,                 // 行数 (1-5)
    input wire [2:0] dim_n,                 // 列数 (1-5)
    input wire [7:0] data_in,               // 输入数据
    input wire [3:0] matrix_id_in,          // 矩阵ID输入
    
    // ========== 运算结果存储接口 ==========
    input wire [7:0] result_data,           // 运算结果数据
    input wire op_done,                     // 运算完成标志
    
    // ========== 控制信号 ==========
    input wire start_input,                 // 开始输入模式
    input wire start_disp,                  // 开始显示模式
    
    // ========== 运算数加载接口 ==========
    input wire load_operands,               // 加载运算数到缓冲区
    input wire [3:0] operand_a_id,          // 运算数A的ID
    input wire [3:0] operand_b_id,          // 运算数B的ID
    
    // ========== 列表查询接口 ==========
    input wire req_list_info,               // 请求列表信息
    
    // ========== 读取/显示接口 ==========
    output reg [7:0] data_out,              // 输出数据
    output reg [3:0] matrix_id_out,         // 当前读取的矩阵ID
    output reg meta_info_valid,             // 元信息有效标志
    output reg error_flag,                  // 错误标志
    
    // ========== 运算数缓冲区 ==========
    output reg [7:0] matrix_a [0:24],       // 运算数A缓冲区
    output reg [7:0] matrix_b [0:24],       // 运算数B缓冲区
    output reg [2:0] matrix_a_m,            // 运算数A行数
    output reg [2:0] matrix_a_n,            // 运算数A列数
    output reg [2:0] matrix_b_m,            // 运算数B行数
    output reg [2:0] matrix_b_n,            // 运算数B列数
    
    // ========== 列表信息输出 ==========
    output reg [2:0] list_m [0:9],          // 各矩阵行数
    output reg [2:0] list_n [0:9],          // 各矩阵列数
    output reg list_valid [0:9]             // 各矩阵有效标志
);

    // ========== 参数定义 ==========
    localparam MAX_MATRICES = 10;           // 最多存储10个矩阵
    localparam MAX_ELEMENTS = 25;           // 每个矩阵最大25个元素 (5x5)
    localparam MAX_PER_SIZE = 2;            // 相同尺寸最多存2个
    
    // ========== 内部寄存器 ==========
    reg [7:0] value_min;                    // 元素最小值限制
    reg [7:0] value_max;                    // 元素最大值限制
    
    // ========== 存储RAM ==========
    reg [7:0] ram [0:MAX_MATRICES*MAX_ELEMENTS-1];  // 主存储空间 (10*25=250字节)
    
    // ========== 元数据存储 ==========
    reg [2:0] meta_m [0:MAX_MATRICES-1];            // 各矩阵的行数
    reg [2:0] meta_n [0:MAX_MATRICES-1];            // 各矩阵的列数
    reg meta_valid_internal [0:MAX_MATRICES-1];     // 各槽位有效标志
    
    reg [3:0] total_matrices;               // 当前存储的矩阵总数
    
    // ========== 写入状态机变量 ==========
    reg [3:0] write_matrix_id;              // 当前写入的矩阵ID
    reg [4:0] write_elem_idx;               // 当前写入的元素索引
    reg [4:0] write_elem_total;             // 需要写入的元素总数
    reg writing;                            // 写入进行中标志
    
    // ========== 读取状态机变量 ==========
    reg [3:0] read_matrix_id;               // 当前读取的矩阵ID
    reg [4:0] read_elem_idx;                // 当前读取的元素索引
    reg [4:0] read_elem_total;              // 需要读取的元素总数
    reg reading;                            // 读取进行中标志
    
    // ========== 结果存储状态机变量 ==========
    reg [3:0] result_matrix_id;             // 结果存储的矩阵ID
    reg [4:0] result_elem_idx;              // 结果存储的元素索引
    reg [2:0] result_m, result_n;           // 结果矩阵的维度
    reg storing_result;                     // 结果存储进行中标志
    
    integer i, j;                           // 循环变量
    
    // ========== 槽位查找状态机变量 ==========
    // 为了避免在时序逻辑中调用函数，使用状态机实现槽位查找
    reg [3:0] slot_search_idx;              // 当前搜索的槽位索引
    reg slot_search_done;                   // 槽位搜索完成标志
    reg [3:0] found_slot;                   // 找到的槽位ID
    reg [2:0] target_m, target_n;           // 目标矩阵的维度
    
    // 槽位查找状态定义
    localparam SLOT_IDLE = 2'd0;            // 空闲状态
    localparam SLOT_SEARCHING = 2'd1;       // 搜索中
    localparam SLOT_FOUND = 2'd2;           // 已找到
    
    reg [1:0] slot_state;
    
    /**************************************************************************
     * 槽位查找状态机
     * 功能：为新矩阵分配存储槽位
     * 策略：1. 优先查找空槽位
     *       2. 查找相同尺寸的槽位（覆盖策略）
     *       3. 都没有则使用槽位0
     **************************************************************************/
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            slot_state <= SLOT_IDLE;
            slot_search_idx <= 4'd0;
            slot_search_done <= 1'b0;
            found_slot <= 4'd0;
            target_m <= 3'd0;
            target_n <= 3'd0;
        end else begin
            case (slot_state)
                // ===== 空闲状态：等待查找请求 =====
                SLOT_IDLE: begin
                    slot_search_done <= 1'b0;
                    
                    // 检测到写入或结果存储请求
                    if ((start_input || op_done) && !writing && !storing_result) begin
                        // 保存目标维度
                        target_m <= (start_input) ? dim_m : result_m;
                        target_n <= (start_input) ? dim_n : result_n;
                        slot_search_idx <= 4'd0;
                        slot_state <= SLOT_SEARCHING;
                    end
                end
                
                // ===== 搜索状态：遍历所有槽位 =====
                SLOT_SEARCHING: begin
                    if (slot_search_idx < MAX_MATRICES) begin
                        // 策略1：找到空槽位，优先使用
                        if (!meta_valid_internal[slot_search_idx]) begin
                            found_slot <= slot_search_idx;
                            slot_search_done <= 1'b1;
                            slot_state <= SLOT_FOUND;
                        end
                        // 策略2：找到相同尺寸的槽位，覆盖使用
                        else if (meta_m[slot_search_idx] == target_m && 
                                 meta_n[slot_search_idx] == target_n) begin
                            found_slot <= slot_search_idx;
                            slot_search_done <= 1'b1;
                            slot_state <= SLOT_FOUND;
                        end
                        // 继续搜索下一个槽位
                        else begin
                            slot_search_idx <= slot_search_idx + 1;
                        end
                    end else begin
                        // 策略3：没找到合适槽位，使用槽位0（覆盖最旧的）
                        found_slot <= 4'd0;
                        slot_search_done <= 1'b1;
                        slot_state <= SLOT_FOUND;
                    end
                end
                
                // ===== 找到状态：返回空闲 =====
                SLOT_FOUND: begin
                    slot_state <= SLOT_IDLE;
                end
                
                default: slot_state <= SLOT_IDLE;
            endcase
        end
    end
    
    /**************************************************************************
     * 主存储控制逻辑
     * 处理：写入、读取、结果存储、运算数加载、列表查询
     **************************************************************************/
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // ===== 初始化所有元数据 =====
            for (i = 0; i < MAX_MATRICES; i = i + 1) begin
                meta_m[i] <= 3'd0;
                meta_n[i] <= 3'd0;
                meta_valid_internal[i] <= 1'b0;
                list_valid[i] <= 1'b0;
                list_m[i] <= 3'd0;
                list_n[i] <= 3'd0;
            end
            
            // ===== 初始化运算数缓冲区 =====
            for (i = 0; i < 25; i = i + 1) begin
                matrix_a[i] <= 8'd0;
                matrix_b[i] <= 8'd0;
            end
            
            // ===== 初始化RAM =====
            for (i = 0; i < MAX_MATRICES*MAX_ELEMENTS; i = i + 1) begin
                ram[i] <= 8'd0;
            end
            
            // ===== 初始化状态变量 =====
            total_matrices <= 4'd0;
            write_matrix_id <= 4'd0;
            write_elem_idx <= 5'd0;
            write_elem_total <= 5'd0;
            writing <= 1'b0;
            read_matrix_id <= 4'd0;
            read_elem_idx <= 5'd0;
            read_elem_total <= 5'd0;
            reading <= 1'b0;
            data_out <= 8'd0;
            matrix_id_out <= 4'd0;
            meta_info_valid <= 1'b0;
            error_flag <= 1'b0;
            
            result_matrix_id <= 4'd0;
            result_elem_idx <= 5'd0;
            result_m <= 3'd0;
            result_n <= 3'd0;
            storing_result <= 1'b0;
            
            matrix_a_m <= 3'd0;
            matrix_a_n <= 3'd0;
            matrix_b_m <= 3'd0;
            matrix_b_n <= 3'd0;
            
            value_min <= 8'd0;
            value_max <= 8'd9;
        end else begin
            // ===== 默认：清除单周期标志 =====
            meta_info_valid <= 1'b0;
            error_flag <= 1'b0;
            
            // ========== 处理1：启动写入流程 ==========
            if (start_input && !writing && slot_search_done) begin
                // 检查维度合法性
                if (dim_m < 3'd1 || dim_m > 3'd5 || dim_n < 3'd1 || dim_n > 3'd5) begin
                    error_flag <= 1'b1;  // 维度非法
                end else begin
                    // 使用槽位查找结果
                    write_matrix_id <= found_slot;
                    write_elem_idx <= 5'd0;
                    write_elem_total <= dim_m * dim_n;
                    writing <= 1'b1;     // 开始写入流程
                end
            end
            
            // ========== 处理2：写入数据流 ==========
            if (writing && write_en) begin
                // 检查数据范围
                if (data_in < value_min || data_in > value_max) begin
                    error_flag <= 1'b1;
                    writing <= 1'b0;
                end else begin
                    // 写入RAM：基地址 = matrix_id * 25
                    ram[write_matrix_id * MAX_ELEMENTS + write_elem_idx] <= data_in;
                    write_elem_idx <= write_elem_idx + 1;
                    
                    // 检查是否写入完成
                    if (write_elem_idx >= write_elem_total - 1) begin
                        // 更新元数据
                        meta_m[write_matrix_id] <= dim_m;
                        meta_n[write_matrix_id] <= dim_n;
                        meta_valid_internal[write_matrix_id] <= 1'b1;
                        writing <= 1'b0;
                    end
                end
            end
            
            // ========== 处理3：启动结果存储流程 ==========
            if (op_done && !storing_result && slot_search_done) begin
                result_matrix_id <= found_slot;
                result_elem_idx <= 5'd0;
                storing_result <= 1'b1;
            end
            
            // ========== 处理4：存储运算结果数据流 ==========
            if (storing_result) begin
                ram[result_matrix_id * MAX_ELEMENTS + result_elem_idx] <= result_data;
                result_elem_idx <= result_elem_idx + 1;
                
                // 检查是否存储完成
                if (result_elem_idx >= result_m * result_n - 1) begin
                    meta_m[result_matrix_id] <= result_m;
                    meta_n[result_matrix_id] <= result_n;
                    meta_valid_internal[result_matrix_id] <= 1'b1;
                    storing_result <= 1'b0;
                end
            end
            
            // ========== 处理5：启动读取/显示流程 ==========
            if (start_disp && !reading) begin
                // 检查矩阵ID合法性
                if (matrix_id_in >= MAX_MATRICES || !meta_valid_internal[matrix_id_in]) begin
                    error_flag <= 1'b1;  // 矩阵不存在
                end else begin
                    read_matrix_id <= matrix_id_in;
                    read_elem_idx <= 5'd0;
                    read_elem_total <= meta_m[matrix_id_in] * meta_n[matrix_id_in];
                    reading <= 1'b1;
                    meta_info_valid <= 1'b1;  // 元信息有效
                end
            end
            
            // ========== 处理6：读取数据流（配合read_en） ==========
            if (reading && read_en) begin
                data_out <= ram[read_matrix_id * MAX_ELEMENTS + read_elem_idx];
                matrix_id_out <= read_matrix_id;
                read_elem_idx <= read_elem_idx + 1;
                
                // 检查是否读取完成
                if (read_elem_idx >= read_elem_total - 1) begin
                    reading <= 1'b0;
                end
            end
            
            // ========== 处理7：加载运算数到缓冲区 ==========
            // 将指定ID的两个矩阵加载到matrix_a和matrix_b
            if (load_operands) begin
                // 加载维度信息
                matrix_a_m <= meta_m[operand_a_id];
                matrix_a_n <= meta_n[operand_a_id];
                matrix_b_m <= meta_m[operand_b_id];
                matrix_b_n <= meta_n[operand_b_id];
                
                // 加载数据（并行加载，综合工具会展开）
                for (j = 0; j < MAX_ELEMENTS; j = j + 1) begin
                    matrix_a[j] <= ram[operand_a_id * MAX_ELEMENTS + j];
                    matrix_b[j] <= ram[operand_b_id * MAX_ELEMENTS + j];
                end
            end
            
            // ========== 处理8：输出矩阵列表信息 ==========
            // 用于display_formatter显示可用矩阵列表
            if (req_list_info) begin
                for (j = 0; j < MAX_MATRICES; j = j + 1) begin
                    list_m[j] <= meta_m[j];
                    list_n[j] <= meta_n[j];
                    list_valid[j] <= meta_valid_internal[j];
                end
            end
        end
    end

endmodule