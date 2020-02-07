include ../common.mk
unexport YOSYS

DEVICE=xc6s
GRADE=2
TARGETS = $(patsubst %,tab_%_$(DEVICE)_$(GRADE)/results.txt,$(basename $(notdir $(BENCHMARKS))))

all: $(TARGETS)
	cd $(DIR) && $(SCRIPTS_DIR)/ise_min_period_table.sh > results_$(DEVICE).csv

tab_%_$(DEVICE)_$(GRADE)/results.txt:
	f=(../../*/benchmarks_*/*/$*.{v.gz,v,vhdl}); \
	../../scripts/ise_min_period.sh $${f[0]} $(DEVICE) $(GRADE) --rdir $(DIR)

clean:
	 rm -r $(DIR)/tab_*
