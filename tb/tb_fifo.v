// -----------------------------------------------------------------------------
// tb_fifo.v
//
// Self-checking testbench for rtl/fifo.v.
//   1. Reset / empty / full defaults
//   2. Fill to capacity, verify full, verify writes are ignored when full
//   3. Drain, verify order and empty
//   4. Thousands of randomized simultaneous read/write operations against a
//      golden queue
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_fifo;

    localparam integer WIDTH  = 8;
    localparam integer DEPTH  = 8;
    localparam integer ADDR_W = $clog2(DEPTH);
    localparam integer MODEL_DEPTH = 256;

    reg  clk = 1'b0;
    reg  rst = 1'b1;
    reg  wr_en = 1'b0;
    reg  rd_en = 1'b0;
    reg  [WIDTH-1:0] din = {WIDTH{1'b0}};
    wire [WIDTH-1:0] dout;
    wire full;
    wire empty;
    wire [ADDR_W:0] count;

    // Golden model: circular queue of accepted elements.
    reg  [WIDTH-1:0] model [0:MODEL_DEPTH-1];
    integer head = 0;
    integer tail = 0;

    integer errors = 0;
    integer i, n;

    always #5 clk = ~clk;

    fifo #(
        .WIDTH  (WIDTH),
        .DEPTH  (DEPTH),
        .ADDR_W (ADDR_W)
    ) dut (
        .clk   (clk),
        .rst   (rst),
        .wr_en (wr_en),
        .din   (din),
        .rd_en (rd_en),
        .dout  (dout),
        .full  (full),
        .empty (empty),
        .count (count)
    );

    task fail(input [255:0] msg);
        begin
            $display("FAIL @%0t: %0s", $time, msg);
            errors = errors + 1;
        end
    endtask

    // Push a value (caller guarantees the FIFO is not full).
    task push(input [WIDTH-1:0] v);
        begin
            @(negedge clk);
            wr_en = 1'b1;
            din   = v;
            @(negedge clk);
            wr_en = 1'b0;
            model[tail] = v;
            tail = (tail + 1) % MODEL_DEPTH;
        end
    endtask

    // Pop and compare with the golden model (caller guarantees not empty).
    task pop;
        begin
            @(negedge clk);
            if (empty) begin
                fail("pop while empty");
            end else begin
                if (dout !== model[head]) begin
                    $display("FAIL @%0t: pop got %02h expected %02h",
                             $time, dout, model[head]);
                    errors = errors + 1;
                end
                head = (head + 1) % MODEL_DEPTH;
                rd_en = 1'b1;
                @(negedge clk);
                rd_en = 1'b0;
            end
        end
    endtask

    initial begin
        $dumpfile("build/tb_fifo.vcd");
        $dumpvars(0, tb_fifo);

        // Reset.
        repeat (3) @(negedge clk);
        rst = 1'b0;
        repeat (2) @(negedge clk);

        if (!empty) fail("empty not asserted after reset");
        if (full)   fail("full asserted after reset");
        if (count !== 0) fail("count not zero after reset");

        // ---- Fill to capacity -------------------------------------------
        for (i = 0; i < DEPTH; i = i + 1)
            push(i[WIDTH-1:0]);

        if (!full) fail("full not asserted at capacity");
        if (empty) fail("empty asserted while full");
        if (count !== DEPTH) fail("count wrong at capacity");

        // Writes while full must be ignored.
        @(negedge clk);
        wr_en = 1'b1;
        din   = 8'hEE;
        @(negedge clk);
        wr_en = 1'b0;
        if (count !== DEPTH) fail("count changed on write-while-full");

        // ---- Drain and check order --------------------------------------
        for (i = 0; i < DEPTH; i = i + 1)
            pop;

        if (!empty) fail("empty not asserted after drain");
        if (full)   fail("full still asserted after drain");
        if (count !== 0) fail("count not zero after drain");

        // Reset the golden model indices; FIFO is empty so this is safe.
        head = 0;
        tail = 0;

        // ---- Randomized stress ------------------------------------------
        for (n = 0; n < 4000; n = n + 1) begin
            // State at this negedge reflects the previous posedge's commit.
            if (count !== ((tail - head + MODEL_DEPTH) % MODEL_DEPTH))
                fail("count does not match golden model");

            wr_en = $random;
            rd_en = $random;
            din   = $random;

            if (wr_en && !full) begin
                model[tail] = din;
                tail = (tail + 1) % MODEL_DEPTH;
            end

            if (rd_en && !empty) begin
                if (dout !== model[head]) begin
                    $display("FAIL @%0t: stress pop got %02h expected %02h",
                             $time, dout, model[head]);
                    errors = errors + 1;
                end
                head = (head + 1) % MODEL_DEPTH;
            end

            @(negedge clk);
        end

        // ---- Drain whatever is left -------------------------------------
        wr_en = 1'b0;
        while (!empty) begin
            if (dout !== model[head]) begin
                $display("FAIL @%0t: drain got %02h expected %02h",
                         $time, dout, model[head]);
                errors = errors + 1;
            end
            head = (head + 1) % MODEL_DEPTH;
            rd_en = 1'b1;
            @(negedge clk);
        end
        rd_en = 1'b0;
        repeat (2) @(negedge clk);

        if (!empty) fail("FIFO not empty at end of test");
        if (count !== 0) fail("count not zero at end of test");

        if (errors == 0)
            $display("PASS: tb_fifo (%0d directed checks + stress)", DEPTH);
        else
            $display("FAIL: tb_fifo with %0d error(s)", errors);

        $finish;
    end

endmodule
