module uart_rx #(
    parameter CLK_FREQ = 50_000_000,  // 修复：实际时钟是50MHz，不是100MHz
    parameter BAUD_RATE = 115200
)(
    input wire clk,
    input wire rst_n,
    input wire rx,
    output reg [7:0] rx_data,
    output reg rx_valid
);

    // 修复：使用更精确的波特率分频器计算
    // 50,000,000 / 115200 = 434.027...，使用434会有小误差，但通常可接受
    // 如果需要更精确，可以使用57600: 50,000,000 / 57600 = 868.055...
    localparam BAUD_DIV = CLK_FREQ / BAUD_RATE;
    
    // 调试：检查BAUD_DIV是否正确（综合时会警告如果不是整数）
    // 对于50MHz和115200: BAUD_DIV = 434
    // 对于50MHz和57600: BAUD_DIV = 868

    reg [15:0] baud_cnt;
    reg [3:0] bit_idx;
    reg [9:0] rx_shift;
    reg rx_busy;
    reg rx_d1, rx_d2;
    
    // 调试：添加状态寄存器用于观察
    reg rx_start_detected;  // 起始位检测标志
    reg [7:0] debug_rx_data;  // 调试用：最后接收的数据

    always @(posedge clk) begin
        rx_d1 <= rx;
        rx_d2 <= rx_d1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt <= 0;
            bit_idx <= 0;
            rx_busy <= 0;
            rx_valid <= 0;
            rx_data <= 8'b0;
            rx_start_detected <= 0;
            debug_rx_data <= 8'b0;
        end else begin
            rx_valid <= 0;
            rx_start_detected <= 0;
            
            if (!rx_busy) begin
                // 检测起始位（低电平）
                if (rx_d2 == 0) begin
                    rx_busy <= 1;
                    baud_cnt <= BAUD_DIV / 2;  // 从起始位中间开始，等待半个位时间后采样
                    bit_idx <= 0;
                    rx_start_detected <= 1;  // 调试：标记检测到起始位
                end
            end else begin
                // 波特率计数器
                if (baud_cnt >= BAUD_DIV - 1) begin
                    baud_cnt <= 0;
                    bit_idx <= bit_idx + 1;
                    
                    // UART接收时序（在每个数据位的中间采样）：
                    // bit_idx=0: 起始位，不采样
                    // bit_idx=1-8: 采样数据位 D0-D7 (LSB first)
                    // bit_idx=9: 停止位，输出数据
                    
                    if (bit_idx >= 1 && bit_idx <= 8) begin
                        // 采样当前数据位（LSB first）
                        // bit_idx=1时采样D0，bit_idx=8时采样D7
                        rx_shift[bit_idx - 1] <= rx_d2;
                    end else if (bit_idx == 9) begin
                        // 停止位：输出接收到的数据
                        rx_busy <= 0;
                        rx_data <= rx_shift[7:0];
                        rx_valid <= 1;
                        bit_idx <= 0;  // 复位bit_idx，准备接收下一个字节
                    end
                end else begin
                    baud_cnt <= baud_cnt + 1;
                end
            end
        end
    end
endmodule
