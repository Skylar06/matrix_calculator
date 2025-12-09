module display_formatter (
    input wire clk,
    input wire rst_n,
    input wire start_format,
    input wire [1:0] display_mode,
    
    input wire [3:0] matrix_id,
    input wire [2:0] dim_m,
    input wire [2:0] dim_n,
    input wire [7:0] matrix_data,
    input wire matrix_data_valid,
    
    input wire [2:0] list_m [0:9],
    input wire [2:0] list_n [0:9],
    input wire list_valid [0:9],
    
    output reg [7:0] tx_data,
    output reg tx_valid,
    input wire tx_busy,
    
    output reg format_done
);

    localparam IDLE           = 4'd0;
    localparam SEND_HEADER    = 4'd1;
    localparam SEND_MATRIX    = 4'd2;
    localparam SEND_NEWLINE   = 4'd3;
    localparam SEND_LIST      = 4'd4;
    localparam DONE           = 4'd5;
    
    reg [3:0] state;
    
    reg [7:0] header_buffer [0:31];
    reg [4:0] header_len;
    reg [4:0] char_idx;
    
    reg [4:0] elem_cnt;
    reg [4:0] elem_total;
    reg [2:0] col_cnt;
    
    reg [3:0] list_idx;
    
    reg [2:0] current_m, current_n;
    reg [3:0] current_id;
    
    function [7:0] digit_to_ascii;
        input [3:0] digit;
        begin
            digit_to_ascii = 8'd48 + digit;
        end
    endfunction
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            tx_data <= 8'd0;
            tx_valid <= 1'b0;
            format_done <= 1'b0;
            char_idx <= 5'd0;
            elem_cnt <= 5'd0;
            col_cnt <= 3'd0;
            list_idx <= 4'd0;
            header_len <= 5'd0;
            current_m <= 3'd0;
            current_n <= 3'd0;
            current_id <= 4'd0;
        end else begin
            case (state)
                IDLE: begin
                    format_done <= 1'b0;
                    tx_valid <= 1'b0;
                    char_idx <= 5'd0;
                    elem_cnt <= 5'd0;
                    col_cnt <= 3'd0;
                    list_idx <= 4'd0;
                    
                    if (start_format) begin
                        current_m <= dim_m;
                        current_n <= dim_n;
                        current_id <= matrix_id;
                        elem_total <= dim_m * dim_n;
                        
                        case (display_mode)
                            2'd0: begin
                                header_buffer[0]  <= 8'd77;
                                header_buffer[1]  <= 8'd97;
                                header_buffer[2]  <= 8'd116;
                                header_buffer[3]  <= 8'd114;
                                header_buffer[4]  <= 8'd105;
                                header_buffer[5]  <= 8'd120;
                                header_buffer[6]  <= 8'd32;
                                header_buffer[7]  <= digit_to_ascii(matrix_id);
                                header_buffer[8]  <= 8'd32;
                                header_buffer[9]  <= 8'd40;
                                header_buffer[10] <= digit_to_ascii(dim_m);
                                header_buffer[11] <= 8'd120;
                                header_buffer[12] <= digit_to_ascii(dim_n);
                                header_buffer[13] <= 8'd41;
                                header_buffer[14] <= 8'd58;
                                header_buffer[15] <= 8'd10;
                                header_len <= 5'd16;
                                state <= SEND_HEADER;
                            end
                            2'd1: begin
                                header_buffer[0]  <= 8'd65;
                                header_buffer[1]  <= 8'd118;
                                header_buffer[2]  <= 8'd97;
                                header_buffer[3]  <= 8'd105;
                                header_buffer[4]  <= 8'd108;
                                header_buffer[5]  <= 8'd97;
                                header_buffer[6]  <= 8'd98;
                                header_buffer[7]  <= 8'd108;
                                header_buffer[8]  <= 8'd101;
                                header_buffer[9]  <= 8'd32;
                                header_buffer[10] <= 8'd77;
                                header_buffer[11] <= 8'd97;
                                header_buffer[12] <= 8'd116;
                                header_buffer[13] <= 8'd114;
                                header_buffer[14] <= 8'd105;
                                header_buffer[15] <= 8'd99;
                                header_buffer[16] <= 8'd101;
                                header_buffer[17] <= 8'd115;
                                header_buffer[18] <= 8'd58;
                                header_buffer[19] <= 8'd10;
                                header_len <= 5'd20;
                                state <= SEND_HEADER;
                            end
                            2'd2: begin
                                header_buffer[0]  <= 8'd82;
                                header_buffer[1]  <= 8'd101;
                                header_buffer[2]  <= 8'd115;
                                header_buffer[3]  <= 8'd117;
                                header_buffer[4]  <= 8'd108;
                                header_buffer[5]  <= 8'd116;
                                header_buffer[6]  <= 8'd32;
                                header_buffer[7]  <= 8'd40;
                                header_buffer[8]  <= digit_to_ascii(dim_m);
                                header_buffer[9]  <= 8'd120;
                                header_buffer[10] <= digit_to_ascii(dim_n);
                                header_buffer[11] <= 8'd41;
                                header_buffer[12] <= 8'd58;
                                header_buffer[13] <= 8'd10;
                                header_len <= 5'd14;
                                state <= SEND_HEADER;
                            end
                            default: state <= IDLE;
                        endcase
                    end
                end
                
                SEND_HEADER: begin
                    if (!tx_busy) begin
                        if (char_idx < header_len) begin
                            tx_data <= header_buffer[char_idx];
                            tx_valid <= 1'b1;
                            char_idx <= char_idx + 1;
                        end else begin
                            tx_valid <= 1'b0;
                            char_idx <= 5'd0;
                            
                            if (display_mode == 2'd1)
                                state <= SEND_LIST;
                            else
                                state <= SEND_MATRIX;
                        end
                    end else begin
                        tx_valid <= 1'b0;
                    end
                end
                
                SEND_MATRIX: begin
                    if (matrix_data_valid && !tx_busy) begin
                        if (char_idx == 0) begin
                            if (matrix_data >= 10) begin
                                tx_data <= digit_to_ascii(matrix_data / 10);
                                tx_valid <= 1'b1;
                                char_idx <= 5'd1;
                            end else begin
                                char_idx <= 5'd1;
                            end
                        end
                        else if (char_idx == 1) begin
                            tx_data <= digit_to_ascii(matrix_data % 10);
                            tx_valid <= 1'b1;
                            char_idx <= 5'd2;
                        end
                        else if (char_idx == 2) begin
                            col_cnt <= col_cnt + 1;
                            elem_cnt <= elem_cnt + 1;
                            
                            if (col_cnt >= current_n - 1) begin
                                tx_data <= 8'd10;
                                col_cnt <= 3'd0;
                            end else begin
                                tx_data <= 8'd32;
                            end
                            tx_valid <= 1'b1;
                            char_idx <= 5'd0;
                            
                            if (elem_cnt >= elem_total - 1) begin
                                state <= SEND_NEWLINE;
                            end
                        end
                    end else begin
                        tx_valid <= 1'b0;
                    end
                end
                
                SEND_LIST: begin
                    if (!tx_busy) begin
                        if (list_idx < 10) begin
                            if (char_idx == 0) begin
                                tx_data <= 8'd91;
                                tx_valid <= 1'b1;
                                char_idx <= 5'd1;
                            end
                            else if (char_idx == 1) begin
                                tx_data <= digit_to_ascii(list_idx);
                                tx_valid <= 1'b1;
                                char_idx <= 5'd2;
                            end
                            else if (char_idx == 2) begin
                                tx_data <= 8'd93;
                                tx_valid <= 1'b1;
                                char_idx <= 5'd3;
                            end
                            else if (char_idx == 3) begin
                                tx_data <= 8'd32;
                                tx_valid <= 1'b1;
                                char_idx <= 5'd4;
                            end
                            else if (char_idx == 4) begin
                                if (list_valid[list_idx]) begin
                                    tx_data <= digit_to_ascii(list_m[list_idx]);
                                    tx_valid <= 1'b1;
                                    char_idx <= 5'd5;
                                end else begin
                                    tx_data <= 8'd69;
                                    tx_valid <= 1'b1;
                                    char_idx <= 5'd9;
                                end
                            end
                            else if (char_idx == 5) begin
                                tx_data <= 8'd120;
                                tx_valid <= 1'b1;
                                char_idx <= 5'd6;
                            end
                            else if (char_idx == 6) begin
                                tx_data <= digit_to_ascii(list_n[list_idx]);
                                tx_valid <= 1'b1;
                                char_idx <= 5'd7;
                            end
                            else if (char_idx == 7) begin
                                tx_data <= 8'd10;
                                tx_valid <= 1'b1;
                                char_idx <= 5'd0;
                                list_idx <= list_idx + 1;
                            end
                            else if (char_idx == 9) begin
                                tx_data <= 8'd109;
                                tx_valid <= 1'b1;
                                char_idx <= 5'd10;
                            end
                            else if (char_idx == 10) begin
                                tx_data <= 8'd112;
                                tx_valid <= 1'b1;
                                char_idx <= 5'd11;
                            end
                            else if (char_idx == 11) begin
                                tx_data <= 8'd116;
                                tx_valid <= 1'b1;
                                char_idx <= 5'd12;
                            end
                            else if (char_idx == 12) begin
                                tx_data <= 8'd121;
                                tx_valid <= 1'b1;
                                char_idx <= 5'd13;
                            end
                            else if (char_idx == 13) begin
                                tx_data <= 8'd10;
                                tx_valid <= 1'b1;
                                char_idx <= 5'd0;
                                list_idx <= list_idx + 1;
                            end
                        end else begin
                            state <= DONE;
                        end
                    end else begin
                        tx_valid <= 1'b0;
                    end
                end
                
                SEND_NEWLINE: begin
                    if (!tx_busy) begin
                        tx_data <= 8'd10;
                        tx_valid <= 1'b1;
                        state <= DONE;
                    end else begin
                        tx_valid <= 1'b0;
                    end
                end
                
                DONE: begin
                    tx_valid <= 1'b0;
                    format_done <= 1'b1;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule