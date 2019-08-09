#!/bin/sh

ghdl -a cic5.vhdl
ghdl -a cic5_tb.vhdl
ghdl -e cic5_tb
ghdl -r cic5_tb --wave=cic5_tb.ghw
