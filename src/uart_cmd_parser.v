module uart_cmd_parser (
    input wire clk,
    input wire rst_n,
    input wire [7:0] rx_data,
    input wire rx_valid,
    input wire [1:0] mode_sel,
    input wire start_input,
    input wire start_gen,
    input wire in_operand_select,      // 新增：当前是否在选择运算数状态
    
    output reg [2:0] dim_m,
    output reg [2:0] dim_n,
    output reg [7:0] elem_data,
    output reg [7:0] elem_min,
    output reg [7:0] elem_max,
    output reg [3:0] count,
    output reg [3:0] matrix_id,
    output reg write_en,
    output reg data_ready,
    
    // 新增：运算数选择输出
    output reg [3:0] user_id_a,
    output reg [3:0] user_id_b,
    output reg user_input_valid
);

    localparam IDLE         = 3'd0;
    localparam WAIT_M       = 3'd1;
    localparam WAIT_N       = 3'd2;
    localparam WAIT_DATA    = 3'd3;
    localparam WAIT_ID_A    = 3'd4;    // 新增
    localparam WAIT_ID_B    = 3'd5;    // 新增
    localparam DONE         = 3'd6;

    reg [2:0] state, next_state;
    
    reg [4:0] data_cnt;
    reg [4:0] data_total;
    reg [7:0] num_buffer;
    reg num_building;
    
    localparam ASCII_SPACE = 8'd32;
    localparam ASCII_0 = 8'd48;
    localparam ASCII_9 = 8'd57;
    localparam ASCII_MINUS = 8'd45;
    localparam ASCII_CR = 8'd13;
    localparam ASCII_LF = 8'd10;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        next_state = state;
        
        case (state)
            IDLE: begin
                if (in_operand_select)              // 运算数选择模式
                    next_state = WAIT_ID_A;
                else if (start_input || start_gen)
                    next_state = WAIT_M;
            end
            
            WAIT_M: begin
                if (rx_valid && (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF))
                    next_state = WAIT_N;
            end
            
            WAIT_N: begin
                if (rx_valid && (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF)) begin
                    case (mode_sel)
                        2'b00: next_state = WAIT_DATA;  // INPUT
                        2'b01: next_state = WAIT_DATA;  // GEN
                        default: next_state = DONE;
                    endcase
                end
            end
            
            WAIT_DATA: begin
                case (mode_sel)
                    2'b01: begin  // INPUT
                        if (data_cnt >= data_total)
                            next_state = DONE;
                    end
                    2'b10: begin  // GEN
                        if (data_cnt >= 1)
                            next_state = DONE;
                    end
                    default: next_state = DONE;
                endcase
            end
            
            WAIT_ID_A: begin
                if (rx_valid && (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF))
                    next_state = WAIT_ID_B;
            end
            
            WAIT_ID_B: begin
                if (rx_valid && (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF))
                    next_state = DONE;
            end
            
            DONE: begin
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dim_m <= 3'd0;
            dim_n <= 3'd0;
            elem_data <= 8'd0;
            elem_min <= 8'd0;
            elem_max <= 8'd9;
            count <= 4'd0;
            matrix_id <= 4'd0;
            write_en <= 1'b0;
            data_ready <= 1'b0;
            data_cnt <= 5'd0;
            data_total <= 5'd0;
            num_buffer <= 8'd0;
            num_building <= 1'b0;
            user_id_a <= 4'd0;
            user_id_b <= 4'd0;
            user_input_valid <= 1'b0;
        end else begin
            write_en <= 1'b0;
            data_ready <= 1'b0;
            user_input_valid <= 1'b0;
            
            case (state)
                IDLE: begin
                    data_cnt <= 5'd0;
                    data_total <= 5'd0;
                    num_buffer <= 8'd0;
                    num_building <= 1'b0;
                end
                
                WAIT_M: begin
                    if (rx_valid) begin
                        if (rx_data >= ASCII_0 && rx_data <= ASCII_9) begin
                            if (num_building) begin
                                num_buffer <= num_buffer * 10 + (rx_data - ASCII_0);
                            end else begin
                                num_buffer <= rx_data - ASCII_0;
                                num_building <= 1'b1;
                            end
                        end
                        else if (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF) begin
                            dim_m <= num_buffer[2:0];
                            num_buffer <= 8'd0;
                            num_building <= 1'b0;
                        end
                    end
                end
                
                WAIT_N: begin
                    if (rx_valid) begin
                        if (rx_data >= ASCII_0 && rx_data <= ASCII_9) begin
                            if (num_building) begin
                                num_buffer <= num_buffer * 10 + (rx_data - ASCII_0);
                            end else begin
                                num_buffer <= rx_data - ASCII_0;
                                num_building <= 1'b1;
                            end
                        end
                        else if (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF) begin
                            dim_n <= num_buffer[2:0];
                            data_total <= dim_m * num_buffer[2:0];
                            num_buffer <= 8'd0;
                            num_building <= 1'b0;
                        end
                    end
                end
                
                WAIT_DATA: begin
                    if (rx_valid) begin
                        if (rx_data >= ASCII_0 && rx_data <= ASCII_9) begin
                            if (num_building) begin
                                num_buffer <= num_buffer * 10 + (rx_data - ASCII_0);
                            end else begin
                                num_buffer <= rx_data - ASCII_0;
                                num_building <= 1'b1;
                            end
                        end
                        else if (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF) begin
                            case (mode_sel)
                                2'b01: begin  // INPUT
                                    if (data_cnt < data_total) begin
                                        elem_data <= num_buffer;
                                        write_en <= 1'b1;
                                        data_cnt <= data_cnt + 1;
                                    end
                                end
                                2'b10: begin  // GEN
                                    count <= num_buffer[3:0];
                                    data_cnt <= data_cnt + 1;
                                end
                                default: ;
                            endcase
                            
                            num_buffer <= 8'd0;
                            num_building <= 1'b0;
                        end
                    end
                end
                
                WAIT_ID_A: begin
                    if (rx_valid) begin
                        if (rx_data >= ASCII_0 && rx_data <= ASCII_9) begin
                            if (num_building) begin
                                num_buffer <= num_buffer * 10 + (rx_data - ASCII_0);
                            end else begin
                                num_buffer <= rx_data - ASCII_0;
                                num_building <= 1'b1;
                            end
                        end
                        else if (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF) begin
                            user_id_a <= num_buffer[3:0];
                            num_buffer <= 8'd0;
                            num_building <= 1'b0;
                        end
                    end
                end
                
                WAIT_ID_B: begin
                    if (rx_valid) begin
                        if (rx_data >= ASCII_0 && rx_data <= ASCII_9) begin
                            if (num_building) begin
                                num_buffer <= num_buffer * 10 + (rx_data - ASCII_0);
                            end else begin
                                num_buffer <= rx_data - ASCII_0;
                                num_building <= 1'b1;
                            end
                        end
                        else if (rx_data == ASCII_SPACE || rx_data == ASCII_CR || rx_data == ASCII_LF) begin
                            user_id_b <= num_buffer[3:0];
                            user_input_valid <= 1'b1;  // 标记用户输入完成
                            num_buffer <= 8'd0;
                            num_building <= 1'b0;
                        end
                    end
                end
                
                DONE: begin
                    data_ready <= 1'b1;
                end
                
                default: ;
            endcase
        end
    end

endmodule