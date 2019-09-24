#!/bin/bash

set -e
path=`readlink -f "$1"`
dev="$2"
grade="$3"
ip="$(basename -- ${path})"
ip=${ip%.gz}
ip=${ip%.*}

# rm -rf tab_${ip}_${dev}_${grade}
if [ $4 == "--rdir" ] || [ $4 == "-d" ]
then
  echo "Saving results in ${5}"
  dir=$5
  mkdir -p $dir
  cd $dir
  mkdir -p tab_${ip}_${dev}_${grade}
  cd tab_${ip}_${dev}_${grade}
  rm -f ${ip}.edif
else
  mkdir -p tab_${ip}_${dev}_${grade}
  cd tab_${ip}_${dev}_${grade}
fi

best_speed=10000
speed=50
step=16

synth_case() {
	if [ -f test_${1}.txt ]; then
		echo "Reusing cached tab_${ip}_${dev}_${grade}/test_${1}."
		return
	fi

	case "${dev}" in
		xc6s) xl_device="xc6slx100t-csg484-${grade}"
		#xc7a) xl_device="xc7a100t-csg324-${grade}" ;;
		#xc7a200) xl_device="xc7a200t-fbg676-${grade}" ;;
		#xc7k) xl_device="xc7k70t-fbg676-${grade}" ;;
		#xc7v) xl_device="xc7v585t-ffg1761-${grade}" ;;
		#xcku) xl_device="xcku035-fbva676-${grade}-e" ;;
		#xcvu) xl_device="xcvu065-ffvc1517-${grade}-e" ;;
		#xckup) xl_device="xcku3p-ffva676-${grade}-e" ;;
		#xcvup) xl_device="xcvu3p-ffvc1517-${grade}-e" ;;
	esac

	pwd=$PWD
	cat > test_${1}.ucf <<- EOT
		NET "$(<$(dirname ${path})/${ip}.clock)" TNM_NET = clk;
		TIMESPEC TS_clk = PERIOD "clk" ${speed:0: -1}.${speed: -1} ns;
		#PIN "BUFG.O" CLOCK_DEDICATED_ROUTE = FALSE;
	EOT
	if [ -f "$(dirname ${path})/${ip}.top" ]; then
		TOP=$(<$(dirname ${path})/${ip}.top)
	else
		TOP=${ip}
	fi

	if [ -z "$YOSYS" ]; then
		if [ -f "$(dirname ${path})/${ip}_ise.prj" ]; then
			cp "$(dirname ${path})/${ip}_ise.prj" test_${1}.prj
		else
			cat > test_${1}.prj <<- EOT
				verilog work $(basename ${path})
			EOT
		fi
		echo "run -ifn ${pwd}/test_${1}.prj -ifmt mixed -top ${TOP} -ofn ${pwd}/test_${1}.ngc -ofmt NGC -p ${xl_device} -uc ${pwd}/test_${1}.xcf -iobuf no -vlgincdir { \"$(dirname ${path})\" }" > test_${1}.xst
		cat > test_${1}.xcf <<- EOT
			NET "$(<$(dirname ${path})/${ip}.clock)" TNM_NET = clk;
			TIMESPEC TS_clk = PERIOD "clk" ${speed:0: -1}.${speed: -1} ns;
			BEGIN MODEL ${ip}
				NET "$(<$(dirname ${path})/${ip}.clock)" BUFFER_TYPE = BUFG;
			END;
		EOT

		echo "Running tab_${ip}_${dev}_${grade}/test_${1}.."
		pushd $(dirname ${path}) > /dev/null
		if ! xst -ifn ${pwd}/test_${1}.xst -ofn ${pwd}/test_${1}.srp -intstyle xflow > /dev/null 2>&1; then
			cat ${pwd}/test_${1}.srp
			exit 1
		fi
		popd > /dev/null

		if ! ngdbuild test_${1}.ngc test_${1}.ngd -uc test_${1}.ucf -intstyle xflow -p ${xl_device} > /dev/null 2>&1; then
			cat test_${1}.bld
			exit 1
		fi
	else
		if [ -f ${ip}.edif ]; then
			echo "Reusing cached tab_${ip}_${dev}_${grade}/${ip}.edif."
		else
			if [ -f "$(dirname ${path})/${ip}.ys" ]; then
				echo "script ${ip}.ys" > ${ip}.ys
			else
				if [ ${path:-5} == ".vhdl" ]
				then
					read_verilog $(basename ${path%.gz})
				    echo "read -vhdl $(basename ${path})" > ${ip}.ys
				else
				    echo "read_verilog $(basename ${path})" > ${ip}.ys
				fi
			fi

			cat >> ${ip}.ys <<- EOT
				${YOSYS_SYNTH}
				write_verilog -noexpr -norename ${pwd}/${ip}_syn.v
			EOT

			echo "Running tab_${ip}_${dev}_${grade}/${ip}.ys.."
			pushd $(dirname ${path}) > /dev/null
			if ! ${YOSYS} -l ${pwd}/yosys.log ${pwd}/${ip}.ys > /dev/null 2>&1; then
				cat ${pwd}/yosys.log
				exit 1
			fi
			popd > /dev/null
			mv yosys.log yosys.txt
		fi

		echo "Running tab_${ip}_${dev}_${grade}/test_${1}.."
		if ! edif2ngd ${ip}.edif > ${ip}.edif2ngd 2>&1; then
			cat ${ip}.edif2ngd
			exit 1
		fi
		if ! ngdbuild ${ip}.ngo test_${1}.ngd -uc test_${1}.ucf -intstyle xflow -p ${xl_device} > /dev/null 2>&1; then
			cat test_${1}.bld
			exit 1
		fi
	fi

	if ! map test_${1} -intstyle xflow -u > /dev/null 2>&1; then
		if grep -q '^ERROR:PhysDesignRules:2449 ' test_${1}.mrp; then
			return
		fi
		cat test_${1}.mrp
		exit 1
	fi
	if ! par test_${1} ${pwd}/test_${1}_par -intstyle xflow > /dev/null 2>&1; then
		cat test_${1}_par.par
		exit 1
	fi
	if ! trce test_${1}_par ${pwd}/test_${1}.pcf -v 1 -intstyle xflow > /dev/null 2>&1; then
		cat test_${1}_par.twr
		exit 1
	fi

	rm -f test_${1}.txt
	cat test_${1}.bld >> test_${1}.txt
	cat test_${1}.mrp >> test_${1}.txt
	cat test_${1}_par.par >> test_${1}.txt
	cat test_${1}_par.twr >> test_${1}.txt
}

got_violated=false
got_met=false

countdown=2
while [ $countdown -gt 0 ]; do
	synth_case $speed

	if grep -q '^ERROR:PhysDesignRules:2449 ' test_${speed}.mrp || grep -q '^Slack:\s\+-[0-9\.]\+ns (requirement' test_${speed}.txt; then
		echo "        tab_${ip}_${dev}_${grade}/test_${speed} VIOLATED"
		[ $got_met = true ] && step=$((step / 2))
		speed=$((speed + step))
		got_violated=true
	elif grep -q '^Slack:\s\+[0-9\.]\+ns (requirement' test_${speed}.txt; then
		echo "        tab_${ip}_${dev}_${grade}/test_${speed} MET"
		[ $speed -lt $best_speed ] && best_speed=$speed
		step=$((step / 2))
		speed=$((speed - step))
		got_met=true
	else
		echo "ERROR: No slack line found in $PWD/test_${speed}.txt!"
		exit 1
	fi

	if [ $step -eq 0 ]; then
		countdown=$((countdown - 1))
		speed=$((best_speed - 2))
		step=1
	fi
done

if ! $got_violated; then
	echo "ERROR: No timing violated in $PWD!"
	exit 1
fi

if ! $got_met; then
	echo "ERROR: No timing met in $PWD!"
	exit 1
fi


echo "-----------------------"
echo "Best speed for tab_${ip}_${dev}_${grade}: $best_speed"
echo "-----------------------"
echo $best_speed > results.txt

