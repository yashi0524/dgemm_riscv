/* start.S — bare-metal crt0 for dgemm_riscv on gem5 RISC-V M-mode
 *
 * stdio strategy:
 *   _isatty(1) returns 1 -> newlib sets stdout LINE-BUFFERED
 *   -> printf flushes on every \n -> _write is called per line
 *   -> no fflush, no __sinit, no _global_impure_ptr needed
 *
 * _write routes output via semihosting SYS_WRITE0 (0x04).
 * _exit  terminates via semihosting SYS_EXIT  (0x18).
 *
 * The semihosting magic sequences use raw .word to prevent
 * assembler compression. They are made distinct by unique
 * padding so lld ICF cannot fold them.
 */

#define SYS_WRITE0            0x04
#define SYS_EXIT              0x18
#define ADP_STOPPED_APP_EXIT  0x20026

/* ================================================================== */
    .section .text.init, "ax", @progbits
    .globl  _start
    .type   _start, @function
_start:
    la      sp, _stack_top

    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop

    /* Zero BSS */
    la      a0, _bss_start
    la      a1, _bss_end
    beq     a0, a1, .Lbss_done
.Lbss_loop:
    sd      zero, 0(a0)
    addi    a0, a0, 8
    bltu    a0, a1, .Lbss_loop
.Lbss_done:

  /* Copy .data from flash (LMA) to RAM (VMA) */                                                                
    la      t0, _data_load                                                                                        
    la      t1, _data_start                                   
    la      t2, _data_end                                                                                         
    beq     t1, t2, .Ldata_done                               
  .Ldata_loop:
    ld      t3, 0(t0)                                                                                             
    sd      t3, 0(t1)
    addi    t0, t0, 8                                                                                             
    addi    t1, t1, 8                                         
    bltu    t1, t2, .Ldata_loop
  .Ldata_done:                   

    li      a0, 0
    li      a1, 0
    li      a2, 0
    call    main
    /* fall through to _exit */
    .size   _start, . - _start


/* ================================================================== */
/* _exit                                                               */
/* Sequence tag: 1 x nop after suffix (unique to _exit)               */
/* ================================================================== */
    .globl  _exit
    .type   _exit, @function
_exit:
    mv      s0, a0
    addi    sp, sp, -16
    li      t0, ADP_STOPPED_APP_EXIT
    sd      t0, 0(sp)
    sd      s0, 8(sp)
    li      a0, SYS_EXIT            /* 0x18 */
    mv      a1, sp
    .option push
    .option norvc
    .word   0x01f01013              /* slli x0, x0, 0x1f  PREFIX  */
    .word   0x00100073              /* ebreak              TRIGGER */
    .word   0x40705013              /* srai x0, x0, 7     SUFFIX  */
    .word   0x00000013              /* addi x0,x0,0  tag=1        */
    .option pop
    addi    sp, sp, 16
.Lhalt:
    wfi
    j       .Lhalt
    .size   _exit, . - _exit


/* ================================================================== */
/* _write                                                              */
/* Sequence tag: 2 x nop after suffix (unique to _write)              */
/* ================================================================== */
    .globl  _write
    .type   _write, @function
_write:
    beqz    a2, .Lwrite_ret

    addi    sp, sp, -48
    sd      ra, 40(sp)
    sd      s0, 32(sp)
    sd      s1, 24(sp)
    sd      s2, 16(sp)
    sd      s3,  8(sp)
    sd      s4,  0(sp)

    mv      s0, a1              /* buf */
    mv      s1, a2              /* count */

    /* Allocate null-terminated copy on stack */
    addi    t0, s1, 17
    andi    t0, t0, -16
    sub     sp, sp, t0
    mv      s2, t0
    mv      s3, sp

    mv      s4, s1
    mv      t1, s0
    mv      t2, s3
.Lwrite_copy:
    beqz    s4, .Lwrite_nul
    lbu     t3, 0(t1)
    sb      t3, 0(t2)
    addi    t1, t1, 1
    addi    t2, t2, 1
    addi    s4, s4, -1
    j       .Lwrite_copy
.Lwrite_nul:
    sb      zero, 0(t2)

    li      a0, SYS_WRITE0          /* 0x04 */
    mv      a1, s3
    .option push
    .option norvc
    .word   0x01f01013              /* slli x0, x0, 0x1f  PREFIX  */
    .word   0x00100073              /* ebreak              TRIGGER */
    .word   0x40705013              /* srai x0, x0, 7     SUFFIX  */
    .word   0x00000013              /* addi x0,x0,0  tag=1        */
    .word   0x00000013              /* addi x0,x0,0  tag=2        */
    .option pop

    add     sp, sp, s2
    ld      ra, 40(sp)
    ld      s0, 32(sp)
    ld      s1, 24(sp)
    ld      s2, 16(sp)
    ld      s3,  8(sp)
    ld      s4,  0(sp)
    addi    sp, sp, 48

    mv      a0, s1
    ret

.Lwrite_ret:
    li      a0, 0
    ret
    .size   _write, . - _write


/* ================================================================== */
/* Newlib syscall stubs                                                */
/* ================================================================== */
    .globl  _read
    .type   _read, @function
_read:
    li      a0, -1
    ret

    .globl  _sbrk
    .type   _sbrk, @function
_sbrk:
    la      t0, _heap_ptr
    ld      t1, 0(t0)
    beqz    t1, .Lsbrk_init
    j       .Lsbrk_bump
.Lsbrk_init:
    la      t1, _heap_start
.Lsbrk_bump:
    add     t2, t1, a0
    la      t3, _heap_end
    bgtu    t2, t3, .Lsbrk_fail
    sd      t2, 0(t0)
    mv      a0, t1
    ret
.Lsbrk_fail:
    li      a0, -1
    ret

    .globl  _close
    .type   _close, @function
_close:
    li      a0, -1
    ret

    .globl  _fstat
    .type   _fstat, @function
_fstat:
    li      a0, -1
    ret

    .globl  _isatty
    .type   _isatty, @function
_isatty:
    li      a0, 1               /* return 1 = is a tty                */
    ret                         /* -> newlib sets LINE buffering mode  */
                                /* -> printf flushes on every \n      */

    .globl  _lseek
    .type   _lseek, @function
_lseek:
    li      a0, -1
    ret

    .globl  _getpid
    .type   _getpid, @function
_getpid:
    li      a0, 1
    ret

    .globl  _kill
    .type   _kill, @function
_kill:
    li      a0, 0
    j       _exit


/* ================================================================== */
/* BSS                                                                 */
/* ================================================================== */
    .section .bss
    .align  3
    .globl  _heap_ptr
_heap_ptr:
    .dword  0
