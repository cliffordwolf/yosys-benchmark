include ../common.mk
unexport YOSYS

DEVICE=xc6s
GRADE=2
TARGET=$(DIR)
TARGETS = $(patsubst %,tab_%_$(DEVICE)_$(GRADE)/results.txt,$(basename $(notdir $(BENCHMARKS))))

all: $(TARGETS)
	cd $(DIR) && ../../../scripts/ise_min_period_table.sh > results_$(DEVICE)_$(DIR).csv

tab_%_$(DEVICE)_$(GRADE)/results.txt:
	f=(../../*/benchmarks_*/*/$*.{v.gz,v,vhdl}); \
	../../scripts/ise_min_period.sh $${f[0]} $(DEVICE) $(GRADE) --rdir $(DIR)

clean:
	 rm -r $(DIR)/tab_*
