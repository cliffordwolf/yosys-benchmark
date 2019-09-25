include ../common.mk
unexport YOSYS

DEVICE=xc6s
GRADE=2
TARGET=$(DIR)
TARGETS = $(patsubst %,tab_%_$(DEVICE)_$(GRADE)/results.txt,$(basename $(notdir $(BENCHMARKS))))

all: $(TARGETS)
	cd $(TARGET) && ../../../scripts/ise_min_period_table.sh > results_$(DEVICE)_$(DIR).csv

tab_%_$(DEVICE)_$(GRADE)/results.txt:
	../../scripts/ise_min_period.sh ../../*/benchmarks_*/*/$*.{v.gz,v,vhdl} $(DEVICE) $(GRADE) --rdir $(DIR)

clean:
	 rm -r tab_*
