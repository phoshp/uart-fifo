// -----------------------------------------------------------------------------
// tb_uart_rx.v
//
// Self-checking testbench for rtl/uart_rx.v.
// Drives a synthetic 8N1 serial stream and checks recovered bytes, including
// back-to-back frames and a deliberate framing error (low stop bit).
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

`ifndef TB_CLK_FREQ
 `define TB_CLK_FREQ 1600
`endif
`ifndef TB_BAUD_RATE
 `define TB_BAUD_RATE 100
`endif

module tb_uart_rx;

    localparam integer CLK_FREQ  = `TB_CLK_FREQ;
    localparam integer BAUD_RATE = `TB_BAUD_RATE;
    localparam integer BIT_CLKS  = CLK_FREQ / BAUD_RATE; // 16 clocks/bit
    localparam integer TIMEOUT   = BIT_CLKS * 40;

    reg        clk = 1'b0;
    reg        rst = 1'b1;
    reg        rx  = 1'b1;

    wire [7:0] data_out;
    wire       data_valid;
    wire       frame_err;

    integer errors = 0;

    // Capture the last recovered byte / flag pulses.
    reg [7:0] captured;
    reg       got;
    reg       err_seen;
    integer   i;

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (data_valid) begin
            captured <= data_out;
            got      <= 1'b1;
        end
        if (frame_err)
            err_seen <= 1'b1;
    end

    uart_rx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) dut (
        .clk        (clk),
        .rst        (rst),
        .rx         (rx),
        .data_out   (data_out),
        .data_valid (data_valid),
        .frame_err  (frame_err)
    );

    task fail(input [255:0] msg);
        begin
            $display("FAIL @%0t: %0s", $time, msg);
            errors = errors + 1;
        end
    endtask

    task send_bit(input b);
        begin
            rx = b;
            repeat (BIT_CLKS) @(negedge clk);
        end
    endtask

    task send_byte(input [7:0] d);
        integer k;
        begin
            send_bit(1'b0);
            for (k = 0; k < 8; k = k + 1)
                send_bit(d[k]);
            send_bit(1'b1);
        end
    endtask

    task expect_byte(input [7:0] d);
        integer k;
        begin
            got = 1'b0;
            send_byte(d);
            for (k = 0; k < TIMEOUT && !got; k = k + 1)
                @(posedge clk);
            if (!got)
                fail("no data_valid pulse");
            else if (captured !== d) begin
                $display("FAIL @%0t: got %02h expected %02h",
                         $time, captured, d);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("build/tb_uart_rx.vcd");
        $dumpvars(0, tb_uart_rx);

        repeat (3) @(negedge clk);
        rst = 1'b0;
        repeat (3) @(negedge clk);

        got      = 1'b0;
        err_seen = 1'b0;
        captured = 8'd0;

        // Clean frames, including back-to-back ones.
        expect_byte(8'h55);
        expect_byte(8'h00);
        expect_byte(8'hFF);
        expect_byte(8'hA5);
        expect_byte(8'h3C);
        expect_byte(8'h81);

        if (err_seen) fail("unexpected frame error");

        // Framing error: valid start/data but stop bit forced low.
        err_seen = 1'b0;
        got      = 1'b0;
        send_bit(1'b0);
        for (i = 0; i < 8; i = i + 1)
            send_bit(i[0]);
        send_bit(1'b0);           // bad stop
        rx = 1'b1;
        repeat (BIT_CLKS * 4) @(posedge clk);

        if (!err_seen) fail("frame error not flagged");

        // Receiver must recover and decode the next good frame.
        expect_byte(8'h7E);

        if (errors == 0)
            $display("PASS: tb_uart_rx");
        else
            $display("FAIL: tb_uart_rx with %0d error(s)", errors);

        $finish;
    end

endmodule
