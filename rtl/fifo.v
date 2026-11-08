// -----------------------------------------------------------------------------
// fifo.v
//
// First-word-fall-through (FWFT) synchronous FIFO.
//
//   - dout is combinational and always shows the oldest entry; it is valid
//     whenever `empty` is low.
//   - `rd_en` pops the current head. `wr_en` pushes `din` when not full.
//   - DEPTH must be a power of two (address is a straight wrap of the pointer).
//   - Simultaneous read and write are allowed.
//
// The extra pointer bit (ADDR_W) distinguishes full from empty without a
// separate element counter.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
`default_nettype none

module fifo #(
    parameter integer WIDTH  = 8,
    parameter integer DEPTH  = 16,
    // Do not override; derived from DEPTH so it can appear in the port list.
    parameter integer ADDR_W = $clog2(DEPTH)
) (
    input  wire             clk,
    input  wire             rst,      // synchronous, active high
    input  wire             wr_en,
    input  wire [WIDTH-1:0] din,
    input  wire             rd_en,
    output wire [WIDTH-1:0] dout,
    output wire             full,
    output wire             empty,
    output wire [ADDR_W:0]  count
);

    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_W:0]  wr_ptr;
    reg [ADDR_W:0]  rd_ptr;

    wire [ADDR_W-1:0] wr_addr = wr_ptr[ADDR_W-1:0];
    wire [ADDR_W-1:0] rd_addr = rd_ptr[ADDR_W-1:0];

    assign dout  = mem[rd_addr];
    assign empty = (wr_ptr == rd_ptr);
    assign full  = (wr_ptr[ADDR_W] != rd_ptr[ADDR_W]) &&
                   (wr_ptr[ADDR_W-1:0] == rd_ptr[ADDR_W-1:0]);
    assign count = wr_ptr - rd_ptr;

    always @(posedge clk) begin
        if (rst) begin
            wr_ptr <= {(ADDR_W+1){1'b0}};
            rd_ptr <= {(ADDR_W+1){1'b0}};
        end else begin
            if (wr_en && !full) begin
                mem[wr_addr] <= din;
                wr_ptr       <= wr_ptr + 1'b1;
            end
            if (rd_en && !empty) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
