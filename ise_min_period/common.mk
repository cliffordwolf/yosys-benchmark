SHELL=bash -O nullglob
export PATH := ${PATH}:/opt/Xilinx/14.7/ISE_DS/ISE/bin/lin64

#BENCHMARKS+="verilog/benchmarks_small/various/dynamic_shift_register_1.v"
#BENCHMARKS+="verilog/benchmarks_small/various/mux_16_1_subm.v"
BENCHMARKS+="verilog/benchmarks_small/dspfilters/slowfil_srl_fixedtaps.v"
BENCHMARKS+="verilog/benchmarks_large/wb2axip/axilxbar.v"
BENCHMARKS+="verilog/benchmarks_large/riscv-bitmanip/shifter64.v"
BENCHMARKS+="verilog/benchmarks_large/riscv-bitmanip/smartbextdep.v"
BENCHMARKS+="verilog/benchmarks_large/ethernet/udp_complete_64_top.v"
BENCHMARKS+="verilog/benchmarks_large/picosoc/picosoc_top.v"
BENCHMARKS+="verilog/benchmarks_large/marlann/marlann_compute.v"
BENCHMARKS+="verilog/benchmarks_large/vexriscv/vexriscv_demo_GenFull.v"
BENCHMARKS+="verilog/benchmarks_large/cam/cam_srl_top.v"
BENCHMARKS+="verilog/benchmarks_large/cam/cam_bram_top.v"
BENCHMARKS+="../../verilog/benchmarks_large/litex/soc_basesoc_minispartan6_lm32.v.gz"
BENCHMARKS+="../../verilog/benchmarks_large/litex/soc_basesoc_minispartan6_vexriscv.v.gz"
BENCHMARKS+="../../verilog/benchmarks_large/litex/soc_basesoc_minispartan6_rocket.v.gz"
