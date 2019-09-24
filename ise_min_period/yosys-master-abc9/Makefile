include ../common.mk
export YOSYS=/opt/yosys-master/bin/yosys

DEVICE=xc6s
GRADE=2
TARGET=$(DIR)
TARGETS = $(patsubst %,tab_%_$(DEVICE)_$(GRADE)/results.txt,$(basename $(notdir $(BENCHMARKS))))

all: $(TARGETS)
	cd $(TARGET) && ../../../scripts/ise_min_period_table.sh > results_$(DEVICE)_$(DIR).csv

tab_%_$(DEVICE)_$(GRADE)/results.txt:
	f=(../../*/benchmarks_*/*/$*.{v.gz,v,vhdl}); \
	if ! zgrep -q "\(* top *\)" $${f[0]}; then \
		TOP="-top $*"; \
	fi; \
	YOSYS_SYNTH="synth_xilinx -family xc6s -abc9 -noiopad -edif $(PWD)/$(DIR)/$$(dirname $@)/$*.edif" bash ../../scripts/ise_min_period.sh $${f[0]} $(DEVICE) $(GRADE) --rdir $(DIR)

clean:
	rm -r tab_*
