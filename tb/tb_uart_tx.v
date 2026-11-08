// -----------------------------------------------------------------------------
// tb_uart_tx.v
//
// Self-checking testbench for rtl/uart_tx.v.
// Decodes the serial output at bit midpoints and compares against the bytes
// that were handed to the transmitter.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_uart_tx;

    // Small clock/baud numbers keep simulation fast while keeping the
    // divider exact (16 clocks per bit).
    localparam integer CLK_FREQ  = 1600;
    localparam integer BAUD_RATE = 100;
    localparam integer CPB       = CLK_FREQ / BAUD_RATE;

    reg        clk = 1'b0;
    reg        rst = 1'b1;
    reg        valid = 1'b0;
    reg  [7:0] data = 8'd0;
    wire       ready;
    wire       tx;
    wire       done;

    integer errors = 0;
    integer done_count = 0;

    always #5 clk = ~clk;

    // Watchdog so a handshake bug fails fast instead of hanging.
    initial begin
        #200000;
        $display("WATCHDOG: tx=%b ready=%b state=%0d clk_cnt=%0d bit_idx=%0d done_count=%0d",
                 tx, ready, dut.state, dut.clk_cnt, dut.bit_idx, done_count);
        $display("FAIL: tb_uart_tx timed out");
        $finish;
    end
    always @(posedge clk)
        if (done) done_count = done_count + 1;

    uart_tx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) dut (
        .clk   (clk),
        .rst   (rst),
        .valid (valid),
        .data  (data),
        .ready (ready),
        .tx    (tx),
        .done  (done)
    );

    task fail(input [255:0] msg);
        begin
            $display("FAIL @%0t: %0s", $time, msg);
            errors = errors + 1;
        end
    endtask

    // Wait for the falling start edge, then sample each bit at its midpoint.
    task check_frame(input [7:0] d);
        integer i;
        begin
            @(negedge tx);

            // Midpoint of start bit.
            repeat (CPB/2) @(posedge clk);
            if (tx !== 1'b0) fail("start bit not low");

            // Data bits, LSB first.
            for (i = 0; i < 8; i = i + 1) begin
                repeat (CPB) @(posedge clk);
                if (tx !== d[i]) begin
                    $display("FAIL @%0t: data bit %0d got %b expected %b",
                             $time, i, tx, d[i]);
                    errors = errors + 1;
                end
            end

            // Stop bit.
            repeat (CPB) @(posedge clk);
            if (tx !== 1'b1) fail("stop bit not high");
        end
    endtask

    // Hand a byte to the transmitter, then decode the resulting frame.
    task send(input [7:0] d);
        begin
            @(negedge clk);
            valid = 1'b1;
            data  = d;
            @(posedge clk);
            while (!ready) @(posedge clk);
            @(negedge clk);
            valid = 1'b0;
            check_frame(d);
        end
    endtask

    initial begin
        $dumpfile("build/tb_uart_tx.vcd");
        $dumpvars(0, tb_uart_tx);

        repeat (3) @(negedge clk);
        rst = 1'b0;
        repeat (3) @(negedge clk);

        if (tx !== 1'b1) fail("tx not idle high after reset");
        if (!ready)      fail("ready not high after reset");

        send(8'h55);
        send(8'hA3);
        send(8'h00);
        send(8'hFF);
        send(8'h01);
        send(8'h80);

        // Give the last stop bit time to finish.
        repeat (CPB) @(posedge clk);
        if (!ready) fail("not ready after all frames");
        if (tx !== 1'b1) fail("tx not idle high after all frames");
        if (done_count != 6) begin
            $display("FAIL @%0t: done pulses = %0d (expected 6)",
                     $time, done_count);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: tb_uart_tx");
        else
            $display("FAIL: tb_uart_tx with %0d error(s)", errors);

        $finish;
    end

endmodule
