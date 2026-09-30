// irq.S - тесты прерываний: CLINT (MSI, MTI), локальное прерывание LI0 (таймер тестбенча),
// векторный и прямой режим mtvec, маскирование, приоритеты, точность ловушек в конвейере.
//
// Обработчики используют только x20..x27:
//   x20 - mcause, x21 - mepc, x22 - режим обработчика MTI (0 - однократно, иначе - период
//   стресс-теста), x23 - счётчик прерываний, x24..x26 - временные, x27 - указатель журнала
//   (номер вектора каждого обработанного прерывания пишется в tlog)
#include "riscv_test.h"
#include "priv_test.h"

//Ожидание: до max итераций, пока x23 (счётчик прерываний) не станет >= cnt
#define WAIT_IRQ(cnt, max) li x3, max; li x4, cnt; 1: bgeu x23, x4, 2f; addi x3, x3, -1; bnez x3, 1b; 2:

RVTEST_CODE_BEGIN
    //Векторный режим
    LA_ABS(x1, vtable); ori x1, x1, 1; csrw mtvec, x1
    li x22, 0; li x23, 0; LA_ABS(x27, tlog)

    //#1 MSI: запрос программой через CLINT msip
    TEST_CASE( 1, x23, 0, ("msi[masked:MIE=0]"),       li x1, MIP_MSIP; csrs mie, x1; li x2, CLINT_MSIP; li x1, 1; sw x1, 0(x2); nop; nop; nop; nop)
    TEST_CASE( 2, x14, MIP_MSIP, ("msi[pending-in-mip]"), csrr x14, mip)
    TEST_CASE( 3, x23, 1, ("msi[taken:MIE=1]"),        csrsi mstatus, 8; nop; nop; nop; nop)
    TEST_CASE( 4, x20, 0x80000003, ("msi[mcause]"),    nop)
    TEST_CASE( 5, x26, 3, ("msi[vector-BASE+0x0C]"),   nop)
    TEST_CASE( 6, x14, 0, ("msi[cleared-by-isr]"),     csrr x14, mip)
    TEST_CASE( 7, x14, 0x1888, ("msi[mret:MIE=1]"),    csrr x14, mstatus)
    //Разрешено в mstatus, но запрещено в mie
    TEST_CASE( 8, x23, 1, ("msi[masked:mie.MSIE=0]"),  li x1, MIP_MSIP; csrc mie, x1; li x2, CLINT_MSIP; li x1, 1; sw x1, 0(x2); nop; nop; nop; nop)
    TEST_CASE( 9, x23, 2, ("msi[taken:mie.MSIE=1]"),   li x1, MIP_MSIP; csrs mie, x1; nop; nop; nop; nop)
    //mepc указывает на одну из инструкций сразу после разрешения
    TEST_CASE(10, x23, 3, ("msi[taken-after-csrsi]"),         csrci mstatus, 8; li x2, CLINT_MSIP; li x1, 1; sw x1, 0(x2); nop; nop; nop; csrsi mstatus, 8; 7: nop; nop; nop; nop)
    TEST_CASE(11, x20, 0x80000003, ("msi[mcause-2]"), nop)
    LA_ABS(x1, 7b); sub x21, x21, x1
    TEST_LEU(12, x21, 4, ("msi[mepc-after-csrsi]"))
    csrci mstatus, 8; li x1, MIP_MSIP; csrc mie, x1

    //#2 MTI: mtime >= mtimecmp
    li x23, 0
    TEST_CASE(13, x23, 1, ("mti[taken]"),              li x1, MIP_MTIP; csrs mie, x1; csrsi mstatus, 8; \
                                                       li x2, CLINT_MTIME; lw x1, 0(x2); addi x1, x1, 40; \
                                                       li x2, CLINT_MTIMECMP; sw x1, 0(x2); sw x0, 4(x2); WAIT_IRQ(1, 200))
    TEST_CASE(14, x20, 0x80000007, ("mti[mcause]"),    nop)
    TEST_CASE(15, x26, 7, ("mti[vector-BASE+0x1C]"),   nop)
    TEST_CASE(16, x14, 0, ("mti[cleared-by-isr]"),     csrr x14, mip)
    //Прерывание не приходит раньше срока: в обработчике 0 <= mtime - mtimecmp <= 1000
    TEST_LEU(17, x25, 1000, ("mti[not-early]"))
    csrci mstatus, 8; li x1, MIP_MTIP; csrc mie, x1

    //#3 LI0: событие обновления таймера тестбенча
    li x23, 0
    TEST_CASE(18, x23, 1, ("li0-tbtim[taken]"),         li x1, MIP_LI0; csrs mie, x1; csrsi mstatus, 8; \
                                                       li x2, TBTIM_BASE; sw x0, TBTIM_PR(x2); li x1, 5; sw x1, TBTIM_PER(x2); \
                                                       li x1, TBTIM_CR_EN | TBTIM_CR_UIE; sw x1, TBTIM_CR(x2); WAIT_IRQ(1, 100))
    TEST_CASE(19, x20, 0x80000010, ("li0-tbtim[mcause=16]"), nop)
    TEST_CASE(20, x26, 16, ("li0-tbtim[vector-BASE+0x40]"), nop)
    TEST_CASE(21, x14, 0, ("li0-tbtim[UIF-cleared]"),   li x2, TBTIM_BASE; lw x14, TBTIM_SR(x2))
    csrci mstatus, 8; li x1, MIP_LI0; csrc mie, x1

    //#4 Приоритет: MSI, MTI и LI0 ожидают одновременно -> порядок обработки MSI, MTI, LI0
    li x23, 0; LA_ABS(x27, tlog)
    li x1, MIP_MSIP | MIP_MTIP | MIP_LI0; csrs mie, x1
    li x2, CLINT_MSIP; li x1, 1; sw x1, 0(x2)
    li x2, CLINT_MTIMECMP; sw x0, 0(x2); sw x0, 4(x2)
    //Период больше остатка счётчика после предыдущего теста: в режиме счёта вверх событие - при CNT == PER
    li x2, TBTIM_BASE; sw x0, TBTIM_PR(x2); li x1, 15; sw x1, TBTIM_PER(x2); li x1, TBTIM_CR_EN | TBTIM_CR_UIE; sw x1, TBTIM_CR(x2)
    li x3, 100; li x4, MIP_MSIP | MIP_MTIP | MIP_LI0
1:  csrr x1, mip; beq x1, x4, 2f; addi x3, x3, -1; bnez x3, 1b
2:
    TEST_CASE(22, x14, MIP_MSIP | MIP_MTIP | MIP_LI0, ("priority[all-pending]"), csrr x14, mip)
    TEST_CASE(23, x23, 3, ("priority[3-taken]"),       csrsi mstatus, 8; WAIT_IRQ(3, 100))
    csrci mstatus, 8
    TEST_CASE(24, x14, 3,  ("priority[1st=MSI]"),      LA_ABS(x1, tlog); lw x14, 0(x1))
    TEST_CASE(25, x14, 7,  ("priority[2nd=MTI]"),      LA_ABS(x1, tlog); lw x14, 4(x1))
    TEST_CASE(26, x14, 16, ("priority[3rd=LI0]"),      LA_ABS(x1, tlog); lw x14, 8(x1))
    csrw mie, x0

    //#5 Исключения в векторном режиме идут на BASE
    TEST_CASE(27, x26, 0xE, ("vectored[exception->BASE]"), li x26, 0; ecall)
    TEST_CASE(28, x20, 11,  ("vectored[exception-mcause]"), nop)

    //#6 Прямой режим: все ловушки на BASE, причина - в mcause
    LA_ABS(x1, direct_handler); csrw mtvec, x1
    li x23, 0
    TEST_CASE(29, x26, 0xD, ("direct[msi->BASE]"),     li x26, 0; li x1, MIP_MSIP; csrs mie, x1; csrsi mstatus, 8; \
                                                       li x2, CLINT_MSIP; li x1, 1; sw x1, 0(x2); WAIT_IRQ(1, 50))
    TEST_CASE(30, x20, 0x80000003, ("direct[mcause]"), nop)
    csrci mstatus, 8; csrw mie, x0
    LA_ABS(x1, vtable); ori x1, x1, 1; csrw mtvec, x1

    //#7 Точность ловушек: вычисление с загрузками, записями, load-use, переходами, вызовами, mul и div
    //без прерываний и под потоком прерываний MTI и LI0 должно дать одинаковый результат
    jal x17, init_buf
    LA_ABS(x1, tbuf); li x2, 300; jal x17, work
    mv x8, x14                                        //Эталон без прерываний
    jal x17, init_buf
    li x23, 0; li x22, 71                             //Период MTI: 71..86 тактов (запас над временем обработчика)
    li x1, MIP_MTIP | MIP_LI0; csrs mie, x1
    li x2, TBTIM_BASE; sw x0, TBTIM_PR(x2); li x1, 60; sw x1, TBTIM_PER(x2); li x1, TBTIM_CR_EN | TBTIM_CR_UIE; sw x1, TBTIM_CR(x2) //LI0: каждые 61 такт
    li x2, CLINT_MTIME; lw x1, 0(x2); addi x1, x1, 30; li x2, CLINT_MTIMECMP; sw x1, 0(x2); sw x0, 4(x2)
    csrsi mstatus, 8
    LA_ABS(x1, tbuf); li x2, 300; jal x17, work
    csrci mstatus, 8
    li x2, TBTIM_BASE; sw x0, TBTIM_CR(x2); li x1, 1; sw x1, TBTIM_SR(x2)
    li x2, CLINT_MTIMECMP; li x1, -1; sw x1, 4(x2)
    csrw mie, x0
    TEST_EQ_REG(31, x14, x8, ("precise[result-with-irq]"))
    TEST_GEU(32, x23, 50, ("precise[irq-count>=50]"))

    j pass

