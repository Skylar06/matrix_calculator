module matrix_storage (
    input wire clk,
    input wire rst_n,
    input wire write_en,
    input wire read_en,
    input wire [2:0] dim_m,
    input wire [2:0] dim_n,
    input wire [7:0] data_in,
    input wire [3:0] matrix_id_in,
    input wire [7:0] result_data,
    input wire op_done,
    input wire start_input,
    input wire start_disp,
    
    // 新增：运算数加载接口
    input wire load_operands,
    input wire [3:0] operand_a_id,
    input wire [3:0] operand_b_id,
    
    // 新增：列表查询接口
    input wire req_list_info,
    
    output reg [7:0] data_out,
    output reg [3:0] matrix_id_out,
    output reg meta_info_valid,
    output reg error_flag,
    
    // 修改：矩阵数据输出改为缓冲区
    output reg [7:0] matrix_a [0:24],
    output reg [7:0] matrix_b [0:24],
    output reg [2:0] matrix_a_m,
    output reg [2:0] matrix_a_n,
    output reg [2:0] matrix_b_m,
    output reg [2:0] matrix_b_n,
    
    // 新增：列表信息输出
    output reg [2:0] list_m [0:9],
    output reg [2:0] list_n [0:9],
    output reg list_valid [0:9]
);

    localparam MAX_MATRICES = 10;
    localparam MAX_ELEMENTS = 25;
    localparam MAX_PER_SIZE = 2;
    
    reg [7:0] value_min;
    reg [7:0] value_max;
    
    reg [7:0] ram [0:MAX_MATRICES*MAX_ELEMENTS-1];
    
    reg [2:0] meta_m [0:MAX_MATRICES-1];
    reg [2:0] meta_n [0:MAX_MATRICES-1];
    reg meta_valid [0:MAX_MATRICES-1];
    
    reg [3:0] total_matrices;
    
    reg [3:0] write_matrix_id;
    reg [4:0] write_elem_idx;
    reg [4:0] write_elem_total;
    reg writing;
    
    reg [3:0] read_matrix_id;
    reg [4:0] read_elem_idx;
    reg [4:0] read_elem_total;
    reg reading;
    
    reg [3:0] result_matrix_id;
    reg [4:0] result_elem_idx;
    reg [2:0] result_m, result_n;
    reg storing_result;
    
    integer i, j;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < MAX_MATRICES; i = i + 1) begin
                meta_m[i] <= 3'd0;
                meta_n[i] <= 3'd0;
                meta_valid[i] <= 1'b0;
            end
            
            for (i = 0; i < 25; i = i + 1) begin
                matrix_a[i] <= 8'd0;
                matrix_b[i] <= 8'd0;
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
            meta_info_valid <= 1'b0;
            error_flag <= 1'b0;
            
            // ========== 写入逻辑 ==========
            if (start_input && !writing) begin
                if (dim_m < 3'd1 || dim_m > 3'd5 || dim_n < 3'd1 || dim_n > 3'd5) begin
                    error_flag <= 1'b1;
                    writing <= 1'b0;
                end else begin
                    write_matrix_id <= find_or_create_slot(dim_m, dim_n);
                    write_elem_idx <= 5'd0;
                    write_elem_total <= dim_m * dim_n;
                    writing <= 1'b1;
                end
            end
            
            if (writing && write_en) begin
                if (data_in < value_min || data_in > value_max) begin
                    error_flag <= 1'b1;
                    writing <= 1'b0;
                end else begin
                    if (write_elem_idx < write_elem_total) begin
                        ram[write_matrix_id * MAX_ELEMENTS + write_elem_idx] <= data_in;
                        write_elem_idx <= write_elem_idx + 1;
                        
                        if (write_elem_idx >= write_elem_total - 1) begin
                            meta_m[write_matrix_id] <= dim_m;
                            meta_n[write_matrix_id] <= dim_n;
                            meta_valid[write_matrix_id] <= 1'b1;
                            
                            if (!meta_valid[write_matrix_id])
                                total_matrices <= total_matrices + 1;
                            
                            writing <= 1'b0;
                        end
                    end
                end
            end
            
            if (writing && !write_en) begin
                if (write_elem_idx < write_elem_total) begin
                    ram[write_matrix_id * MAX_ELEMENTS + write_elem_idx] <= 8'd0;
                    write_elem_idx <= write_elem_idx + 1;
                    
                    if (write_elem_idx >= write_elem_total - 1) begin
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
            if (op_done && !storing_result) begin
                result_matrix_id <= find_or_create_slot(result_m, result_n);
                result_elem_idx <= 5'd0;
                storing_result <= 1'b1;
            end
            
            if (storing_result) begin
                ram[result_matrix_id * MAX_ELEMENTS + result_elem_idx] <= result_data;
                result_elem_idx <= result_elem_idx + 1;
                
                if (result_elem_idx >= result_m * result_n - 1) begin
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
                data_out <= ram[read_matrix_id * MAX_ELEMENTS + read_elem_idx];
                matrix_id_out <= read_matrix_id;
                
                if (read_en) begin
                    read_elem_idx <= read_elem_idx + 1;
                    
                    if (read_elem_idx >= read_elem_total - 1) begin
                        reading <= 1'b0;
                    end
                end
            end
            
            // ========== 新增：加载运算数到缓冲区 ==========
            if (load_operands) begin
                matrix_a_m <= meta_m[operand_a_id];
                matrix_a_n <= meta_n[operand_a_id];
                matrix_b_m <= meta_m[operand_b_id];
                matrix_b_n <= meta_n[operand_b_id];
                
                for (j = 0; j < MAX_ELEMENTS; j = j + 1) begin
                    matrix_a[j] <= ram[operand_a_id * MAX_ELEMENTS + j];
                    matrix_b[j] <= ram[operand_b_id * MAX_ELEMENTS + j];
                end
            end
            
            // ========== 新增：输出列表信息 ==========
            if (req_list_info) begin
                for (j = 0; j < MAX_MATRICES; j = j + 1) begin
                    list_m[j] <= meta_m[j];
                    list_n[j] <= meta_n[j];
                    list_valid[j] <= meta_valid[j];
                end
            end
        end
    end
    
    function [3:0] find_or_create_slot;
        input [2:0] m;
        input [2:0] n;
        integer j, count, first_invalid, last_same;
        begin
            count = 0;
            first_invalid = MAX_MATRICES;
            last_same = MAX_MATRICES;
            find_or_create_slot = 4'd0;
            
            for (j = 0; j < MAX_MATRICES; j = j + 1) begin
                if (meta_valid[j] && meta_m[j] == m && meta_n[j] == n) begin
                    count = count + 1;
                    last_same = j;
                end
                if (!meta_valid[j] && first_invalid == MAX_MATRICES) begin
                    first_invalid = j;
                end
            end
            
            if (count < MAX_PER_SIZE) begin
                if (first_invalid < MAX_MATRICES)
                    find_or_create_slot = first_invalid;
                else
                    find_or_create_slot = 4'd0;
            end else begin
                for (j = 0; j < MAX_MATRICES; j = j + 1) begin
                    if (meta_valid[j] && meta_m[j] == m && meta_n[j] == n) begin
                        find_or_create_slot = j;
                        j = MAX_MATRICES;
                    end
                end
            end
        end
    endfunction

endmodule
