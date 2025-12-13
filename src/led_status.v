module led_status (
    input wire clk,
    input wire rst_n,
    input wire error_flag,      // 错误标志
    input wire busy_flag,       // 忙碌标志
    input wire done_flag,       // 完成标志
    
    output reg [2:0] led        // LED输出 [2]=DONE, [1]=BUSY, [0]=ERROR
);

    // LED位定义
    localparam LED_ERROR = 0;   // led[0] - J3 - 错误指示
    localparam LED_BUSY  = 1;   // led[1] - J2 - 忙碌指示
    localparam LED_DONE  = 2;   // led[2] - K2 - 完成指示
    
    // 闪烁控制参数
    localparam CLK_FREQ = 50_000_000;  // 修复：实际时钟是50MHz
    localparam BLINK_FREQ = 2;          // 2Hz闪烁频率(每秒闪2次)
    localparam BLINK_DIV = CLK_FREQ / (BLINK_FREQ * 2); // 除以2是因为要产生50%占空比
    
    reg [25:0] blink_cnt;
    reg blink_state;            // 闪烁状态(0或1)
    
    // 闪烁计数器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            blink_cnt <= 26'd0;
            blink_state <= 1'b0;
        end else begin
            if (blink_cnt >= BLINK_DIV - 1) begin
                blink_cnt <= 26'd0;
                blink_state <= ~blink_state; // 翻转闪烁状态
            end else begin
                blink_cnt <= blink_cnt + 1;
            end
        end
    end
    
    // LED状态寄存器(用于保持DONE状态)
    reg done_latch;
    reg [25:0] done_timer;      // DONE灯持续时间计数器
    localparam DONE_TIME = CLK_FREQ * 3; // DONE灯亮3秒
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done_latch <= 1'b0;
            done_timer <= 26'd0;
        end else begin
            // 当done_flag上升沿到来时,锁存DONE状态
            if (done_flag && !done_latch) begin
                done_latch <= 1'b1;
                done_timer <= 26'd0;
            end
            // DONE状态保持一段时间后自动清除
            else if (done_latch) begin
                if (done_timer >= DONE_TIME - 1) begin
                    done_latch <= 1'b0;
                    done_timer <= 26'd0;
                end else begin
                    done_timer <= done_timer + 1;
                end
            end
            // 如果有新的busy或error,清除done状态
            if (busy_flag || error_flag) begin
                done_latch <= 1'b0;
                done_timer <= 26'd0;
            end
        end
    end
    
    // LED输出控制
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            led <= 3'b000;
        end else begin
            // ERROR LED - 有错误时闪烁,无错误时熄灭
            if (error_flag)
                led[LED_ERROR] <= blink_state; // 闪烁
            else
                led[LED_ERROR] <= 1'b0;        // 熄灭
            
            // BUSY LED - 忙碌时常亮
            if (busy_flag)
                led[LED_BUSY] <= 1'b1;         // 常亮
            else
                led[LED_BUSY] <= 1'b0;         // 熄灭
            
            // DONE LED - 完成时保持亮3秒,然后熄灭
            if (done_latch)
                led[LED_DONE] <= 1'b1;         // 常亮
            else
                led[LED_DONE] <= 1'b0;         // 熄灭
        end
    end

endmodule