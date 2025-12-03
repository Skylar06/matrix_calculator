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

    // TODO: 实现 10 个状态的 FSM

endmodule