include ../common.mk
export YOSYS=/opt/yosys-master/bin/yosys

DEVICE=xc7a
GRADE=1
TARGETS = $(patsubst %,tab_%_$(DEVICE)_$(GRADE)/results.txt,$(basename $(notdir $(BENCHMARKS))))

all: $(TARGETS)
	../../scripts/vivado_min_period_table.sh

tab_%_$(DEVICE)_$(GRADE)/results.txt:
	f=(../../*/benchmarks_*/*/$*.{v.gz,v,vhdl}); \
	if ! zgrep -q "\(* top *\)" $${f[0]}; then \
		TOP="-top $*"; \
	fi; \
	YOSYS_SYNTH="synth_xilinx -abc9 -edif $(PWD)/$$(dirname $@)/$*.edif" bash ../../scripts/vivado_min_period.sh $${f[0]} $(DEVICE) $(GRADE)

clean:
	rm -r tab_*
