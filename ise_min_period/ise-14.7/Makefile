include ../common.mk
unexport YOSYS

DEVICE=xc6s
GRADE=2
TARGETS = $(patsubst %,tab_%_$(DEVICE)_$(GRADE)/results.txt,$(basename $(notdir $(BENCHMARKS))))

all: $(TARGETS)
	../../scripts/ise_min_period_table.sh

tab_%_$(DEVICE)_$(GRADE)/results.txt:
	../../scripts/ise_min_period.sh ../../*/benchmarks_*/*/$*.{v,vhdl} $(DEVICE) $(GRADE) --rdir $(DIR)

clean:
	 rm -r tab_*
