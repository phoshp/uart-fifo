// -----------------------------------------------------------------------------
// tb_uart_fifo.v
//
// Integration test: UART TX -> loopback wire -> UART RX, with FIFOs.
// A producer pushes bytes with backpressure (respecting tx_full) while a
// consumer drains the RX FIFO and checks every byte against the expected
// sequence. This exercises the FIFOs, both UART engines, and the handshake
// between the TX FIFO and the transmitter.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_uart_fifo;

    localparam integer CLK_FREQ  = 1600;
    localparam integer BAUD_RATE = 100;
    localparam integer BIT_CLKS  = CLK_FREQ / BAUD_RATE;
    localparam integer FIFO_DEPTH = 8;
    localparam integer N         = 16;   // bytes in flight
    localparam integer TIMEOUT   = BIT_CLKS * 10 * (N + 4);

    reg        clk = 1'b0;
    reg        rst = 1'b1;

    reg        tx_wr_en = 1'b0;
    reg  [7:0] tx_din = 8'd0;
    wire       tx_full;
    wire       tx_empty;
    wire [3:0] tx_count;

    wire       tx;
    wire       rx = tx;   // loopback

    reg        rx_rd_en = 1'b0;
    wire [7:0] rx_dout;
    wire       rx_empty;
    wire       rx_full;
    wire [3:0] rx_count;
    wire       rx_frame_err;

    reg  [7:0] expected [0:N-1];

    integer errors = 0;
    integer full_seen = 0;
    integer frame_err_seen = 0;
    integer i;

    always #5 clk = ~clk;

    uart_fifo #(
        .CLK_FREQ   (CLK_FREQ),
        .BAUD_RATE  (BAUD_RATE),
        .FIFO_DEPTH (FIFO_DEPTH)
    ) dut (
        .clk          (clk),
        .rst          (rst),
        .tx_wr_en     (tx_wr_en),
        .tx_din       (tx_din),
        .tx_full      (tx_full),
        .tx_empty     (tx_empty),
        .tx_count     (tx_count),
        .tx           (tx),
        .rx           (rx),
        .rx_rd_en     (rx_rd_en),
        .rx_dout      (rx_dout),
        .rx_empty     (rx_empty),
        .rx_full      (rx_full),
        .rx_count     (rx_count),
        .rx_frame_err (rx_frame_err)
    );

    task fail(input [255:0] msg);
        begin
            $display("FAIL @%0t: %0s", $time, msg);
            errors = errors + 1;
        end
    endtask

    // Observe backpressure and framing errors.
    always @(posedge clk) begin
        if (tx_full) full_seen = 1;
        if (rx_frame_err) frame_err_seen = 1;
    end

    // Producer: push all bytes, stalling while the TX FIFO is full.
    task producer;
        integer k;
        begin
            for (k = 0; k < N; k = k + 1) begin
                @(negedge clk);
                while (tx_full) @(negedge clk);
                tx_wr_en <= 1'b1;
                tx_din   <= expected[k];
                @(negedge clk);
                tx_wr_en <= 1'b0;
            end
        end
    endtask

    // Consumer: wait for bytes and pop them in order.
    task consumer;
        integer k;
        integer waited;
        begin
            k = 0;
            while (k < N) begin
                waited = 0;
                while (rx_empty && waited < TIMEOUT) begin
                    @(negedge clk);
                    waited = waited + 1;
                end

                if (rx_empty) begin
                    fail("timed out waiting for received byte");
                    k = N;
                end else begin
                    if (rx_dout !== expected[k]) begin
                        $display("FAIL @%0t: rx byte %0d = %02h, expected %02h",
                                 $time, k, rx_dout, expected[k]);
                        errors = errors + 1;
                    end
                    rx_rd_en <= 1'b1;
                    @(negedge clk);
                    rx_rd_en <= 1'b0;
                    k = k + 1;
                end
            end
        end
    endtask

    initial begin
        $dumpfile("build/tb_uart_fifo.vcd");
        $dumpvars(0, tb_uart_fifo);

        repeat (3) @(negedge clk);
        rst = 1'b0;
        repeat (3) @(negedge clk);

        if (!tx_empty) fail("TX FIFO not empty after reset");
        if (!rx_empty) fail("RX FIFO not empty after reset");
        if (tx_full)    fail("TX FIFO full after reset");
        if (rx_full)    fail("RX FIFO full after reset");
        if (tx_count !== 0) fail("TX count not zero after reset");
        if (rx_count !== 0) fail("RX count not zero after reset");

        for (i = 0; i < N; i = i + 1)
            expected[i] = $random;

        fork
            producer();
            consumer();
        join

        // Everything should have drained.
        repeat (BIT_CLKS * 2) @(negedge clk);
        if (!tx_empty) fail("TX FIFO not empty at end");
        if (!rx_empty) fail("RX FIFO not empty at end");
        if (frame_err_seen) fail("unexpected frame error");

        if (!full_seen)
            fail("backpressure never asserted tx_full");

        if (errors == 0)
            $display("PASS: tb_uart_fifo (%0d bytes looped back)", N);
        else
            $display("FAIL: tb_uart_fifo with %0d error(s)", errors);

        $finish;
    end

endmodule
