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

    // 存储配置参数
    localparam MAX_MATRICES = 10;       // 最多存储10个矩阵
    localparam MAX_ELEMENTS = 25;       // 每个矩阵最多25个元素(5x5)
    localparam MAX_PER_SIZE = 2;        // 每种规格最多存储2个矩阵
    
    // RAM存储 - 存储矩阵数据
    reg [7:0] ram [0:MAX_MATRICES*MAX_ELEMENTS-1];
    
    // 元数据表 - 存储每个矩阵的信息
    reg [2:0] meta_m [0:MAX_MATRICES-1];     // 行数
    reg [2:0] meta_n [0:MAX_MATRICES-1];     // 列数
    reg meta_valid [0:MAX_MATRICES-1];        // 该位置是否有有效矩阵
    
    // 矩阵数量统计
    reg [3:0] total_matrices;                 // 总矩阵数
    
    // 写入控制
    reg [3:0] write_matrix_id;               // 当前写入的矩阵ID
    reg [4:0] write_elem_idx;                // 当前写入的元素索引
    reg [4:0] write_elem_total;              // 当前矩阵总元素数
    reg writing;                              // 正在写入标志
    
    // 读取控制
    reg [3:0] read_matrix_id;                // 当前读取的矩阵ID
    reg [4:0] read_elem_idx;                 // 当前读取的元素索引
    reg [4:0] read_elem_total;               // 读取的总元素数
    reg reading;                              // 正在读取标志
    
    // 用于运算的矩阵索引
    reg [4:0] mat_a_idx;
    reg [4:0] mat_b_idx;
    
    integer i;
    
    // 初始化和主逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < MAX_MATRICES; i = i + 1) begin
                meta_m[i] <= 3'd0;
                meta_n[i] <= 3'd0;
                meta_valid[i] <= 1'b0;
            end
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
            mat_a_idx <= 5'd0;
            mat_b_idx <= 5'd0;
        end else begin
            // 默认关闭控制信号
            meta_info_valid <= 1'b0;
            error_flag <= 1'b0;
            
            // ========== 写入逻辑 ==========
            if (start_input && !writing) begin
                // 开始新的矩阵输入
                // 检查维度合法性
                if (dim_m < 1 || dim_m > 5 || dim_n < 1 || dim_n > 5) begin
                    error_flag <= 1'b1;
                end else begin
                    // 查找或创建存储槽位
                    write_matrix_id <= find_or_create_slot(dim_m, dim_n);
                    write_elem_idx <= 5'd0;
                    write_elem_total <= dim_m * dim_n;
                    writing <= 1'b1;
                end
            end
            
            if (writing && write_en) begin
                // 写入数据到RAM
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
            
            // ========== 存储运算结果 ==========
            if (op_done) begin
                // 将运算结果存储为新矩阵
                // 这里简化处理,实际应该根据运算类型确定结果矩阵维度
                // 可以扩展为从mat_ops接收结果维度
                ram[write_matrix_id * MAX_ELEMENTS + write_elem_idx] <= result_data;
                write_elem_idx <= write_elem_idx + 1;
            end
            
            // ========== 读取/显示逻辑 ==========
            if (start_disp && !reading) begin
                // 开始显示矩阵
                // 检查矩阵ID是否有效
                if (matrix_id_in >= MAX_MATRICES || !meta_valid[matrix_id_in]) begin
                    error_flag <= 1'b1;
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
            // 这里可以扩展为根据matrix_id_in读取特定矩阵
            // 简化实现:假设矩阵A是ID=0,矩阵B是ID=1
            if (meta_valid[0]) begin
                matrix_a <= ram[0 * MAX_ELEMENTS + mat_a_idx];
                mat_a_idx <= (mat_a_idx < meta_m[0] * meta_n[0] - 1) ? mat_a_idx + 1 : 5'd0;
            end
            
            if (meta_valid[1]) begin
                matrix_b <= ram[1 * MAX_ELEMENTS + mat_b_idx];
                mat_b_idx <= (mat_b_idx < meta_m[1] * meta_n[1] - 1) ? mat_b_idx + 1 : 5'd0;
            end
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
                // 覆盖策略:覆盖该规格的第一个矩阵(可以改为LRU等策略)
                // 这里简化为找到第一个相同规格的矩阵
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