include ../common.mk
export YOSYS=yosys

SCRIPTS_DIR=$(shell realpath ../../scripts)
DEVICE=xc6s
GRADE=2
TARGETS = $(patsubst %,tab_%_$(DEVICE)_$(GRADE)/results.txt,$(basename $(notdir $(BENCHMARKS))))

all: $(TARGETS)
	cd $(DIR) && $(SCRIPTS_DIR)/ise_min_period_table.sh > results_$(DEVICE)_$(DIRECTIVE).csv

tab_%_$(DEVICE)_$(GRADE)/results.txt:
	f=(../../*/benchmarks_*/*/$*.{v.gz,v,vhdl}); \
	if ! zgrep -q "\(* top *\)" $${f[0]}; then \
		TOP="-top $*"; \
	fi; \
	YOSYS_SYNTH="$(PREPEND); synth_xilinx $(YSARGS) -family xc6s -edif $(PWD)/$(DIR)/$$(dirname $@)/$*.edif" bash ../../scripts/ise_min_period.sh $${f[0]} $(DEVICE) $(GRADE) --rdir $(DIR)

clean:
	 rm -r $(DIR)/tab_*
