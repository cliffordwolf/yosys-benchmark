SHELL=bash -O nullglob
export VIVADO=/opt/Xilinx/Vivado/2018.3/bin/vivado

BENCHMARKS+="../../verilog/benchmarks_large/boom/MediumBoom.v"
BENCHMARKS+="../../verilog/benchmarks_large/boom/MediumOctoBoom.v"
BENCHMARKS+="../../verilog/benchmarks_large/boom/MegaOctoBoom.v"
BENCHMARKS+="../../verilog/benchmarks_large/boom/SmallBoom.v"
BENCHMARKS+="../../verilog/benchmarks_large/boom/SmallQuadBoom.v"
BENCHMARKS+="../../verilog/benchmarks_large/opensparc/t2.v"
