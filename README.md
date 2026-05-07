# dgemm_riscv

## test environment
    simulator : gem5 TimingSimpleCPU
    ISA       : RV64GCV  (VLEN=512 bits, ELEN=64 bits)
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

    With VLEN=512 and -force-vector-width=4, clang auto-vectorizes the inner
    j-loop using vl=8, sew=64 (8 × FP64 = 64 bytes per vector op). This halves
    instruction count vs the VLEN=256/vl=4 build (32 bytes per vec op).

## simulation results  (kernel-only CSR deltas)
    note: mcycle/minstret are READ_CSR deltas taken before and after
          scalar_dgemm(). hpmcounterN values from whisper only (see run_log.txt).

    --- whisper (functional, VLEN=512) ---
    mcycle        =   8,795
    minstret      =   8,796
    Vector        =   1,072   (vector compute instructions, event 61)
    VectorLoad    =   1,056   (vector load instructions,   event 64)
    VectorStore   =     544   (vector store instructions,  event 65)

    --- gem5 TimingSimpleCPU (cycle-accurate, VLEN=512, 64KB L1 I/D cache) ---
    mcycle        =  26,980
    minstret      =   8,796
    IPC           =   0.326   (8,796 / 26,980)
    CPI           =   3.07    (26,980 / 8,796)

## roofline analysis  (dgemm 16×16 FP64 kernel)

    --- FLOPs ---
    FLOPs = 2 × M × N × K = 2 × 16 × 16 × 16 = 8,192 FLOP

    --- memory traffic (derived from whisper VectorLoad/VectorStore) ---
    vector element width : 8 × FP64 = 64 bytes per vector instruction (vl=8, VLEN=512)
    bytes loaded  = 1,056 vec loads  × 64 B = 67,584 B
    bytes stored  =   544 vec stores × 64 B = 34,816 B
    total Q       = 102,400 B

    note: Q is identical to the VLEN=256 run — same data is accessed, just in
    half as many (but twice as wide) vector instructions.

    VectorLoad breakdown:
      scale step (beta=0)  :  16 rows × 2 j-blocks =   32 vle64
      accum load C         : 256 (i,k) × 2 j-blocks =  512 vle64
      accum load B         : 256 (i,k) × 2 j-blocks =  512 vle64
      total                :                           1,056  ✓

    VectorStore breakdown:
      scale step (beta=0)  :  16 rows × 2 j-blocks =   32 vse64
      accum store C        : 256 (i,k) × 2 j-blocks =  512 vse64
      total                :                             544  ✓

    --- arithmetic intensity ---
    AI = 8,192 FLOP / 102,400 B = 0.080 FLOP/B
    (AI is VLEN-invariant: same algorithm, same data footprint)

    --- hardware ceilings ---
    peak compute (vl=8, FP64, FMA) = 8 elem × 2 FLOP × 1 GHz = 16.0 GFLOP/s
    peak memory BW (DDR3-1600 8x8) = 1600 MT/s × 8 B         = 12.8 GB/s

    --- roofline ---
    ridge point  = 16.0 GFLOP/s / 12.8 GB/s = 1.25 FLOP/B
    kernel AI (0.080) < ridge (1.25)  →  MEMORY BOUND

    attainable perf = AI × peak_BW = 0.080 × 12.8 GB/s = 1.024 GFLOP/s

    --- observed performance (gem5, VLEN=512, 64KB L1 cache) ---
    T_kernel         = 26,980 cycles / 1 GHz          =  27.0 μs
    achieved FLOP/s  = 8,192 FLOP  / 27.0 μs          = 303.6 MFLOP/s
    achieved BW      = 102,400 B   / 27.0 μs           = 3,795 MB/s = 3.80 GB/s

    --- efficiency ---
    vs attainable BW ceiling : 303.6 MFLOP/s / 1,024 MFLOP/s = 29.6 %
    BW utilization            :   3.80 GB/s  /  12.8 GB/s     = 29.7 %

    --- vs VLEN=256 baseline (same cache config) ---
    mcycle        : 35,611 → 26,980   (1.32× speedup)
    FLOP/s        : 230.0  → 303.6 MFLOP/s
    efficiency    : 22.5%  → 29.6%
    avg cyc/load  : 16.9   → 25.6 cycles  (wider loads, half as many)

    --- bottleneck: L1 cache stall latency (in-order, stall-on-access CPU) ---
    All three 16×16 FP64 matrices (~6 KB) fit in the 64 KB L1 D-cache.
    TimingSimpleCPU stalls the pipeline on every load until the L1 responds.

      avg cycles/load = 26,980 / 1,056 ≈ 25.6 cycles  (64-byte wide load)
      L1 cache hit latency (config): tag_latency=2 + data_latency=2 = 4 cycles

    Per-load cycle count is higher than VLEN=256 (25.6 vs 16.9) because 64-byte
    loads span a full cache line and incur more internal pipeline steps. However,
    total cycles are lower (26,980 vs 35,611) because there are half as many
    load instructions. The remaining gap from attainable (29.6% efficiency)
    reflects sequential issue overhead — an OOO core would overlap load latency.

## notes
    1. gem5 hpmcounterN are NOT valid event counts: TimingSimpleCPU does not
       implement HPM performance events; the counters accumulate raw cycles
       from simulation start. Use whisper hpmcounterN for event counts.

    2. Whisper VLEN=512 (bytes_per_vec=64) and gem5 VLEN=512 (vlen=512) now
       match. With -force-vector-width=4 on a 16-element row, clang selects
       vl=8 at VLEN=512 (since 16/2 = 8 elements fit one vector register),
       issuing 64-byte vector ops instead of 32-byte at VLEN=256.

    3. The 64 KB L1 caches deliver a 25× cycle reduction vs the no-cache
       baseline (891,693 → 35,611 cycles at VLEN=256). Widening to VLEN=512
       adds a further 1.32× on top, reaching 26,980 cycles. Further gains
       would require OOO execution or software pipelining to hide L1-hit stalls.

    misa = 0x800000000034112D  →  RV64 I M A F D C V
