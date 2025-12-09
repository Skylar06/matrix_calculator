module operand_selector (
    input wire clk,
    input wire rst_n,
    input wire start_select,
    input wire manual_mode,
    input wire [2:0] op_type,
    
    input wire [3:0] user_id_a,
    input wire [3:0] user_id_b,
    input wire user_input_valid,
    
    input wire [2:0] meta_m [0:9],
    input wire [2:0] meta_n [0:9],
    input wire meta_valid [0:9],
    
    output reg [3:0] selected_a,
    output reg [3:0] selected_b,
    output reg select_done,
    output reg select_error
);

    localparam OP_TRANSPOSE = 3'b000;
    localparam OP_ADD       = 3'b001;
    localparam OP_SCALAR    = 3'b010;
    localparam OP_MULTIPLY  = 3'b011;
    localparam OP_CONV      = 3'b100;
    
    localparam IDLE      = 3'd0;
    localparam WAIT_INPUT = 3'd1;
    localparam RANDOM_GEN = 3'd2;
    localparam VALIDATE   = 3'd3;
    localparam DONE       = 3'd4;
    localparam ERROR      = 3'd5;
    
    reg [2:0] state;
    
    reg [15:0] lfsr;
    wire [3:0] random_id;
    wire lfsr_feedback;
    
    assign lfsr_feedback = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];
    assign random_id = (lfsr[3:0] >= 10) ? (lfsr[3:0] - 10) : lfsr[3:0];
    
    reg [3:0] try_cnt;
    localparam MAX_TRIES = 4'd10;
    reg selecting_a;
    
    reg [2:0] temp_m_a, temp_n_a, temp_m_b, temp_n_b;
    reg temp_valid_a, temp_valid_b;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            selected_a <= 4'd0;
            selected_b <= 4'd0;
            select_done <= 1'b0;
            select_error <= 1'b0;
            lfsr <= 16'hACE1;
            try_cnt <= 4'd0;
            selecting_a <= 1'b1;
            temp_m_a <= 3'd0;
            temp_n_a <= 3'd0;
            temp_m_b <= 3'd0;
            temp_n_b <= 3'd0;
            temp_valid_a <= 1'b0;
            temp_valid_b <= 1'b0;
        end else begin
            lfsr <= {lfsr[14:0], lfsr_feedback};
            
            case (state)
                IDLE: begin
                    select_done <= 1'b0;
                    select_error <= 1'b0;
                    try_cnt <= 4'd0;
                    selecting_a <= 1'b1;
                    
                    if (start_select) begin
                        if (manual_mode)
                            state <= WAIT_INPUT;
                        else
                            state <= RANDOM_GEN;
                    end
                end
                
                WAIT_INPUT: begin
                    if (user_input_valid) begin
                        selected_a <= user_id_a;
                        selected_b <= user_id_b;
                        temp_valid_a <= meta_valid[user_id_a];
                        temp_valid_b <= meta_valid[user_id_b];
                        temp_m_a <= meta_m[user_id_a];
                        temp_n_a <= meta_n[user_id_a];
                        temp_m_b <= meta_m[user_id_b];
                        temp_n_b <= meta_n[user_id_b];
                        state <= VALIDATE;
                    end
                end
                
                RANDOM_GEN: begin
                    if (try_cnt >= MAX_TRIES) begin
                        select_error <= 1'b1;
                        state <= ERROR;
                    end else begin
                        if (selecting_a) begin
                            temp_valid_a <= meta_valid[random_id];
                            if (meta_valid[random_id]) begin
                                selected_a <= random_id;
                                temp_m_a <= meta_m[random_id];
                                temp_n_a <= meta_n[random_id];
                                selecting_a <= 1'b0;
                                try_cnt <= 4'd0;
                            end else begin
                                try_cnt <= try_cnt + 1;
                            end
                        end else begin
                            temp_valid_b <= meta_valid[random_id];
                            if (meta_valid[random_id]) begin
                                selected_b <= random_id;
                                temp_m_b <= meta_m[random_id];
                                temp_n_b <= meta_n[random_id];
                                state <= VALIDATE;
                            end else begin
                                try_cnt <= try_cnt + 1;
                            end
                        end
                    end
                end
                
                VALIDATE: begin
                    select_error <= 1'b0;
                    
                    if (!temp_valid_a) begin
                        select_error <= 1'b1;
                        state <= ERROR;
                    end
                    else if (op_type == OP_TRANSPOSE || op_type == OP_SCALAR) begin
                        state <= DONE;
                    end
                    else if (!temp_valid_b) begin
                        select_error <= 1'b1;
                        state <= ERROR;
                    end
                    else if (op_type == OP_ADD) begin
                        if (temp_m_a == temp_m_b && temp_n_a == temp_n_b) begin
                            state <= DONE;
                        end else begin
                            select_error <= 1'b1;
                            state <= ERROR;
                        end
                    end
                    else if (op_type == OP_MULTIPLY) begin
                        if (temp_n_a == temp_m_b) begin
                            state <= DONE;
                        end else begin
                            select_error <= 1'b1;
                            state <= ERROR;
                        end
                    end
                    else if (op_type == OP_CONV) begin
                        if (temp_m_b <= temp_m_a && temp_n_b <= temp_n_a) begin
                            state <= DONE;
                        end else begin
                            select_error <= 1'b1;
                            state <= ERROR;
                        end
                    end
                    else begin
                        state <= DONE;
                    end
                end
                
                DONE: begin
                    select_done <= 1'b1;
                    state <= IDLE;
                end
                
                ERROR: begin
                    select_error <= 1'b1;
                    if (start_select)
                        state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule