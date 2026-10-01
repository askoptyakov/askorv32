/*
 *****************************************************************************************
 * @file        core_riscv.h
 * @author      Alexander Koptyakov
 * @device      AskoRV32
 * @brief       Ядро: регистры CSR машинного режима, прерывания и исключения.
 *
 *  Контроллер прерываний устроен как SiFive CLINT: фиксированные приоритеты, без вложенных
 *  прерываний. Векторный режим (mtvec.MODE = 1): прерывание с кодом N переходит на
 *  адрес __vector_table + 4*N, исключения - на __vector_table (см. start.S).
 *  Прерывания периферии собирает PLIC (plic.h) в прерывание MEI. В векторном режиме PLIC
 *  (включает PLIC_Init) источник S переходит сразу на __vector_table + 4*(32 + S).
 *
 *  Коды прерываний (mcause с битом 31 = 1) и приоритет (сверху - важнее):
 *    11 MEI  - внешнее прерывание: контроллер PLIC (источники периферии, plic.h)
 *     3 MSI  - программное прерывание (CLINT->MSIP)
 *     7 MTI  - машинный таймер (CLINT: mtime >= mtimecmp)
 *    16..31  - LI0..LI15, локальные линии: периферия, которой конфигуратор ПЛИС назначил линию
 *              вместо PLIC (по умолчанию все устройства - в PLIC, см. soc.h)
 *
 *  Коды исключений (mcause с битом 31 = 0): 0 - нечётный адрес перехода, 2 - недопустимая
 *  инструкция, 3 - ebreak (без подключённого отладчика), 4/6 - невыровненное чтение/запись,
 *  11 - ecall. В mepc - адрес инструкции, в mtval - адрес для кодов 0, 4, 6.
 *
 *  Сборка: -march=rv32i_zicsr (Eclipse: C/C++ Build -> Settings -> Target Processor ->
 *  Other extensions = _zicsr).
 *****************************************************************************************
 */

#ifndef __CORE_RISCV_H
#define __CORE_RISCV_H

#include <stdint.h>

/* Доступ к CSR */
#define CSR_READ(csr)          ({ uint32_t __v; __asm__ volatile ("csrr %0, " #csr : "=r"(__v)); __v; })
#define CSR_WRITE(csr, val)    __asm__ volatile ("csrw " #csr ", %0" :: "rK"((uint32_t)(val)))
#define CSR_SET(csr, mask)     __asm__ volatile ("csrs " #csr ", %0" :: "rK"((uint32_t)(mask)))
#define CSR_CLEAR(csr, mask)   __asm__ volatile ("csrc " #csr ", %0" :: "rK"((uint32_t)(mask)))

/* Биты mstatus */
#define MSTATUS_MIE            (1U << 3)    //Глобальное разрешение прерываний
#define MSTATUS_MPIE           (1U << 7)    //MIE до входа в ловушку

/* Биты mtvec */
#define MTVEC_MODE_DIRECT      0U
#define MTVEC_MODE_VECTORED    1U

/* Биты mcause */
#define MCAUSE_INTERRUPT       (1U << 31)
#define MCAUSE_CODE(mcause)    ((mcause) & 0x1FU)

/* Номера прерываний: бит в mie/mip и код в mcause */
typedef enum
{
  MSI_IRQn  = 3,        //Программное прерывание машинного режима (CLINT)
  MTI_IRQn  = 7,        //Машинный таймер (CLINT)
  MEI_IRQn  = 11,       //Внешнее прерывание (PLIC)
  LI0_IRQn  = 16,       //LI0..LI15 (16..31) - локальные линии; какое устройство на какой - soc.h
  LI1_IRQn, LI2_IRQn, LI3_IRQn, LI4_IRQn, LI5_IRQn, LI6_IRQn, LI7_IRQn, LI8_IRQn,
  LI9_IRQn, LI10_IRQn, LI11_IRQn, LI12_IRQn, LI13_IRQn, LI14_IRQn, LI15_IRQn
} IRQn_Type;

/* Коды исключений */
typedef enum
{
  EXC_INSTR_MISALIGNED = 0,
  EXC_ILLEGAL_INSTR    = 2,
  EXC_BREAKPOINT       = 3,
  EXC_LOAD_MISALIGNED  = 4,
  EXC_STORE_MISALIGNED = 6,
  EXC_ECALL_M          = 11
} EXC_Type;

/* Атрибут обработчика прерывания: компилятор сохраняет используемые регистры и выходит по mret */
#define __IRQ                  __attribute__((interrupt("machine")))

/* Глобальное разрешение и запрет прерываний (mstatus.MIE) */
static inline void __enable_irq(void)  { CSR_SET(mstatus, MSTATUS_MIE); }
static inline void __disable_irq(void) { CSR_CLEAR(mstatus, MSTATUS_MIE); }

/* Разрешение, запрет и проверка ожидания отдельного прерывания (mie/mip) */
static inline void IRQ_Enable(IRQn_Type IRQn)      { CSR_SET(mie, 1U << IRQn); }
static inline void IRQ_Disable(IRQn_Type IRQn)     { CSR_CLEAR(mie, 1U << IRQn); }
static inline uint32_t IRQ_IsPending(IRQn_Type IRQn) { return (CSR_READ(mip) >> IRQn) & 1U; }

/* Счётчик тактов ядра (mcycle, 64 бит) */
static inline uint64_t CORE_GetCycles(void)
{
  uint32_t hi, lo;
  do {
    hi = CSR_READ(mcycleh);
    lo = CSR_READ(mcycle);
  } while (hi != CSR_READ(mcycleh));
  return ((uint64_t)hi << 32) | lo;
}

/* Обработчики (определены в start.S как слабые ссылки на Default_Handler / Exception_Handler;
   чтобы подключить свой, достаточно объявить функцию с тем же именем и атрибутом __IRQ) */
void Exception_Handler(void);
void MSI_IRQHandler(void);
void MTI_IRQHandler(void);
void MEI_IRQHandler(void);
void LI0_IRQHandler(void);

#endif /* __CORE_RISCV_H */
