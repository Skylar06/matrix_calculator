module ctrl_fsm (
    input clk,
    input rst_n,
    input [3:0] sw,        
    input [3:0] key,       
    input error_flag,
    input busy_flag,
    input done_flag,

    output [1:0] mode_sel,
    output [2:0] op_sel,
    output [7:0] countdown_val,
    output start_input,
    output start_gen,
    output tart_disp,
    output start_op,
    output tx_start
);

    localparam S_IDLE = 4'd0;
    localparam S_MENU = 4'd1;
    localparam S_INPUT = 4'd2;
    localparam S_GEN = 4'd3;
    localparam S_DISPLAY = 4'd4;
    localparam S_OP_SELECT = 4'd5;
    localparam S_OP_OPERAND = 4'd6;
    localparam S_OP_RUN = 4'd7;
    localparam S_OP_RESULT = 4'd8;
    localparam S_ERROR = 4'd9;

    reg [3:0] state, next_state;

    wire key_ok = ~key[0];
    wire key_back = ~key[1];
    wire [1:0] mode_sel_sw = sw[1:0];
    wire [1:0] op_sel_sw = sw[3:2];


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end


    always @(*) begin
        next_state = state;

        case (state)
            S_IDLE: begin
                next_state = S_MENU;
            end

            S_MENU: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (key_ok) begin
                    case (mode_sel_sw)
                        2'b00: next_state = S_INPUT;
                        2'b01: next_state = S_GEN;
                        2'b10: next_state = S_DISPLAY;
                        2'b11: next_state = S_OP_SELECT;
                        default: next_state = S_MENU;
                    endcase
                end
            end

            S_INPUT: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (key_back)
                    next_state = S_MENU;
            end

            S_GEN: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (done_flag || key_back)
                    next_state = S_MENU;
            end

            S_DISPLAY: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (key_back)
                    next_state = S_MENU;
            end

            S_OP_SELECT: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (key_back)
                    next_state = S_MENU;
                else if (key_ok)
                    next_state = S_OP_OPERAND;
            end

            S_OP_OPERAND: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (key_back)
                    next_state = S_MENU;
                else if (key_ok)
                    next_state = S_OP_RUN;
            end

            S_OP_RUN: begin
                if (error_flag)
                    next_state = S_ERROR;
                else if (done_flag)
                    next_state = S_OP_RESULT;
            end

            S_OP_RESULT: begin
                if (key_ok || key_back)
                    next_state = S_MENU;
            end

            S_ERROR: begin
                if (!error_flag || key_back)
                    next_state = S_MENU;
            end

            default: next_state = S_IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mode_sel <= 2'b00;
            op_sel <= 3'b000;
            countdown_val <= 8'd0;
            start_input <= 1'b0;
            start_gen <= 1'b0;
            start_disp <= 1'b0;
            start_op <= 1'b0;
            tx_start <= 1'b0;
        end else begin
            start_input <= 1'b0;
            start_gen <= 1'b0;
            start_disp <= 1'b0;
            start_op <= 1'b0;
            tx_start <= 1'b0;

            case (next_state)
                S_MENU: begin
                    mode_sel <= 2'b00;
                    countdown_val <= 8'd0;
                end

                S_INPUT: begin
                    mode_sel <= 2'b01;
                    start_input <= 1'b1;
                end

                S_GEN: begin
                    mode_sel <= 2'b10;
                    start_gen <= 1'b1;
                end

                S_DISPLAY: begin
                    mode_sel <= 2'b11;
                    start_disp <= 1'b1;
                end

                S_OP_SELECT: begin
                    mode_sel <= 2'b11;
                    op_sel <= {1'b0, op_sel_sw};
                end

                S_OP_OPERAND: begin
                end

                S_OP_RUN: begin
                    start_op <= 1'b1;
                end

                S_OP_RESULT: begin
                    tx_start <= 1'b1;
                end

                S_ERROR: begin
                    mode_sel <= 2'b00;
                end

                default: ;
            endcase
        end
    end

endmodule