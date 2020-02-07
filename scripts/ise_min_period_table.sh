#!/bin/bash
for D in *; do    
	if [ -d "$D" ] && [ -f "$D/results.txt" ]; then
		min_period="$(<$D/results.txt)"
		period="${min_period:0: -1}.${min_period: -1}"
		fmax=`echo "scale=3; (1/$period)*1000" | bc | sed 's!\.0*$!!'`
		lut_logic=`sed -n "s/^\s\+\(Number used as logic:\)\s\+\([0-9,]\+\).*/\tLUT as Logic: \2/p" "$D/test_$min_period.txt" | sed 's/[^0-9]*//g' | tail -n 1`
		lut_slr=`sed -n "s/^\s\+Number used as \(Shift Register:\)\s\+\([0-9,]\+\).*/\tLUT as \1 \2/p" "$D/test_$min_period.txt" | sed 's/[^0-9]*//g' | tail -n 1`
		dram=`sed -n "s/^\s\+\(Number used as Memory:\)\s\+\([0-9,]\+\).*/\tLUT as Memory: \2/p" "$D/test_$min_period.txt"  | sed 's/[^0-9]*//g' | tail -n 1`
		flops=`sed -n "s/^\s\+Number used as \(Flip Flops\):\s\+\([0-9,]\+\).*/\tRegister as \1: \2/p" "$D/test_$min_period.txt" | sed 's/[^0-9]*//g' | tail -n 1`
		latch=`sed -n "s/^\s\+Number used as \(Latches\):\s\+\([0-9,]\+\).*/\tRegister as \1: \2/p" "$D/test_$min_period.txt" | sed 's/[^0-9]*//g' | tail -n 1`
		muxcy=`sed -n "s/^\s\+\(Number of MUXCYs used:\)\s\+\([0-9,]\+\).*/\tMUXCY: \2/p" "$D/test_$min_period.txt" | sed 's/[^0-9]*//g' | tail -n 1`
		f7=`sed -n "s/^#\s\+\(MUXF7\)\s\+:\s\+\([0-9]\+\).*/\2/p" "$D/test_$min_period.txt" | tail -n 1`
		f8=`sed -n "s/^#\s\+\(MUXF8\)\s\+:\s\+\([0-9]\+\).*/\2/p" "$D/test_$min_period.txt" | tail -n 1`
		#echo " F7 Muxes: ${f7:-0}"
		#echo " F8 Muxes: ${f8:-0}"
		#echo " Fx Muxes: $((${f7:-0}+${f8:-0}))"
		muxfx=$((${f7:-0}+${f8:-0}))
		dsp=`sed -n "s/^\s\+Number of \(DSP48A1\)s:\s\+\([0-9]\+\).*/\t\1: \2/p" "$D/test_$min_period.txt" | sed -e 's/.*:[0-9 ]//g' | tail -n 1`
		if [ -f "$D/yosys.txt" ]; then
			tool=`sed -n 's/.*\(Yosys\ [0-9].[0-9].*\).*/\1/p' $D/yosys.txt | tail -n 1`
			runtime=`printf "%1.f" $(sed -n 's/.*user\(.*\)system.*/\1/p' "$D/yosys.txt" |  sed -e 's/s\b//g' | tail -n 1)`
			peakmem=`printf "%1.f" $(sed -n 's/.*total,\(.*\)MB\ resident.*/\1/p' "$D/yosys.txt" |  sed -e 's/s\b//g' | tail -n 1)`
			if [ "$peakmem" -eq "0" ]; then # ABC child process included, format change
				peakmem=`printf "%1.f" $(grep "MEM:[[:blank:]].*$" "$D/yosys.txt" | awk '{print $13}')`
			fi
		else
			tool="ISE 14.7" #TODO: Select appropiate tool/version
			runtime=`printf "%1.f" $(sed -n 's/.*REAL time to NGDBUILD completion:\ \(.*\)sec.*/\1/p' "$D/test_$min_period.txt" |  sed -e 's/s\b//g')`
			peakmem=`printf "%1.f" $(sed -n 's/.*usage is\(.*\)k.*/\1/p' "$D/test_$min_period.txt" |  sed -e 's/s\b//g' | awk '{$1=$1/1024; print $1;}')`
		fi
		RAMB16=`sed -n "s/^\s\+\(Number of RAMB16BWERs:\)\s\+\([0-9,]\+\).*/\tRAMB16BWERs: \2/p" "$D/test_$min_period.txt" | sed -e 's/.*:[0-9 ]//g' | tail -n 1`
		RAMB8=`sed -n "s/^\s\+\(Number of RAMB8BWERs:\)\s\+\([0-9,]\+\).*/\tRAMB16BWERs: \2/p" "$D/test_$min_period.txt" | sed -e 's/.*:[0-9 ]//g' | tail -n 1`
		bram=$(($RAMB16+$RAMB8))
		echo "Design: $D"
		#echo ",Tool,LUT,FF,BRAM,LUTRAM,DSP,SRL,CARRY4,MuxFx,Logic Levels,Max Frequency,Peak Runtime in s,Peak Memory in MB"
		echo ",\"$tool\",$lut_logic,$flops,$bram,$dram,$dsp,$lut_slr,$muxcy,$muxfx,$fmax,$runtime,$peakmem"
	fi
done


