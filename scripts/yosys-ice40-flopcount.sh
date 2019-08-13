#!/bin/bash

#
# mode script for ICE40 FPGA FF count
#

logfile=$( mktemp )
scriptpath=$( pwd )

# create synthesis script
myfile="$1"
if [ ${myfile: -5} == ".vhdl" ]
then
    topmodule=$( basename -s .vhdl "$1" )
    echo "read -vhdl $1" > script.yos
elif [ ${myfile##**.} == "sv" ]
then
    incdir=$( dirname "$1" )
    echo "read -incdir $incdir" > script.yos
    topmodule=$( basename -s .sv "$1" )
    echo "read -sv $1" >> script.yos
else
    topmodule=$( basename -s .v "$1")
    echo "read -vlog2k $1" > script.yos
fi
echo "synth_ice40 -top $topmodule" >> script.yos

# run tools
yosys -ql $logfile -p "script $scriptpath/script.yos" >/dev/null
sed -r '/^[0-9\.]+ Printing statistics./,/^[0-9\.]+ / { /SB_DFF/ { s/.* //; p; }; }; d;' $logfile
rm -f $logfile
rm -f script.yos
