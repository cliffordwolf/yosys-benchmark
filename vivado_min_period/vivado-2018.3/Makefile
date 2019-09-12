include ../common.mk
unexport YOSYS

DEVICE=xc7a
GRADE=1
TARGETS=$(patsubst %,tab_%_$(DEVICE)_$(GRADE)/results.txt,$(basename $(notdir $(BENCHMARKS))))
HDL_FILES=$(shell find ../../*/benchmarks* -name  "*.v*")

all: $(TARGETS)
	../../scripts/vivado_min_period_table.sh

tab_%_$(DEVICE)_$(GRADE)/results.txt:
	f=(../../*/benchmarks_*/*/$*.{v.gz,v,vhdl}); \
	../../scripts/vivado_min_period.sh --directive $(DIRECTIVE) $${f[0]} $(DEVICE) $(GRADE) --rdir $(DIR)
clean:
	rm -r tab_*
