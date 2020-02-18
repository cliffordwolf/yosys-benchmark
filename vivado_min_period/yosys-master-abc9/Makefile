ifdef LARGE
        include ../large.mk
endif
ifdef SMALL
        include ../small.mk
endif

export YOSYS=yosys

SCRIPTS_DIR=$(shell realpath ../../scripts)
DEVICE=xc7a
GRADE=1
TARGETS = $(patsubst %,tab_%_$(DEVICE)_$(GRADE)/results.txt,$(basename $(notdir $(BENCHMARKS))))

all: $(TARGETS)
	cd $(DIR) && $(SCRIPTS_DIR)/vivado_min_period_table.sh > results_$(DEVICE)_$(DIRECTIVE).csv

tab_%_$(DEVICE)_$(GRADE)/results.txt:
	f=(../../*/benchmarks_*/*/$*.{v.gz,v,vhdl}); \
	if ! zgrep -q "\(* top *\)" $${f[0]}; then \
		TOP="-top $*"; \
	fi; \
	YOSYS_SYNTH="$(PREPEND); synth_xilinx $(YSARGS) -edif $(PWD)/$(DIR)/$$(dirname $@)/$*.edif" bash ../../scripts/vivado_min_period.sh --directive $(DIRECTIVE) $${f[0]} $(DEVICE) $(GRADE) --rdir $(DIR)

clean:
	rm -r $(DIR)/tab_*
