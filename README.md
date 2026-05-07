# dgemm_riscv

## test environment
    simulator : gem5 TimingSimpleCPU
    ISA       : RV64GCV  (VLEN=256 bits, ELEN=64 bits)
    clock     : 1 GHz
    cache     : 64 KB L1 I-cache + 64 KB L1 D-cache (4-way, 2-cycle latency)
    memory    : DDR3-1600 8x8
    OS        : bare-metal M-mode (semihosting I/O)
    toolchain : xpack-riscv-none-elf-gcc-13.2.0 / clang-18
    flags     : --target=riscv64-unknown-elf -march=rv64gcv -O3
                -mllvm -force-vector-width=4

## kernel
    operation : C = alpha*A*B + beta*C  (scalar DGEMM, i-k-j loop order)
    M=N=K     : 16
    dtype     : double (float64)
    alpha=1.0, beta=0.0

    compiled with -force-vector-width=4 → clang auto-vectorizes inner j-loop
    into RVV instructions with vl=4, sew=64 (4 × FP64 = 32 bytes per vec op)

## simulation results  (kernel-only CSR deltas)
    note: mcycle/minstret are READ_CSR deltas taken before and after
          scalar_dgemm(). hpmcounterN values from whisper only (see run_log.txt).

    --- whisper (functional, VLEN=512) ---
    mcycle        =  12,267
    minstret      =  12,268
    Vector        =   1,616   (vector compute instructions, event 61)
    VectorLoad    =   2,112   (vector load instructions,   event 64)
    VectorStore   =   1,088   (vector store instructions,  event 65)

    --- gem5 TimingSimpleCPU (cycle-accurate, 64KB L1 I/D cache) ---
    mcycle        =  35,611
    minstret      =  12,268
    IPC           =   0.344   (12,268 / 35,611)
    CPI           =   2.90    (35,611 / 12,268)

## roofline analysis  (dgemm 16×16 FP64 kernel)

    --- FLOPs ---
    FLOPs = 2 × M × N × K = 2 × 16 × 16 × 16 = 8,192 FLOP

    --- memory traffic (derived from whisper VectorLoad/VectorStore) ---
    vector element width : 4 × FP64 = 32 bytes per vector instruction
    bytes loaded  = 2,112 vec loads  × 32 B = 67,584 B
    bytes stored  = 1,088 vec stores × 32 B = 34,816 B
    total Q       = 102,400 B

    VectorLoad breakdown:
      scale step (beta=0)  :  16 rows × 4 j-blocks =   64 vle64
      accum load C         : 256 (i,k) × 4 j-blocks = 1,024 vle64
      accum load B         : 256 (i,k) × 4 j-blocks = 1,024 vle64
      total                :                           2,112  ✓

    VectorStore breakdown:
      scale step (beta=0)  :  16 rows × 4 j-blocks =   64 vse64
      accum store C        : 256 (i,k) × 4 j-blocks = 1,024 vse64
      total                :                           1,088  ✓

    --- arithmetic intensity ---
    AI = 8,192 FLOP / 102,400 B = 0.080 FLOP/B

    --- hardware ceilings ---
    peak compute (vl=4, FP64, FMA) = 4 elem × 2 FLOP × 1 GHz =  8.0 GFLOP/s
    peak memory BW (DDR3-1600 8x8) = 1600 MT/s × 8 B         = 12.8 GB/s

    --- roofline ---
    ridge point  = 8.0 GFLOP/s / 12.8 GB/s = 0.625 FLOP/B
    kernel AI (0.080) < ridge (0.625)  →  MEMORY BOUND

    attainable perf = AI × peak_BW = 0.080 × 12.8 GB/s = 1.024 GFLOP/s

    --- observed performance (gem5, 64KB L1 cache) ---
    T_kernel         = 35,611 cycles / 1 GHz          =  35.6 μs
    achieved FLOP/s  = 8,192 FLOP  / 35.6 μs          = 230.0 MFLOP/s
    achieved BW      = 102,400 B   / 35.6 μs           =  2,876 MB/s = 2.88 GB/s

    --- efficiency ---
    vs attainable BW ceiling : 230.0 MFLOP/s / 1,024 MFLOP/s = 22.5 %
    BW utilization            :   2.88 GB/s  /  12.8 GB/s     = 22.5 %

    --- bottleneck: L1 cache latency (stall-on-miss CPU, no OOO) ---
    The L1 cache absorbs most DRAM traffic (all three 16×16 matrices = 6 KB
    fit entirely in the 64 KB L1 D-cache). However, TimingSimpleCPU still
    stalls the pipeline on every load until the L1 responds. Average stall:

      avg cycles/load = 35,611 cycles / 2,112 loads ≈ 16.9 cycles
      L1 cache hit latency (config): tag_latency=2 + data_latency=2 = 4 cycles

    16.9 cycles/load vs 4-cycle L1 latency: overhead from sequential issue,
    instruction dispatch, and vector unit integration. Compare to no-cache run:

      no-cache avg cycles/load = 891,693 / 2,112 ≈ 422 cycles  (DDR3 latency)
      with-L1   avg cycles/load =  35,611 / 2,112 ≈  17 cycles
      speedup   = 891,693 / 35,611 ≈ 25×

    The remaining gap from attainable (22.5% efficiency) is due to in-order
    stall-per-instruction execution — an OOO or superscalar core could issue
    the next vector load while the previous result is in flight.

## notes
    1. gem5 hpmcounterN are NOT valid event counts: TimingSimpleCPU does not
       implement HPM performance events; the counters accumulate raw cycles
       from simulation start. Use whisper hpmcounterN for event counts.

    2. Whisper VLEN=512 but force-vector-width=4 fixes vl=4; both simulators
       execute identical vector instructions (32 B per op).

    3. The 64 KB L1 I/D caches added in this run deliver a 25× cycle reduction
       vs the no-cache baseline (891,693 → 35,611 cycles). All three 16×16 FP64
       matrices (~6 KB) fit in L1, collapsing DRAM traffic to a cold-start fill.
       Further gains would require OOO execution or software pipelining to hide
       the remaining L1-hit stall cycles.

    misa = 0x800000000034112D  →  RV64 I M A F D C V
