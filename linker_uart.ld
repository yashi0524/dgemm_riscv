/* linker.ld — bare-metal linker script for dgemm_riscv on gem5 RISC-V
 *
 * Memory map:
 *   0x00010000  FLASH  — .text, .rodata, .init_array, .fini_array
 *   0x00030000  RAM    — .data, .bss, heap, stack
 *
 * UART:  0x10000000 (NS16550A, mapped by gem5 platform)
 * Stack: 1MB, grows down from _stack_top
 * Heap:  512KB, grows up from _heap_start
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    FLASH (rx)  : ORIGIN = 0x00010000, LENGTH = 0x00020000   /* 128 KB */
    RAM   (rwx) : ORIGIN = 0x00030000, LENGTH = 0x00200000   /*   2 MB */
}

_STACK_SIZE = 0x100000;   /* 1 MB */
_HEAP_SIZE  = 0x080000;   /* 512 KB */

SECTIONS
{
    /* ---------------------------------------------------------------- */
    /* .text.init first — _start must be the ELF entry point            */
    /* ---------------------------------------------------------------- */
    .text.init :
    {
        KEEP(*(.text.init))
    } > FLASH

    .text :
    {
        *(.text)
        *(.text.*)
        *(.gnu.linkonce.t.*)
    } > FLASH

    .rodata :
    {
        *(.rodata)
        *(.rodata.*)
        *(.gnu.linkonce.r.*)
    } > FLASH

    /* C++ init/fini arrays */
    .preinit_array :
    {
        PROVIDE_HIDDEN(__preinit_array_start = .);
        KEEP(*(.preinit_array))
        PROVIDE_HIDDEN(__preinit_array_end = .);
    } > FLASH

    .init_array :
    {
        PROVIDE_HIDDEN(__init_array_start = .);
        KEEP(*(SORT(.init_array.*)))
        KEEP(*(.init_array))
        PROVIDE_HIDDEN(__init_array_end = .);
    } > FLASH

    .fini_array :
    {
        PROVIDE_HIDDEN(__fini_array_start = .);
        KEEP(*(SORT(.fini_array.*)))
        KEEP(*(.fini_array))
        PROVIDE_HIDDEN(__fini_array_end = .);
    } > FLASH

    /* ---------------------------------------------------------------- */
    /* .data — initialized globals, loaded from FLASH, run from RAM     */
    /* ---------------------------------------------------------------- */
    .data :
    {
        . = ALIGN(8);
        _data_start = .;
        *(.data)
        *(.data.*)
        *(.gnu.linkonce.d.*)
        . = ALIGN(8);
        PROVIDE(__global_pointer$ = . + 0x800);
        _data_end = .;
    } > RAM AT > FLASH

    _data_load = LOADADDR(.data);

    /* ---------------------------------------------------------------- */
    /* .bss — zero-initialized; _start zeros this region at boot        */
    /* ---------------------------------------------------------------- */
    .bss :
    {
        . = ALIGN(8);
        _bss_start = .;
        *(.bss)
        *(.bss.*)
        *(.gnu.linkonce.b.*)
        *(COMMON)
        . = ALIGN(8);
        _bss_end = .;

        /* newlib reent pointer — not always exported as a linker symbol */
        PROVIDE(_global_impure_ptr = .);
        PROVIDE(_impure_ptr        = .);
    } > RAM

    /* ---------------------------------------------------------------- */
    /* Heap                                                              */
    /* ---------------------------------------------------------------- */
    .heap :
    {
        . = ALIGN(16);
        _heap_start = .;
        . += _HEAP_SIZE;
        _heap_end = .;
    } > RAM

    /* ---------------------------------------------------------------- */
    /* Stack — grows downward from _stack_top                           */
    /* ---------------------------------------------------------------- */
    .stack :
    {
        . = ALIGN(16);
        _stack_bottom = .;
        . += _STACK_SIZE;
        . = ALIGN(16);
        _stack_top = .;
    } > RAM

    /DISCARD/ :
    {
        *(.eh_frame)
        *(.eh_frame_hdr)
        *(.note.*)
        *(.comment)
    }
}
