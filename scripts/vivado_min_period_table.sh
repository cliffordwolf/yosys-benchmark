#!/bin/bash
for D in *; do
    if [ -d "$D" ] && [ -f "$D/results.txt" ]; then
        min_period="$(<$D/results.txt)"
        echo "$D @ ${min_period:0: -1}.${min_period: -1} ns"
        sed -n "s/|\s\+\(LUT as Logic\)\s\+|\s\+\([0-9]\+\).*/\t\1: \2/p" "$D/test_$min_period.txt" | tail -n 1
        sed -n "s/|\s\+\(LUT as Shift Register\)\s\+|\s\+\([0-9]\+\).*/\t\1: \2/p" "$D/test_$min_period.txt" | tail -n 1
	sed -n "s/|\s\+\(LUT as Distributed RAM\)\s\+|\s\+\([0-9]\+\).*/\t\1: \2/p" "$D/test_$min_period.txt" | tail -n 1
        sed -n "s/|\s\+\(Register as Flip Flop\)\s\+|\s\+\([0-9]\+\).*/\t\1: \2/p" "$D/test_$min_period.txt" | tail -n 1
        sed -n "s/|\s\+\(Register as Latch\)\s\+|\s\+\([0-9]\+\).*/\t\1: \2/p" "$D/test_$min_period.txt" | tail -n 1
        if grep -q -e "|\s\+CARRY4\s\+" "$D/test_$min_period.txt"; then
            sed -n "s/|\s\+\(CARRY4\)\s\+|\s\+\([0-9]\+\).*/\t\1: \2/p" "$D/test_$min_period.txt" | tail -n 1
        else
            echo "	CARRY4: 0"
        fi
        f7=`sed -n "s/|\s\+\(F7 Muxes\)\s\+|\s\+\([0-9]\+\).*/\2/p" "$D/test_$min_period.txt" | tail -n 1`
        f8=`sed -n "s/|\s\+\(F8 Muxes\)\s\+|\s\+\([0-9]\+\).*/\2/p" "$D/test_$min_period.txt" | tail -n 1`
        echo "	F7 Muxes: $f7"
        echo "	F8 Muxes: $f8"
        echo "	Fx Muxes: $(($f7+$f8))"
	if grep -q -e "|\s\+RAM[A-Z][0-9]\{2\}[A-Z]" "$D/test_$min_period.txt"; then
		RAMB36E1=`sed -n "s/|\s\+\(RAMB36E1\)\s\+|\s\+\([0-9]\+\).*/\2/p" "$D/test_$min_period.txt" | tail -n 1`
		RAMB18E1=`sed -n "s/|\s\+\(RAMB36E1\)\s\+|\s\+\([0-9]\+\).*/\2/p" "$D/test_$min_period.txt" | tail -n 1`
		echo -e "	BRAM:  \n\t\tRAMB36E1: $RAMB36E1 \n\t\tRAMB18E1: $RAMB18E1"
	fi
	if grep -q -e "|\s\+RAM[A-Z][0-9]\s*[0-9][A-Z]" "$D/test_$min_period.txt"; then
		RAM32X1D=`sed -n "s/|\s\+\(RAMD32X1D\)\s\+|\s\+\([0-9]\+\).*/\2/p" "$D/test_$min_period.txt" | tail -n 1`
		RAMD32=`sed -n "s/|\s\+\(RAMD32\)\s\+|\s\+\([0-9]\+\).*/\2/p" "$D/test_$min_period.txt" | tail -n 1`
        	RAMS32=`sed -n "s/|\s\+\(RAMS32\)\s\+|\s\+\([0-9]\+\).*/\2/p" "$D/test_$min_period.txt" | tail -n 1`
		RAMD64E=`sed -n "s/|\s\+\(RAMD64E\)\s\+|\s\+\([0-9]\+\).*/\2/p" "$D/test_$min_period.txt" | tail -n 1`
        	echo -e "	LUTRAM:  \n\t\tRAMD32: $RAMD32 \n\t\tRAMS32: $RAMS32 \n\t\tRAMD64E: $RAMD64E" 
	fi
	sed -n "s/|\s\+\(DSP48E1\)\s\+|\s\+\([0-9]\+\).*/\t\1: \2/p" "$D/test_$min_period.txt" | tail -n 1
        sed -n "s/|\s\+End Point Clock\s\+.*|\s\+\([0-9]\+\).*/\tLogic Levels: \1/p" "$D/test_$min_period.txt" | tail -n 1
        sed -n "s/|\s\+\(Logical Path\)\s\+|\s\+\(.*\+\)\s\+|$/\t\1: \2/p" "$D/test_$min_period.txt" | tail -n 1
    fi
done