//Заполнение tbuf[16] псевдослучайными значениями
init_buf:
    LA_ABS(x1, tbuf); li x7, 0x13572468; li x3, 0
1:  slli x15, x3, 2; add x15, x15, x1; sw x7, 0(x15)
    slli x4, x7, 3; xor x7, x4, x3; xori x7, x7, 0x5a5
    addi x3, x3, 1; li x4, 16; blt x3, x4, 1b
    jalr x0, 0(x17)

//Вычисление: x1 - буфер, x2 - число итераций, результат - x14
work:
    li x14, 0; li x3, 0
1:  andi x4, x3, 15; slli x4, x4, 2; add x4, x4, x1
    lw x7, 0(x4)
    add x14, x14, x7                                  //load-use
    ori x9, x3, 1                                     //Расширение M: прерывание посреди деления гасит его,
    divu x10, x7, x9                                  //после mret деление выполняется заново
    add x14, x14, x10
    rem x10, x14, x9
    mul x10, x10, x7
    xor x14, x14, x10
    xor x7, x7, x3
    sw x7, 0(x4)
    andi x15, x3, 3
    bnez x15, 2f
    jal x16, rotate
2:  addi x3, x3, 1
    blt x3, x2, 1b
    jalr x0, 0(x17)
rotate:
    slli x7, x14, 1; srli x15, x14, 31; or x14, x7, x15
    jalr x0, 0(x16)

//------------------------------------------------------------------------------------------
// Таблица векторов (mtvec.MODE = 1): вход N - прерывание с кодом N, вход 0 - исключения
//------------------------------------------------------------------------------------------
    .balign 128
vtable:
    j exc_isr       //0  исключения
    j bad_isr       //1
    j bad_isr       //2
    j msi_isr       //3  MSI
    j bad_isr       //4
    j bad_isr       //5
    j bad_isr       //6
    j mti_isr       //7  MTI
    j bad_isr       //8
    j bad_isr       //9
    j bad_isr       //10
    j bad_isr       //11 MEI (не подключено)
    j bad_isr       //12
    j bad_isr       //13
    j bad_isr       //14
    j bad_isr       //15
    j li0_isr       //16 LI0 - таймер тестбенча
    .rept 15
    j bad_isr       //17..31
    .endr

msi_isr:
    csrr x20, mcause; csrr x21, mepc; li x26, 3; addi x23, x23, 1
    sw x26, 0(x27); addi x27, x27, 4
    li x24, CLINT_MSIP; sw x0, 0(x24)
    mret

mti_isr:
    csrr x20, mcause; csrr x21, mepc; addi x23, x23, 1
    li x24, CLINT_MTIME; lw x25, 0(x24)               //mtime в момент обработки
    li x24, CLINT_MTIMECMP
    bnez x22, 1f
    li x26, 7; sw x26, 0(x27); addi x27, x27, 4
    lw x26, 0(x24); sub x25, x25, x26                 //mtime - mtimecmp >= 0
    li x26, -1; sw x26, 4(x24)                        //mtimecmp = максимум - запрос снят
    li x26, 7
    mret
1:  andi x26, x23, 15; add x25, x25, x26; add x25, x25, x22
    sw x25, 0(x24)                                    //Следующее прерывание через x22..x22+15 тактов
    mret

li0_isr:
    csrr x20, mcause; csrr x21, mepc; addi x23, x23, 1
    li x24, TBTIM_BASE
    bnez x22, 1f
    sw x0, TBTIM_CR(x24)                               //Однократно: таймер выключается ДО сброса UIF,
1:  li x25, 1; sw x25, TBTIM_SR(x24)                   //иначе событие между записями снова выставит UIF
    bnez x22, 2f
    li x26, 16; sw x26, 0(x27); addi x27, x27, 4
2:  mret

exc_isr:
    csrr x20, mcause; li x26, 0xE
    csrr x25, mepc; addi x25, x25, 4; csrw mepc, x25
    mret

direct_handler:
    csrr x20, mcause; addi x23, x23, 1
    bgez x20, 1f                                      //Исключение - ошибка теста
    li x26, 0xD
    li x24, CLINT_MSIP; sw x0, 0(x24)
    mret
1:  mv ACTUAL, x20; li EXPECTED, -1; j fail

bad_isr:
    csrr ACTUAL, mcause; li EXPECTED, -1; j fail
RVTEST_CODE_END

RVTEST_DATA_BEGIN
tlog: .zero 64
tbuf: .zero 64
