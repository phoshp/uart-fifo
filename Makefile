SHELL     := /bin/sh
IVERILOG  ?= iverilog
VVP       ?= vvp
VERILATOR ?= verilator
YOSYS     ?= yosys
GTKWAVE   ?= gtkwave

BUILD := build
RTL   := rtl/fifo.v rtl/uart_tx.v rtl/uart_rx.v rtl/uart_fifo.v
TESTS := tb_fifo tb_uart_tx tb_uart_rx tb_uart_fifo

.PHONY: all test test_real lint synth wave clean

all: test

$(BUILD):
	mkdir -p $(BUILD)

.PRECIOUS: $(BUILD)/%.vvp $(BUILD)/%.vcd

$(BUILD)/%.vvp: tb/%.v $(RTL) | $(BUILD)
	$(IVERILOG) -g2005 -Wall -o $@ $(RTL) $<

test: $(addprefix run_,$(TESTS))

run_%: $(BUILD)/%.vvp
	$(VVP) $(BUILD)/$*.vvp

# Receiver test with realistic 50 MHz / 115200 baud (non-exact divider).
test_real: | $(BUILD)
	$(IVERILOG) -g2005 -Wall -DTB_CLK_FREQ=50000000 -DTB_BAUD_RATE=115200 \
	    -o $(BUILD)/tb_uart_rx_real.vvp $(RTL) tb/tb_uart_rx.v
	$(VVP) $(BUILD)/tb_uart_rx_real.vvp

lint: | $(BUILD)
	$(VERILATOR) --lint-only -Wall --top-module uart_fifo $(RTL)

synth:
	$(YOSYS) -Q -p "read_verilog $(RTL); synth -top uart_fifo; stat"

$(BUILD)/%.vcd: $(BUILD)/%.vvp
	$(VVP) $<

# make wave_tb_uart_fifo
wave_%: $(BUILD)/%.vcd
	$(GTKWAVE) $< &

clean:
	rm -rf $(BUILD)
