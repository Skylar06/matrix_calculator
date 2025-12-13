module matrix_storage (
    input  wire        clk,
    input  wire        rst_n,

    // config parameters
    input  wire signed [7:0] elem_min,
    input  wire signed [7:0] elem_max,
    output reg         query_max_per_size,
    input  wire [3:0]  max_per_size_in,

    // write interface
    input  wire        write_en,
    input  wire [2:0]  dim_m,
    input  wire [2:0]  dim_n,
    input  wire [7:0]  data_in,
    input  wire [3:0]  matrix_id_in,

    // result store interface
    input  wire [7:0]  result_data,
    input  wire        op_done,
    input  wire [2:0]  result_m,
    input  wire [2:0]  result_n,

    // control
    input  wire        start_input,
    input  wire        start_gen,  // 修复：添加start_gen输入
    input  wire        start_disp,
    input  wire        read_en,

    // operand load
    input  wire        load_operands,
    input  wire [3:0]  operand_a_id,
    input  wire [3:0]  operand_b_id,

    // list request
    input  wire        req_list_info,

    // read/display
    output reg  [7:0]  data_out,
    output reg  [3:0]  matrix_id_out,
    output reg  [3:0]  write_matrix_id_out,  // 修复：输出写入时的matrix_id
    output reg         meta_info_valid,
    output reg         matrix_data_valid,
    output reg         error_flag,

    // packed outputs
    output wire [8*25-1:0] matrix_a_flat,
    output wire [8*25-1:0] matrix_b_flat,
    output reg  [2:0]  matrix_a_m,
    output reg  [2:0]  matrix_a_n,
    output reg  [2:0]  matrix_b_m,
    output reg  [2:0]  matrix_b_n,

    output wire [3*10-1:0] list_m_flat,
    output wire [3*10-1:0] list_n_flat,
    output wire [10-1:0]   list_valid_flat
);

    localparam MAX_MATRICES = 10;
    localparam MAX_ELEMENTS = 25;

    (* ram_style = "block" *) reg [7:0] ram [0:MAX_MATRICES*MAX_ELEMENTS-1];
    reg [2:0] meta_m [0:MAX_MATRICES-1];
    reg [2:0] meta_n [0:MAX_MATRICES-1];
    reg       meta_valid_internal [0:MAX_MATRICES-1];

    reg [3:0] total_matrices;

    // write state
    reg [3:0] write_matrix_id;
    reg [4:0] write_elem_idx;
    reg [4:0] write_elem_total;
    reg       writing;
    reg       start_input_prev;  // 用于检测start_input下降沿

    // read state
    reg [3:0] read_matrix_id;
    reg [4:0] read_elem_idx;
    reg [4:0] read_elem_total;
    reg       reading;

    // result store state
    reg [3:0] result_matrix_id;
    reg [4:0] result_elem_idx;
    reg       storing_result;
    reg       pending_result;

    // internal buffers
    reg [7:0] matrix_a [0:24];
    reg [7:0] matrix_b [0:24];
    reg [2:0] list_m [0:9];
    reg [2:0] list_n [0:9];
    reg       list_valid [0:9];

    // pack outputs
    genvar pack_i;
    generate
        for (pack_i = 0; pack_i < 25; pack_i = pack_i + 1) begin : GEN_PACK_A
            assign matrix_a_flat[pack_i*8 +: 8] = matrix_a[pack_i];
            assign matrix_b_flat[pack_i*8 +: 8] = matrix_b[pack_i];
        end
        for (pack_i = 0; pack_i < 10; pack_i = pack_i + 1) begin : GEN_PACK_LIST
            assign list_m_flat[pack_i*3 +: 3] = list_m[pack_i];
            assign list_n_flat[pack_i*3 +: 3] = list_n[pack_i];
            assign list_valid_flat[pack_i]    = list_valid[pack_i];
        end
    endgenerate

    integer i, j;

    // slot search FSM
    reg [3:0] slot_search_idx;
    reg       slot_search_done;
    reg [3:0] found_slot;
    reg [2:0] target_m, target_n;

    localparam SLOT_IDLE      = 2'd0;
    localparam SLOT_SEARCHING = 2'd1;
    localparam SLOT_FOUND     = 2'd2;

    reg [1:0] slot_state;
    reg [3:0] same_size_count;
    reg error_flag_clear;  // 修复：error_flag清除标志

    function [3:0] count_same_size;
        input [2:0] check_m;
        input [2:0] check_n;
        integer k;
        begin
            count_same_size = 4'd0;
            for (k = 0; k < MAX_MATRICES; k = k + 1) begin
                if (meta_valid_internal[k] &&
                    meta_m[k] == check_m &&
                    meta_n[k] == check_n) begin
                    count_same_size = count_same_size + 1;
                end
            end
        end
    endfunction

    // slot search
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            slot_state <= SLOT_IDLE;
            slot_search_idx <= 4'd0;
            slot_search_done <= 1'b0;
            found_slot <= 4'd0;
            target_m <= 3'd0;
            target_n <= 3'd0;
            query_max_per_size <= 1'b0;
            same_size_count <= 4'd0;
        end else begin
            query_max_per_size <= 1'b0;

            case (slot_state)
                SLOT_IDLE: begin
                    slot_search_done <= 1'b0;
                    if ((start_input || start_gen || op_done) && !writing && !storing_result) begin
                        // 修复：支持GEN模式的slot搜索
                        if (start_gen) begin
                            target_m <= dim_m;
                            target_n <= dim_n;
                            same_size_count <= count_same_size(dim_m, dim_n);
                        end else if (start_input) begin
                            target_m <= dim_m;
                            target_n <= dim_n;
                            same_size_count <= count_same_size(dim_m, dim_n);
                        end else begin
                            target_m <= result_m;
                            target_n <= result_n;
                            same_size_count <= count_same_size(result_m, result_n);
                        end
                        slot_search_idx <= 4'd0;
                        query_max_per_size <= 1'b1;
                        slot_state <= SLOT_SEARCHING;
                    end
                end

                SLOT_SEARCHING: begin
                    if (slot_search_idx < MAX_MATRICES) begin
                        if (!meta_valid_internal[slot_search_idx]) begin
                            found_slot <= slot_search_idx;
                            slot_search_done <= 1'b1;
                            slot_state <= SLOT_FOUND;
                        end else if (meta_m[slot_search_idx] == target_m &&
                                     meta_n[slot_search_idx] == target_n) begin
                            if (same_size_count >= max_per_size_in) begin
                                found_slot <= slot_search_idx;
                                slot_search_done <= 1'b1;
                                slot_state <= SLOT_FOUND;
                            end else begin
                                slot_search_idx <= slot_search_idx + 1;
                            end
                        end else begin
                            slot_search_idx <= slot_search_idx + 1;
                        end
                    end else begin
                        found_slot <= 4'd0;
                        slot_search_done <= 1'b1;
                        slot_state <= SLOT_FOUND;
                    end
                end

                SLOT_FOUND: slot_state <= SLOT_IDLE;
                default:    slot_state <= SLOT_IDLE;
            endcase
        end
    end

    // main logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < MAX_MATRICES; i = i + 1) begin
                meta_m[i] <= 3'd0;
                meta_n[i] <= 3'd0;
                meta_valid_internal[i] <= 1'b0;
                list_valid[i] <= 1'b0;
                list_m[i] <= 3'd0;
                list_n[i] <= 3'd0;
            end
            for (i = 0; i < 25; i = i + 1) begin
                matrix_a[i] <= 8'd0;
                matrix_b[i] <= 8'd0;
            end

            total_matrices   <= 4'd0;
            write_matrix_id  <= 4'd0;
            write_elem_idx   <= 5'd0;
            write_elem_total <= 5'd0;
            writing          <= 1'b0;
            start_input_prev <= 1'b0;
            read_matrix_id   <= 4'd0;
            read_elem_idx    <= 5'd0;
            read_elem_total  <= 5'd0;
            reading          <= 1'b0;
            data_out         <= 8'd0;
            matrix_id_out    <= 4'd0;
            write_matrix_id_out <= 4'd0;  // 修复：复位write_matrix_id_out
            meta_info_valid  <= 1'b0;
            matrix_data_valid<= 1'b0;
            error_flag       <= 1'b0;
            error_flag_clear <= 1'b0;

            result_matrix_id <= 4'd0;
            result_elem_idx  <= 5'd0;
            storing_result   <= 1'b0;
            pending_result   <= 1'b0;

            matrix_a_m <= 3'd0;
            matrix_a_n <= 3'd0;
            matrix_b_m <= 3'd0;
            matrix_b_n <= 3'd0;
        end else begin
            meta_info_valid   <= 1'b0;
            matrix_data_valid <= 1'b0;
            // 修复：error_flag不应该每个周期都清除，应该保持直到被明确清除
            // error_flag        <= 1'b0;  // 注释掉自动清除

            if (op_done) pending_result <= 1'b1;

            // 修复：error_flag清除逻辑 - 只在新的start_input时清除之前的错误
            // 但需要保持错误标志直到被明确清除或新的输入开始
            if (start_input && !writing && slot_search_done) begin
                error_flag_clear <= 1'b1;  // 标记可以清除错误
            end else begin
                error_flag_clear <= 1'b0;
            end

            // write flow (INPUT和GEN模式共用)
            if ((start_input || start_gen) && !writing && slot_search_done) begin
                if (dim_m < 3'd1 || dim_m > 3'd5 || dim_n < 3'd1 || dim_n > 3'd5) begin
                    error_flag <= 1'b1;
                end else begin
                    if (error_flag_clear) error_flag <= 1'b0;  // 清除之前的错误
                    write_matrix_id  <= found_slot;
                    write_elem_idx   <= 5'd0;
                    write_elem_total <= dim_m * dim_n;
                    writing          <= 1'b1;
                end
            end

            // 检测start_input下降沿
            start_input_prev <= start_input;
            
            if (writing && write_en) begin
                if ($signed(data_in) < elem_min || $signed(data_in) > elem_max) begin
                    error_flag <= 1'b1;
                    writing    <= 1'b0;
                end else begin
                    ram[write_matrix_id * MAX_ELEMENTS + write_elem_idx] <= data_in;
                    write_elem_idx <= write_elem_idx + 1;
                    if (write_elem_idx >= write_elem_total - 1) begin
                        meta_m[write_matrix_id] <= dim_m;
                        meta_n[write_matrix_id] <= dim_n;
                        meta_valid_internal[write_matrix_id] <= 1'b1;
                        write_matrix_id_out <= write_matrix_id;  // 修复：输出写入的matrix_id
                        writing <= 1'b0;
                        // 输入成功完成，清除错误标志
                        error_flag <= 1'b0;
                    end
                end
            end
            
            // 修复：如果输入元素个数不足，剩余位置自动填0
            // 当start_input下降沿（输入完成）但writing还在进行时，自动填充剩余位置为0
            if (writing && start_input_prev && !start_input && write_elem_idx < write_elem_total) begin
                // 输入已完成但元素不足，剩余位置填0
                ram[write_matrix_id * MAX_ELEMENTS + write_elem_idx] <= 8'd0;
                write_elem_idx <= write_elem_idx + 1;
                if (write_elem_idx >= write_elem_total - 1) begin
                    meta_m[write_matrix_id] <= dim_m;
                    meta_n[write_matrix_id] <= dim_n;
                    meta_valid_internal[write_matrix_id] <= 1'b1;
                    write_matrix_id_out <= write_matrix_id;  // 修复：输出写入的matrix_id
                    writing <= 1'b0;
                end
            end

            // store result
            if (pending_result && !storing_result && slot_search_done) begin
                result_matrix_id <= found_slot;
                result_elem_idx  <= 5'd0;
                storing_result   <= 1'b1;
                pending_result   <= 1'b0;
            end

            if (storing_result) begin
                ram[result_matrix_id * MAX_ELEMENTS + result_elem_idx] <= result_data;
                result_elem_idx <= result_elem_idx + 1;
                if (result_elem_idx >= result_m * result_n - 1) begin
                    meta_m[result_matrix_id] <= result_m;
                    meta_n[result_matrix_id] <= result_n;
                    meta_valid_internal[result_matrix_id] <= 1'b1;
                    storing_result <= 1'b0;
                end
            end

            // read/display
            if (start_disp && !reading) begin
                if (matrix_id_in >= MAX_MATRICES || !meta_valid_internal[matrix_id_in]) begin
                    error_flag <= 1'b1;
                end else begin
                    read_matrix_id  <= matrix_id_in;
                    read_elem_idx   <= 5'd0;
                    read_elem_total <= meta_m[matrix_id_in] * meta_n[matrix_id_in];
                    reading         <= 1'b1;
                    meta_info_valid <= 1'b1;
                end
            end

            if (reading && read_en) begin
                data_out <= ram[read_matrix_id * MAX_ELEMENTS + read_elem_idx];
                matrix_id_out <= read_matrix_id;
                matrix_data_valid <= 1'b1;
                read_elem_idx <= read_elem_idx + 1;
                if (read_elem_idx >= read_elem_total - 1) begin
                    reading <= 1'b0;
                end
            end

            // load operands
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

            // list info
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