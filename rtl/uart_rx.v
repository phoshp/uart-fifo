// -----------------------------------------------------------------------------
// uart_rx.v
//
// 8N1 UART receiver with 16x oversampling.
//
// The incoming line is passed through a 2-flop synchronizer. A high-to-low
// transition arms the receiver; the start bit is verified at its midpoint,
// then every data bit is sampled at its midpoint. `data_valid` pulses for one
// clock on a good stop bit; `frame_err` pulses for one clock if the stop bit
// is low.
//
// Falling edges are latched so a start bit is not missed between sample ticks.
// A still-low line (e.g. after a framing error) cannot retrigger a frame until
// it has gone high again.
//
// Note: CLK_FREQ must be at least BAUD_RATE * 16.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
`default_nettype none

module uart_rx #(
    parameter integer CLK_FREQ  = 50_000_000,
    parameter integer BAUD_RATE = 115200
) (
    input  wire       clk,
    input  wire       rst,     // synchronous, active high
    input  wire       rx,
    output reg  [7:0] data_out,
    output reg        data_valid,
    output reg        frame_err
);

    localparam integer OVERSAMPLE    = 16;
    localparam integer CLKS_PER_SMPL = CLK_FREQ / (BAUD_RATE * OVERSAMPLE);
    localparam integer CNT_W         = (CLKS_PER_SMPL > 1) ? $clog2(CLKS_PER_SMPL) : 1;
    /* verilator lint_off WIDTHTRUNC */
    localparam [CNT_W-1:0] LAST_SMPL = CLKS_PER_SMPL - 1;
    localparam [3:0]       LAST_SMP  = OVERSAMPLE - 1;
    /* verilator lint_on WIDTHTRUNC */
    localparam [3:0]       MID       = 4'd7;   // OVERSAMPLE / 2 - 1

    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    reg [1:0]       state;
    reg [CNT_W-1:0] clk_cnt;
    reg [3:0]       sample_cnt;
    reg [2:0]       bit_idx;
    reg [7:0]       shift;
    reg             start_valid;

    reg rx_sync0;
    reg rx_sync1;
    reg rx_prev;
    reg start_pending;

    wire rx_s = rx_sync1;
    wire fall = !rx_s && rx_prev;

    always @(posedge clk) begin
        if (rst) begin
            state         <= S_IDLE;
            clk_cnt       <= {CNT_W{1'b0}};
            sample_cnt    <= 4'd0;
            bit_idx       <= 3'd0;
            shift         <= 8'd0;
            start_valid   <= 1'b0;
            rx_sync0      <= 1'b1;
            rx_sync1      <= 1'b1;
            rx_prev       <= 1'b1;
            start_pending <= 1'b0;
            data_out      <= 8'd0;
            data_valid    <= 1'b0;
            frame_err     <= 1'b0;
        end else begin
            // Input synchronizer and edge detect.
            rx_sync0 <= rx;
            rx_sync1 <= rx_sync0;
            rx_prev  <= rx_s;

            // Latch any falling edge so a start bit is not lost between
            // sample ticks. Outside IDLE, edges are ignored.
            if (fall)
                start_pending <= 1'b1;
            else if (state != S_IDLE)
                start_pending <= 1'b0;

            data_valid <= 1'b0;
            frame_err  <= 1'b0;

            if (clk_cnt == LAST_SMPL) begin
                clk_cnt <= {CNT_W{1'b0}};

                case (state)
                    S_IDLE: begin
                        if (start_pending || fall) begin
                            state         <= S_START;
                            sample_cnt    <= 4'd0;
                            start_valid   <= 1'b0;
                            start_pending <= 1'b0;
                        end
                    end

                    S_START: begin
                        if (sample_cnt == MID) begin
                            if (!rx_s) begin
                                start_valid <= 1'b1;
                                sample_cnt  <= sample_cnt + 1'b1;
                            end else begin
                                // Glitch, not a real start bit.
                                state      <= S_IDLE;
                                sample_cnt <= 4'd0;
                            end
                        end else if (sample_cnt == LAST_SMP) begin
                            sample_cnt <= 4'd0;
                            if (start_valid) begin
                                state   <= S_DATA;
                                bit_idx <= 3'd0;
                            end else begin
                                state <= S_IDLE;
                            end
                        end else begin
                            sample_cnt <= sample_cnt + 1'b1;
                        end
                    end

                    S_DATA: begin
                        if (sample_cnt == MID)
                            shift[bit_idx] <= rx_s;

                        if (sample_cnt == LAST_SMP) begin
                            sample_cnt <= 4'd0;
                            if (bit_idx == 3'd7)
                                state <= S_STOP;
                            else
                                bit_idx <= bit_idx + 1'b1;
                        end else begin
                            sample_cnt <= sample_cnt + 1'b1;
                        end
                    end

                    S_STOP: begin
                        if (sample_cnt == MID) begin
                            if (rx_s) begin
                                data_out   <= shift;
                                data_valid <= 1'b1;
                            end else begin
                                frame_err  <= 1'b1;
                            end
                            state      <= S_IDLE;
                            sample_cnt <= 4'd0;
                        end else begin
                            sample_cnt <= sample_cnt + 1'b1;
                        end
                    end

                    default: state <= S_IDLE;
                endcase
            end else begin
                clk_cnt <= clk_cnt + 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
