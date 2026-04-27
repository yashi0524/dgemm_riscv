#define read_mcycle(count) asm volatile ("csrr %0, mcycle" : "=r" (count));

#define read_cycle(count) asm volatile ("csrr %0, cycle" : "=r" (count));

#define READ_CSR(reg) ({ unsigned long __v; \
    asm volatile ("csrr %0, " #reg : "=r" (__v)); __v; })

#define WRITE_CSR(val, reg) ({ \
    asm volatile ("csrw " #reg ", %0" :: "r" (val)); \
})    