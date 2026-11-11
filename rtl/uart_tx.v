// -----------------------------------------------------------------------------
// uart_tx.v
//
// 8N1 UART transmitter (1 start bit, 8 data bits LSB-first, 1 stop bit).
//
// Handshake: `valid`/`ready`, AXI-Stream style. A byte is accepted on a clock
// edge where both are high. `ready` is high while the transmitter is idle.
// `done` pulses for one clock at the end of the stop bit.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
`default_nettype none

module uart_tx #(
    parameter integer CLK_FREQ  = 50_000_000,
    parameter integer BAUD_RATE = 115200
) (
    input  wire       clk,
    input  wire       rst,     // synchronous, active high
    input  wire       valid,
    input  wire [7:0] data,
    output wire       ready,
    output wire       tx,
    output wire       done
);

    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam integer CNT_W        = (CLKS_PER_BIT > 1) ? $clog2(CLKS_PER_BIT) : 1;
    /* verilator lint_off WIDTHTRUNC */
    localparam [CNT_W-1:0] LAST     = CLKS_PER_BIT - 1;
    /* verilator lint_on WIDTHTRUNC */

    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    reg [1:0]       state;
    reg [CNT_W-1:0] clk_cnt;
    reg [2:0]       bit_idx;
    reg [7:0]       shift;
    reg             tx_r;
    reg             done_r;

    assign tx    = tx_r;
    assign ready = (state == S_IDLE);
    assign done  = done_r;

    always @(posedge clk) begin
        if (rst) begin
            state   <= S_IDLE;
            clk_cnt <= {CNT_W{1'b0}};
            bit_idx <= 3'd0;
            shift   <= 8'd0;
            tx_r    <= 1'b1;
            done_r  <= 1'b0;
        end else begin
            done_r <= 1'b0;

            case (state)
                S_IDLE: begin
                    tx_r    <= 1'b1;
                    clk_cnt <= {CNT_W{1'b0}};
                    if (valid) begin
                        shift <= data;
                        state <= S_START;
                    end
                end

                S_START: begin
                    tx_r <= 1'b0;
                    if (clk_cnt == LAST) begin
                        clk_cnt <= {CNT_W{1'b0}};
                        bit_idx <= 3'd0;
                        state   <= S_DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                S_DATA: begin
                    tx_r <= shift[bit_idx];
                    if (clk_cnt == LAST) begin
                        clk_cnt <= {CNT_W{1'b0}};
                        if (bit_idx == 3'd7)
                            state <= S_STOP;
                        else
                            bit_idx <= bit_idx + 1'b1;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                S_STOP: begin
                    tx_r <= 1'b1;
                    if (clk_cnt == LAST) begin
                        clk_cnt <= {CNT_W{1'b0}};
                        done_r  <= 1'b1;
                        state   <= S_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
