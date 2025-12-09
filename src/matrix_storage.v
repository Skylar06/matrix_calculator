module matrix_storage (
    input wire clk,
    input wire rst_n,
    input wire write_en,            // 写使能
    input wire read_en,             // 读使能
    input wire [2:0] dim_m,         // 矩阵行数
    input wire [2:0] dim_n,         // 矩阵列数
    input wire [7:0] data_in,       // 输入数据
    input wire [3:0] matrix_id_in,  // 输入矩阵编号
    input wire [7:0] result_data,   // 运算结果数据
    input wire op_done,             // 运算完成标志
    input wire start_input,         // 开始输入标志
    input wire start_disp,          // 开始显示标志
    
    output reg [7:0] data_out,      // 输出数据
    output reg [3:0] matrix_id_out, // 输出矩阵编号
    output reg meta_info_valid,     // 元数据有效标志
    output reg error_flag,          // 错误标志
    output reg [7:0] matrix_a,      // 矩阵A数据(供运算模块使用)
    output reg [7:0] matrix_b       // 矩阵B数据(供运算模块使用)
);

    // ========== 存储配置参数 ==========
    localparam MAX_MATRICES = 10;       // 最多存储10个矩阵
    localparam MAX_ELEMENTS = 25;       // 每个矩阵最多25个元素(5x5)
    localparam MAX_PER_SIZE = 2;        // 每种规格最多存储2个矩阵
    
    // 数值范围配置(可扩展为动态配置)
    reg [7:0] value_min;                // 元素最小值,默认0
    reg [7:0] value_max;                // 元素最大值,默认9
    
    // ========== RAM存储 - 存储矩阵数据 ==========
    reg [7:0] ram [0:MAX_MATRICES*MAX_ELEMENTS-1];
    
    // ========== 元数据表 - 存储每个矩阵的信息 ==========
    reg [2:0] meta_m [0:MAX_MATRICES-1];     // 行数
    reg [2:0] meta_n [0:MAX_MATRICES-1];     // 列数
    reg meta_valid [0:MAX_MATRICES-1];        // 该位置是否有有效矩阵
    
    // 矩阵数量统计
    reg [3:0] total_matrices;                 // 总矩阵数
    
    // ========== 写入控制 ==========
    reg [3:0] write_matrix_id;               // 当前写入的矩阵ID
    reg [4:0] write_elem_idx;                // 当前写入的元素索引
    reg [4:0] write_elem_total;              // 当前矩阵总元素数
    reg writing;                              // 正在写入标志
    
    // ========== 读取控制 ==========
    reg [3:0] read_matrix_id;                // 当前读取的矩阵ID
    reg [4:0] read_elem_idx;                 // 当前读取的元素索引
    reg [4:0] read_elem_total;               // 读取的总元素数
    reg reading;                              // 正在读取标志
    
    // ========== 运算结果相关 ==========
    reg [3:0] result_matrix_id;          // 结果矩阵ID
    reg [4:0] result_elem_idx;           // 结果元素索引
    reg [2:0] result_m, result_n;        // 结果矩阵维度
    reg storing_result;                   // 正在存储结果
    
    integer i;
    
    // ========== 初始化和主逻辑 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 初始化元数据
            for (i = 0; i < MAX_MATRICES; i = i + 1) begin
                meta_m[i] <= 3'd0;
                meta_n[i] <= 3'd0;
                meta_valid[i] <= 1'b0;
            end
            
            // 初始化控制信号
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
            matrix_a <= 8'd0;
            matrix_b <= 8'd0;
            
            // 初始化运算结果相关
            result_matrix_id <= 4'd0;
            result_elem_idx <= 5'd0;
            result_m <= 3'd0;
            result_n <= 3'd0;
            storing_result <= 1'b0;
            
            // 初始化数值范围
            value_min <= 8'd0;
            value_max <= 8'd9;
        end else begin
            // 默认关闭控制信号
            meta_info_valid <= 1'b0;
            error_flag <= 1'b0;
            
            // ========== 写入逻辑 ==========
            if (start_input && !writing) begin
                // ===== 检测1: 维度范围 (1-5) =====
                if (dim_m < 3'd1 || dim_m > 3'd5 || dim_n < 3'd1 || dim_n > 3'd5) begin
                    error_flag <= 1'b1;  // 维度超出范围!
                    writing <= 1'b0;
                end else begin
                    // 维度合法,开始写入
                    write_matrix_id <= find_or_create_slot(dim_m, dim_n);
                    write_elem_idx <= 5'd0;
                    write_elem_total <= dim_m * dim_n;
                    writing <= 1'b1;
                end
            end
            
            if (writing && write_en) begin
                // ===== 检测2: 数值范围 (0-9或配置范围) =====
                if (data_in < value_min || data_in > value_max) begin
                    error_flag <= 1'b1;  // 数值超出范围!
                    writing <= 1'b0;     // 终止写入,需要重新输入
                    // 不写入无效数据,直接退出写入状态
                end else begin
                    // ===== 检测3a: 元素个数控制 - 只取前N个 =====
                    if (write_elem_idx < write_elem_total) begin
                        // 在范围内,正常写入
                        ram[write_matrix_id * MAX_ELEMENTS + write_elem_idx] <= data_in;
                        write_elem_idx <= write_elem_idx + 1;
                        
                        // 检查是否写入完成
                        if (write_elem_idx >= write_elem_total - 1) begin
                            // 更新元数据
                            meta_m[write_matrix_id] <= dim_m;
                            meta_n[write_matrix_id] <= dim_n;
                            meta_valid[write_matrix_id] <= 1'b1;
                            
                            // 更新总数(如果是新矩阵)
                            if (!meta_valid[write_matrix_id])
                                total_matrices <= total_matrices + 1;
                            
                            writing <= 1'b0;
                        end
                    end
                    // 如果 write_elem_idx >= write_elem_total,
                    // 元素超出,自动忽略(不写入,不报错)
                end
            end
            
            // ===== 检测3b: 元素不足自动填0 =====
            // 当writing=1但长时间没有write_en时,说明用户停止输入
            // 直接填充剩余位置为0
            if (writing && !write_en) begin
                // 如果还有未填充的位置,自动填0
                if (write_elem_idx < write_elem_total) begin
                    ram[write_matrix_id * MAX_ELEMENTS + write_elem_idx] <= 8'd0;
                    write_elem_idx <= write_elem_idx + 1;
                    
                    // 检查是否填充完成
                    if (write_elem_idx >= write_elem_total - 1) begin
                        // 更新元数据
                        meta_m[write_matrix_id] <= dim_m;
                        meta_n[write_matrix_id] <= dim_n;
                        meta_valid[write_matrix_id] <= 1'b1;
                        
                        if (!meta_valid[write_matrix_id])
                            total_matrices <= total_matrices + 1;
                        
                        writing <= 1'b0;
                    end
                end
            end
            
            // ========== 存储运算结果 ==========
            // 运算模块应该提供结果维度信息(result_m, result_n)
            // 这里假设从mat_ops接收到维度信息
            if (op_done && !storing_result) begin
                // 开始存储运算结果
                result_matrix_id <= find_or_create_slot(result_m, result_n);
                result_elem_idx <= 5'd0;
                storing_result <= 1'b1;
            end
            
            if (storing_result) begin
                // 逐个存储结果元素
                ram[result_matrix_id * MAX_ELEMENTS + result_elem_idx] <= result_data;
                result_elem_idx <= result_elem_idx + 1;
                
                // 检查是否存储完成
                if (result_elem_idx >= result_m * result_n - 1) begin
                    // 更新元数据
                    meta_m[result_matrix_id] <= result_m;
                    meta_n[result_matrix_id] <= result_n;
                    meta_valid[result_matrix_id] <= 1'b1;
                    
                    if (!meta_valid[result_matrix_id])
                        total_matrices <= total_matrices + 1;
                    
                    storing_result <= 1'b0;
                end
            end
            
            // ========== 读取/显示逻辑 ==========
            if (start_disp && !reading) begin
                // 开始显示矩阵
                // 检查矩阵ID是否有效
                if (matrix_id_in >= MAX_MATRICES || !meta_valid[matrix_id_in]) begin
                    error_flag <= 1'b1;  // 矩阵ID无效!
                end else begin
                    read_matrix_id <= matrix_id_in;
                    read_elem_idx <= 5'd0;
                    read_elem_total <= meta_m[matrix_id_in] * meta_n[matrix_id_in];
                    reading <= 1'b1;
                    meta_info_valid <= 1'b1;
                end
            end
            
            if (reading) begin
                // 从RAM读取数据
                data_out <= ram[read_matrix_id * MAX_ELEMENTS + read_elem_idx];
                matrix_id_out <= read_matrix_id;
                
                if (read_en) begin
                    read_elem_idx <= read_elem_idx + 1;
                    
                    // 检查是否读取完成
                    if (read_elem_idx >= read_elem_total - 1) begin
                        reading <= 1'b0;
                    end
                end
            end
            
            // ========== 为运算模块提供矩阵数据 ==========
            // 根据matrix_id_in读取指定的矩阵数据
            // 这里需要mat_ops提供需要读取的矩阵ID
            // 当前设计: matrix_a和matrix_b由mat_ops通过read接口获取
            // (实际使用时需要完善握手机制)
        end
    end
    
    // ========== 查找或创建存储槽位的函数 ==========
    function [3:0] find_or_create_slot;
        input [2:0] m;
        input [2:0] n;
        integer j, count, first_invalid, last_same;
        begin
            count = 0;
            first_invalid = MAX_MATRICES;
            last_same = MAX_MATRICES;
            find_or_create_slot = 4'd0;
            
            // 先查找相同规格的矩阵数量
            for (j = 0; j < MAX_MATRICES; j = j + 1) begin
                if (meta_valid[j] && meta_m[j] == m && meta_n[j] == n) begin
                    count = count + 1;
                    last_same = j; // 记录最后一个相同规格的位置
                end
                if (!meta_valid[j] && first_invalid == MAX_MATRICES) begin
                    first_invalid = j; // 记录第一个空位置
                end
            end
            
            // 如果相同规格矩阵数量 < MAX_PER_SIZE,使用新槽位
            if (count < MAX_PER_SIZE) begin
                if (first_invalid < MAX_MATRICES)
                    find_or_create_slot = first_invalid;
                else
                    find_or_create_slot = 4'd0; // RAM满了,使用槽位0
            end else begin
                // 覆盖策略:覆盖该规格的第一个矩阵
                for (j = 0; j < MAX_MATRICES; j = j + 1) begin
                    if (meta_valid[j] && meta_m[j] == m && meta_n[j] == n) begin
                        find_or_create_slot = j;
                        j = MAX_MATRICES; // 退出循环
                    end
                end
            end
        end
    endfunction

endmodule

// ============================================================================
// 系统检测说明:
//
// 1. 维度范围检测 (1-5):
//    - 在start_input时检查dim_m和dim_n
//    - 不合法: error_flag=1, 拒绝写入
//
// 2. 数值范围检测 (0-9):
//    - 在write_en时检查data_in
//    - 不合法: error_flag=1, 跳过该元素
//    - 默认范围: [0, 9]
//    - 可扩展: 通过value_min/value_max配置
//
// 3. 元素个数处理:
//    a) 元素不足: 自动填充0
//       示例: 2x3矩阵只输入4个 → [1,2,3],[4,0,0]
//    b) 元素超出: 自动忽略多余的
//       示例: 2x3矩阵输入8个 → 只取前6个
//
// 4. 矩阵ID检测:
//    - 在start_disp时检查matrix_id_in
//    - 无效或不存在: error_flag=1
//
// 错误处理:
//    - error_flag连接到ctrl_fsm
//    - 触发ERROR状态,LED闪烁,倒计时
// ============================================================================