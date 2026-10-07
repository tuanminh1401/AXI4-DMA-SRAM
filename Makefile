MODELSIM_DIR = /d/intelFPGA_lite/20.1/modelsim_ase/win32aloem
export PATH := $(MODELSIM_DIR):$(PATH)
VLOG = $(MODELSIM_DIR)/vlog -sv
VSIM = $(MODELSIM_DIR)/vsim

# Toàn bộ mã nguồn RTL của DMA và SRAM Slave Core
SRC_RTL = src/dma_csr.sv \
          src/dma_fifo.sv \
          src/dma_read_master.sv \
          src/dma_write_master.sv \
          src/dma_top.sv \
          src/burst_addr_gen.sv \
          src/write_controller.sv \
          src/read_controller.sv \
          src/sram_4bank_core.sv \
          src/axi_slave_sram_top.sv

SRC_TB = tb/tb_dma_sram_system.sv
TOP_TB = tb_dma_sram_system

.PHONY: all compile sim gui clean
all: sim
compile:
	@if [ ! -d "work" ]; then $(MODELSIM_DIR)/vlib work; fi
	$(VLOG) $(SRC_RTL) $(SRC_TB)
sim: compile
	$(VSIM) -c -do "run -all; quit" $(TOP_TB)
gui: compile
	$(VSIM) -do "add wave -r /*; run -all" $(TOP_TB)
clean:
	rm -rf work transcript *.wlf