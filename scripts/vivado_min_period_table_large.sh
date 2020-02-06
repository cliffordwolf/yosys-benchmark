#!/bin/bash
for D in *; do
    if [ -d "$D" ] && [ -f "$D/yosys.txt" ]; then
	FILE="$D/yosys.txt"
	tac $FILE | sed '/Number of cells/Q' | tac > $D/stats.txt
	STATS="$D/stats.txt"
	FLOPSUM=`grep "FD.*[[:blank:]][[:blank:]].*$" $STATS | awk '{print $2}' | awk '{ SUM += $1} END { print SUM }'`
	LUTSUM=`grep "LUT[0-9][[:blank:]][[:blank:]].*$" $STATS | awk '{print $2}' | awk '{ SUM += $1} END { print SUM }'`
	INVSUM=`grep "INV[[:blank:]][[:blank:]].*$" $STATS | awk '{print $2}' | awk '{ SUM += $1} END { print SUM }'`
	LUTRAMSUM=`grep "RAM[[:digit:]].*[[:blank:]][[:blank:]].*$" $STATS | awk '{print $2}' | awk '{ SUM += $1} END { print SUM }'`
	BRAMSUM=`grep "RAMB[[:digit:]].*[[:blank:]][[:blank:]].*$" $STATS | awk '{print $2}' | awk '{ SUM += $1} END { print SUM }'`
	DSPSUM=`grep "DSP[[:digit:]].*[[:blank:]][[:blank:]].*$" $STATS | awk '{print $2}' | awk '{ SUM += $1} END { print SUM }'`
	SRLSUM=`grep "SRL[[:digit:]].*[[:blank:]][[:blank:]].*$" $STATS | awk '{print $2}' | awk '{ SUM += $1} END { print SUM }'`
	CARRY4SUM=`grep "CARRY[[:digit:]].*[[:blank:]][[:blank:]].*$" $STATS | awk '{print $2}' | awk '{ SUM += $1} END { print SUM }'`
	MUXFXSUM=`grep "MUXF[[:digit:]].*[[:blank:]][[:blank:]].*$" $STATS | awk '{print $2}' | awk '{ SUM += $1} END { print SUM }'`
	tool=`sed -n 's/.*\(Yosys\ [0-9].[0-9].*\).*/\1/p' "$STATS" | tail -n 1`
	runtime=`printf "%1.f" $(sed -n 's/.*user\(.*\)system.*/\1/p' "$STATS" |  sed -e 's/s\b//g' | tail -n 1)`
	#peakmem=`printf "%1.f" $(sed -n 's/.*total,\(.*\)MB\ resident.*/\1/p' "$STATS" |  sed -e 's/s\b//g' | tail -n 1)`
        peakmem=`printf "%1.f" $(grep "MEM:[[:blank:]].*$" "$D/yosys.txt" | awk '{print $13}')`
	echo "Design: $D"
	echo ",\"$tool\",$(($LUTSUM+$INVSUM)),$FLOPSUM,$BRAMSUM,$LUTRAMSUM,$DSPSUM,$SRLSUM,$CARRY4SUM,$MUXFXSUM,$runtime,,,$peakmem"
	rm $STATS
    fi
done
