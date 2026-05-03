/* start.S — bare-metal crt0 for dgemm_riscv on gem5 RISC-V M-mode
 *
 * Output strategy: NS16550A UART at 0x10000000
 *   _write polls TX-empty bit in LSR before sending each byte.
 *   Output appears in m5term (util/term/m5term localhost 3456).
 *
 * Exit strategy: m5_exit pseudo-instruction (0x4200007b).
 */

#define UART_BASE     0x10000000
#define UART_TX       0x00        /* transmit holding register  */
#define UART_LSR      0x05        /* line status register       */
#define UART_LSR_THRE 0x20        /* bit5: TX holding reg empty */

#define M5_EXIT       .word 0x4200007b   /* gem5 m5_exit pseudo-inst */

/* ================================================================== */
    .section .text.init, "ax", @progbits
    .globl  _start
    .type   _start, @function
_start:
    /* 1. Stack pointer — must be first instruction */
    la      sp, _stack_top

    /* 2. Global pointer for linker relaxation */
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop

    /* 3. Zero BSS */
    la      a0, _bss_start
    la      a1, _bss_end
    beq     a0, a1, .Lbss_done
.Lbss_loop:
    sd      zero, 0(a0)
    addi    a0, a0, 8
    bltu    a0, a1, .Lbss_loop
.Lbss_done:

    /* 4. Call main */
    li      a0, 0
    li      a1, 0
    li      a2, 0
    call    main
    /* fall through to _exit */
    .size   _start, . - _start


/* ================================================================== */
/* uart_putc(char c) — poll LSR THRE then write one byte to UART TX   */
/* a0 = character to send (byte)                                       */
/* No return value. Clobbers t0, t1.                                   */
/* ================================================================== */
    .globl  uart_putc
    .type   uart_putc, @function
uart_putc:
    li      t0, UART_BASE
.Lpoll_lsr:
    lb      t1, UART_LSR(t0)        /* read Line Status Register */
    andi    t1, t1, UART_LSR_THRE   /* check TX empty bit        */
    beqz    t1, .Lpoll_lsr          /* wait until TX ready       */
    sb      a0, UART_TX(t0)         /* write byte to TX register */
    ret
    .size   uart_putc, . - uart_putc


/* ================================================================== */
/* _write(fd, buf, count) — send buf to UART byte by byte             */
/* Newlib calls this for all printf/puts/putchar output.              */
/* ================================================================== */
    .globl  _write
    .type   _write, @function
_write:
    /* a0=fd, a1=buf, a2=count */
    beqz    a2, .Lwrite_ret
    mv      t2, a1              /* buf ptr  */
    mv      t3, a2              /* count    */
    li      t4, UART_BASE
.Lwrite_loop:
    beqz    t3, .Lwrite_done
    /* poll LSR THRE */
.Lwait_tx:
    lb      t5, UART_LSR(t4)
    andi    t5, t5, UART_LSR_THRE
    beqz    t5, .Lwait_tx
    lbu     t5, 0(t2)           /* load byte from buf */
    sb      t5, UART_TX(t4)     /* send to UART TX    */
    addi    t2, t2, 1
    addi    t3, t3, -1
    j       .Lwrite_loop
.Lwrite_done:
    mv      a0, a2              /* return original count */
    ret
.Lwrite_ret:
    li      a0, 0
    ret
    .size   _write, . - _write


/* ================================================================== */
/* _exit — terminate gem5 via m5_exit pseudo-instruction              */
/* ================================================================== */
    .globl  _exit
    .type   _exit, @function
_exit:
    M5_EXIT
.Lhalt:
    wfi
    j       .Lhalt
    .size   _exit, . - _exit


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
    li      a0, 1
    ret

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
