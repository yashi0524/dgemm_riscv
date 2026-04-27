# --- Compiler and Tools ---
CC      := clang-18
LD      := lld-18

# --- Paths ---
# Ensure TOOLCHAIN, LIBC_DIR, and GCC_LIB_DIR are set in your environment
# or define them explicitly here:
# TOOLCHAIN    := /path/to/toolchain
# LIBC_DIR     := /path/to/libc
# GCC_LIB_DIR  := /path/to/gcc_libs

SRC_DIR := src
INC_DIR := inc

# --- Target Architecture Flags ---
TARGET_FLAGS := --target=riscv64-unknown-elf \
                -march=rv64gcv \
                -mabi=lp64d

# --- System and Toolchain Paths ---
SYSROOT_FLAGS := --sysroot=$(TOOLCHAIN)/riscv-none-elf \
                 --gcc-toolchain=$(TOOLCHAIN) \
                 -B$(LIBC_DIR) \
                 -B$(GCC_LIB_DIR)

# --- Compiler tuning Flags ---
TUNING_FLAGS := -O3 -mllvm -force-vector-width=256
TUNING_FLAGS += -Rpass=loop-vectorize 
#-mllvm -prefer-predicate-over-epilogue=off

# --- Linker and Library Flags ---
LDFLAGS := -L$(LIBC_DIR) \
           -L$(GCC_LIB_DIR) \
           -fuse-ld=$(LD) \
           -static

# --- Combined CFLAGS ---
CFLAGS := $(TARGET_FLAGS) $(SYSROOT_FLAGS) $(TUNING_FLAGS) -I$(INC_DIR)

# --- Build Rules ---
TARGET := dgemm_riscv
SRC    := $(SRC_DIR)/dgemm.c

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

clean:
	rm -f $(TARGET)

.PHONY: all clean