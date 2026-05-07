#!/bin/bash

GEM5_ROOT_PATH=/home/ajno5/work/0_simulator/gem5/1_build/gem5

GEM5_BIN=$GEM5_ROOT_PATH/build/RISCV/gem5.opt

CONFIG_PATH=/home/ajno5/work/2_pattern/dgemm/config
CONFIG_FILE=$CONFIG_PATH/gem5_riscv_demo_riscv_baremetal_semihost.py

#PATTERN_ELF=/home/ajno5/work/2_pattern/hello_world/hello_riscv
#PATTERN_ELF=/home/ajno5/work/2_pattern/dgemm/dgemm_riscv
PATTERN_ELF=${1:?"Error: You must provide a filename as the first argument."}

$GEM5_BIN $CONFIG_FILE $PATTERN_ELF 2>&1 
# | grep -i "semi\|write\|WRITE"
# --debug-flags=Semihosting 

##gdb 
#$GEM5_BIN_PATH/gem5.opt --listener-mode=on  $CONFIG_PATH/riscv_demo_rvv.py $PATTERN_ELF

##debug
#gdb --args $GEM5_BIN_PATH/gem5.opt $CONFIG_PATH/riscv_demo_rvv.py $PATTERN_ELF
#$GEM5_BIN_PATH/gem5.opt --debug-flags=Exec,RiscvMisc $CONFIG_PATH/riscv_demo_rvv.py $PATTERN_ELF 2>&1 | tee debug_trace.txt 