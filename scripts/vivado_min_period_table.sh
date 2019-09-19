#!/bin/bash
for D in *; do
    if [ -d "$D" ] && [ -f "$D/results.txt" ]; then
        min_period="$(<$D/results.txt)"
	period="${min_period:0: -1}.${min_period: -1}"
	fmax=`echo "scale=3; (1/$period)*1000" | bc | sed 's!\.0*$!!'`
        lut_logic=`sed -n "s/|\s\+\(LUT as Logic\)\s\+|\s\+\([0-9]\+\).*/\t\1: \2/p" "$D/test_$min_period.txt" | sed 's/[^0-9]*//g' | tail -n 1`
        lut_slr=`sed -n "s/|\s\+\(LUT as Shift Register\)\s\+|\s\+\([0-9]\+\).*/\t\1: \2/p" "$D/test_$min_period.txt" | sed 's/[^0-9]*//g'| tail -n 1`
	dram=`sed -n "s/|\s\+\(LUT as Distributed RAM\)\s\+|\s\+\([0-9]\+\).*/\t\1: \2/p" "$D/test_$min_period.txt" | sed 's/[^0-9]*//g' | tail -n 1`
        flops=`sed -n "s/|\s\+\(Register as Flip Flop\)\s\+|\s\+\([0-9]\+\).*/\t\1: \2/p" "$D/test_$min_period.txt" | sed 's/[^0-9]*//g'| tail -n 1`
        latch=`sed -n "s/|\s\+\(Register as Latch\)\s\+|\s\+\([0-9]\+\).*/\t\1: \2/p" "$D/test_$min_period.txt" | sed 's/[^0-9]*//g'| tail -n 1`
        if grep -q -e "|\s\+CARRY4\s\+" "$D/test_$min_period.txt"; then
            carry=`sed -n "s/|\s\+\(CARRY4\)\s\+|\s\+\([0-9]\+\).*/\t\1: \2/p" "$D/test_$min_period.txt" | sed -e 's/.*:[0-9 ]//g' | tail -n 1`
	    #sed -r 's/([^0-9]*([0-9]*)){2}.*/\2/' | tail -n 1`
        else
	    carry="0"
        fi
        f7=`sed -n "s/|\s\+\(F7 Muxes\)\s\+|\s\+\([0-9]\+\).*/\2/p" "$D/test_$min_period.txt" | tail -n 1`
        f8=`sed -n "s/|\s\+\(F8 Muxes\)\s\+|\s\+\([0-9]\+\).*/\2/p" "$D/test_$min_period.txt" | tail -n 1`
	muxfx=$(($f7+$f8))
	if grep -q -e "|\s\+RAM[A-Z][0-9]\{2\}[A-Z]" "$D/test_$min_period.txt"; then
		bram=`sed -n "s/|\s\+\(RAMB[0-9][0-9][A-Z][0-9]\)\s\+|\s\+\([0-9]\+\).*/\1: \2/p" "$D/test_$min_period.txt" | awk -F: '{ print $NF }' | paste -sd+ | bc`
	else
		bram=0
	fi
	dsp=`sed -n "s/|\s\+\(DSP48E1\)\s\+|\s\+\([0-9]\+\).*/\t\1: \2/p" "$D/test_$min_period.txt" | sed -e 's/.*:[0-9 ]//g' | tail -n 1`
	if [ -z "$dsp" ]; then
		dsp48=0
	else
		dsp48=$dsp
	fi
        llevels=`sed -n "s/|\s\+End Point Clock\s\+.*|\s\+\([0-9]\+\).*/\tLogic Levels: \1/p" "$D/test_$min_period.txt" | sed 's/[^0-9]*//g' | tail -n 1`
	if [ -f "$D/yosys.txt" ]; then 
		tool=`sed -n 's/.*\(Yosys\ [0-9].[0-9].*\).*/\1/p' $D/yosys.txt | tail -n 1` 
	else
		tool="Vivado 2018.3" #TODO: Select appropiate tool/version
	fi
	echo "Design: $D"
	#echo ",Tool,LUT,FF,BRAM,LUTRAM,DSP,SRL,CARRY4,MuxFx,Logic Levels,Max Frequency,Peak Runtime in s,Peak Memory in MB"
	echo ",\"$tool\",$lut_logic,$flops,$bram,$dram,$dsp48,$lut_slr,$carry,$muxfx,$llevels,$fmax"
    fi
done
