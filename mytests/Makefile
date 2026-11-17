# Worst-case sweep of the rubik solvers: make -C mytests sweep
# Needs the objects of a `make elfs` in the top directory.
ROOT := ..
B := $(ROOT)/build
CROSS_COMPILE ?= riscv-none-elf-
EMU := $(ROOT)/third_party/rv32emu/build/rv32emu
OPTS := O1 O2 O3 Os
CFLAGS := -march=rv32i_zicsr -mabi=ilp32 -O2 -ffreestanding -fno-pic \
          -iquote $(ROOT) -I$(ROOT)/common
RT := $(addprefix $(B)/common/, start.o perf.o rt.o print.o)

.PHONY: sweep tables
sweep: $(foreach o,$(OPTS),$(B)/mytests/sweep-$(o).elf)
	@for o in $(OPTS); do echo "-$$o"; $(EMU) $(B)/mytests/sweep-$$o.elf; done

$(B)/mytests/sweep.o: rubik_sweep.c dist11.inc
	@mkdir -p $(@D)
	$(CROSS_COMPILE)gcc $(CFLAGS) -c $< -o $@

$(B)/mytests/sweep-%.elf: $(B)/mytests/sweep.o $(B)/rubik/%/impl.o $(B)/rubik/impl_asm.o
	$(CROSS_COMPILE)ld -T $(ROOT)/common/linker.ld --no-warn-rwx-segments \
	    -o $@ $^ $(RT)

tables:
	cd $(ROOT) && python3 mytests/gen_rubik_tables.py
