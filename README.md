# dgemm_riscv

## test environment
    simulator : gem5 TimingSimpleCPU
    ISA       : RV64GCV  (VLEN=256 bits, ELEN=64 bits)
    clock     : 1 GHz
    memory    : DDR3-1600 (1 channel, 8×8)
    OS        : bare-metal M-mode (semihosting I/O)
    toolchain : xpack-riscv-none-elf-gcc-13.2.0 / clang-18
    flags     : --target=riscv64-unknown-elf -march=rv64gcv -O3
                -mllvm -force-vector-width=256

## kernel
    operation : C = alpha*A*B + beta*C  (scalar DGEMM, i-k-j loop order)
    M=N=K     : 16
    dtype     : double (float64)
    alpha=1.0, beta=0.0

## simulation results  (gem5 stats.txt + CSR reads)
    note: mcycle/inst_count are kernel-only CSR deltas (READ before/after
          scalar_dgemm). gem5 stats counters cover the full simulation.

    mcycle           =   3,241,310   (kernel-only CSR delta)
    inst_count       =      39,323   (kernel-only CSR delta)
    simSeconds       =    0.004027 s (4.027 ms total sim time)

    --- gem5 stats ---
    numCycles        =   4,027,273   (CPU clock cycles, full sim)
    committedInsts   =      49,230
    numFpInsts       =      17,666
    numVecInsts      =           0   (RVV FP counted under numFpInsts)
    IPC              =       0.012   (memory-stall dominated)
    CPI              =      81.8

    --- memory traffic (full simulation) ---
    DRAM reads  (data)   =   79,266 B
    DRAM writes (data)   =   48,139 B
    DRAM reads  (ifetch) =  228,200 B
    avg DRAM read  BW    =      18.8 MiB/s  (data only)
    avg DRAM write BW    =      11.4 MiB/s  (data only)
    peak DRAM BW         =  12,800 MB/s  (DDR3-1600 theoretical)

## roofline analysis  (dgemm 16×16 FP64 kernel)

    FLOPs             = 2 × M × N × K = 2 × 16 × 16 × 16 = 8,192 FLOP
    working set       = A(2,048 B) + B(2,048 B) + C(2,048 B) = 6,144 B
    arith. intensity  = 8,192 / 6,144 = 1.333 FLOP/B

    --- hardware ceilings ---
    peak compute (scalar FP64, 1 FMA/cycle) =  2.0 GFLOP/s
    peak compute (vector FP64, VLEN=256)    =  8.0 GFLOP/s   [4 elem × 2 × 1 GHz]
    peak memory BW                          = 12.8 GB/s

    --- roofline ---
    ridge point  = 8.0 GFLOP/s / 12.8 GB/s = 0.625 FLOP/B
    kernel AI (1.333) > ridge (0.625)  →  COMPUTE BOUND

    attainable perf = min(8.0, 1.333 × 12.8) = min(8.0, 17.1) = 8.0 GFLOP/s

    --- observed BW utilization (full sim, not kernel-only) ---
    data BW used = (79,266 + 48,139) B / 0.004027 s = 31.6 MB/s
    BW util      = 31.6 / 12,800 = 0.25 %
    (low: single-thread serial access dominated by stdio/printf overhead)

## notes
    1. mcycle/inst_count are kernel-only CSR deltas: READ_CSR before and
       after scalar_dgemm call, then subtract. gem5 stats counters (numCycles,
       committedInsts) cover the full simulation including printf overhead.

    2. numVecInsts = 0 despite -force-vector-width=256 vectorization.
       gem5 TimingSimpleCPU classifies RVV FP instructions (vfmacc.vf
       etc.) under numFpInsts, not numVecInsts.

    3. IPC = 0.012 (CPI = 81.8) reflects TimingSimpleCPU stalling on
       every DRAM access (~80 cycles latency). A cached or OOO core
       would show much higher IPC.

    misa = 0x800000000034112D  →  RV64 I M A F D C V
