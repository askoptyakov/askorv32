// plic.S - тесты контроллера прерываний PLIC (источники 2..8 выставляет тестбенч по записи
// в SIM_PLIC_SRC; источник 1 - таймер тестбенча)
#include "riscv_test.h"
#include "priv_test.h"

#define PLIC_BASE       0x0C000000
#define PLIC_PENDING    0x0C001000
#define PLIC_ENABLE     0x0C002000
#define PLIC_THRESHOLD  0x0C200000
#define PLIC_CLAIM      0x0C200004
#define PLIC_VECTOR     0x0C200008          //Векторный режим (расширение askoRV32)
#define SIM_PLIC_SRC    0x1F000014          //Устройство моделирования: бит N - уровень источника N
#define MIP_MEIP        (1 << 11)

//Установка приоритета источника n
#define PRIO(n, p)   li x2, PLIC_BASE + 4 * (n); li x3, p; sw x3, 0(x2)
#define SRC(mask)    li x2, SIM_PLIC_SRC; li x3, mask; sw x3, 0(x2)
#define CLAIM(reg)   li x2, PLIC_CLAIM; lw reg, 0(x2)
#define COMPLETE(n)  li x2, PLIC_CLAIM; li x3, n; sw x3, 0(x2)
#define ENABLE(mask) li x2, PLIC_ENABLE; li x3, mask; sw x3, 0(x2)
//Источники для векторного режима: x21 - копия уровней, обработчик снимает только свой бит
#define VSRC(mask)   li x21, mask; li x2, SIM_PLIC_SRC; sw x21, 0(x2)
#define WAIT         nop; nop; nop; nop; nop; nop; nop; nop; nop; nop; nop; nop; nop; nop; nop; nop

RVTEST_CODE_BEGIN
    LA_ABS(x1, vtable); ori x1, x1, 1; csrw mtvec, x1
    li x23, 0

    //#1 Ожидание (pending) не зависит от разрешения; claim при запрете возвращает 0
    TEST_CASE( 1, x14, 1 << 2, ("pending[src2,disabled]"),   SRC(1 << 2); nop; nop; li x2, PLIC_PENDING; lw x14, 0(x2))
    TEST_CASE( 2, x14, 0,      ("claim[disabled]=0"),        CLAIM(x14))
    TEST_CASE( 3, x14, 0,      ("meip[disabled]=0"),         csrr x14, mip; li x4, MIP_MEIP; and x14, x14, x4)
    //#2 Разрешение и приоритет
    TEST_CASE( 4, x14, MIP_MEIP, ("meip[enabled,prio=1]"),   PRIO(2, 1); li x2, PLIC_ENABLE; li x3, 1 << 2; sw x3, 0(x2); nop; nop; \
                                                             csrr x14, mip; li x4, MIP_MEIP; and x14, x14, x4)
    TEST_CASE( 5, x14, 2,      ("claim=2"),                  CLAIM(x14))
    TEST_CASE( 6, x14, 0,      ("pending-cleared-by-claim"), nop; li x2, PLIC_PENDING; lw x14, 0(x2))
    TEST_CASE( 7, x14, 0,      ("meip=0:claimed(busy)"),     csrr x14, mip; li x4, MIP_MEIP; and x14, x14, x4)
    TEST_CASE( 8, x14, 1 << 2, ("level:re-pend-after-complete"), COMPLETE(2); nop; nop; li x2, PLIC_PENDING; lw x14, 0(x2))
    TEST_CASE( 9, x14, 0,      ("no-re-pend:src-low"),       CLAIM(x14); SRC(0); COMPLETE(2); nop; nop; li x2, PLIC_PENDING; lw x14, 0(x2))

    //#3 Выбор по приоритету, при равенстве - меньший номер
    PRIO(3, 5); PRIO(4, 5); PRIO(5, 2); PRIO(6, 0)
    li x2, PLIC_ENABLE; li x3, (1 << 3) | (1 << 4) | (1 << 5) | (1 << 6); sw x3, 0(x2)
    SRC((1 << 3) | (1 << 4) | (1 << 5) | (1 << 6)); nop; nop
    TEST_CASE(10, x14, 3, ("claim[prio5,tie->lower-id]=3"),  CLAIM(x14))
    TEST_CASE(11, x14, 4, ("claim[next]=4"),                 CLAIM(x14))
    TEST_CASE(12, x14, 5, ("claim[prio2]=5"),                CLAIM(x14))
    TEST_CASE(13, x14, 0, ("claim[prio0-never]=0"),          CLAIM(x14))
    SRC(0); COMPLETE(3); COMPLETE(4); COMPLETE(5)
    //#4 Порог
    SRC((1 << 3) | (1 << 5)); nop; nop
    TEST_CASE(14, x14, 3, ("threshold=4:claim=3"),           li x2, PLIC_THRESHOLD; li x3, 4; sw x3, 0(x2); CLAIM(x14))
    TEST_CASE(15, x14, 0, ("threshold=4:prio2-masked"),      CLAIM(x14))
    TEST_CASE(16, x14, 0, ("threshold=5:meip=0"),            li x2, PLIC_THRESHOLD; li x3, 5; sw x3, 0(x2); SRC(1 << 3); COMPLETE(3); nop; nop; \
                                                             csrr x14, mip; li x4, MIP_MEIP; and x14, x14, x4)
    SRC(0); COMPLETE(5)
    li x2, PLIC_THRESHOLD; sw x0, 0(x2)
    li x2, PLIC_PENDING; lw x14, 0(x2)                  //Остатки ожидания - снять claim
1:  CLAIM(x14); beqz x14, 2f; mv x3, x14; li x2, PLIC_CLAIM; sw x3, 0(x2); j 1b
2:

    //#5 Прерывание MEI (mcause 11, вектор BASE+0x2C): обработчик claim -> снять источник -> complete
    li x1, MIP_MEIP; csrs mie, x1; csrsi mstatus, 8
    TEST_CASE(17, x23, 1, ("mei[taken]"),                    li x23, 0; PRIO(7, 3); li x2, PLIC_ENABLE; li x3, 1 << 7; sw x3, 0(x2); \
                                                             SRC(1 << 7); nop; nop; nop; nop; nop; nop)
    TEST_CASE(18, x20, 0x8000000B, ("mei[mcause=11]"),       nop)
    TEST_CASE(19, x26, 7, ("mei[isr-claimed-id=7]"),         nop)
    TEST_CASE(20, x14, 0, ("mei[completed,no-repeat]"),      nop; nop; nop; mv x14, x23; addi x14, x14, -1)
    //#6 Источник 1 - таймер тестбенча через PLIC
    TEST_CASE(21, x26, 1, ("mei[stim-via-plic:id=1]"),       li x23, 0; PRIO(1, 1); li x2, PLIC_ENABLE; li x3, 1 << 1; sw x3, 0(x2); \
                                                             li x2, TBTIM_BASE; sw x0, TBTIM_PR(x2); li x1, 20; sw x1, TBTIM_PER(x2); \
                                                             li x1, TBTIM_CR_EN | TBTIM_CR_UIE; sw x1, TBTIM_CR(x2); \
                                                             li x3, 200; 3: bnez x23, 4f; addi x3, x3, -1; bnez x3, 3b; 4:)
    csrci mstatus, 8; csrw mie, x0
    li x2, TBTIM_BASE; sw x0, TBTIM_CR(x2)
    SRC(0); ENABLE(0)
    li x2, PLIC_BASE + 4; li x3, 7; 5: sw x0, 0(x2); addi x2, x2, 4; addi x3, x3, -1; bnez x3, 5b

    //#7 Векторный режим: MEI источника S - на вход 32 + S, PLIC захватывает источник сам (claim не нужен)
    TEST_CASE(22, x14, 1, ("vector-reg=1"),                  li x2, PLIC_VECTOR; li x3, 1; sw x3, 0(x2); lw x14, 0(x2))
    li x1, MIP_MEIP; csrs mie, x1; csrsi mstatus, 8
    TEST_CASE(23, x23, 1, ("vec[taken]"),                    li x22, 0; li x23, 0; PRIO(2, 1); ENABLE(1 << 2); VSRC(1 << 2); WAIT)
    TEST_CASE(24, x26, 2, ("vec[entry=32+2]"),               nop)
    TEST_CASE(25, x20, 0x8000000B, ("vec[mcause=11]"),       nop)
    TEST_CASE(26, x14, 0, ("vec[auto-claim:pending=0]"),     andi x14, x27, 1 << 2)
    TEST_CASE(27, x14, 0, ("vec[completed:claim=0]"),        CLAIM(x14))
    //Приоритет: два источника ждут при запрещённых прерываниях; сначала более важный, затем второй
    csrci mstatus, 8
    TEST_CASE(28, x22, 0x63, ("vec[order:prio6,then-prio2]"), li x22, 0; li x23, 0; PRIO(3, 2); PRIO(6, 6); ENABLE((1 << 3) | (1 << 6)); \
                                                             VSRC((1 << 3) | (1 << 6)); WAIT; csrsi mstatus, 8; WAIT; WAIT)
    TEST_CASE(29, x23, 2, ("vec[two-entries]"),              nop)
    csrci mstatus, 8
    TEST_CASE(30, x22, 0x47, ("vec[tie->lower-id]"),         li x22, 0; PRIO(4, 5); PRIO(7, 5); ENABLE((1 << 4) | (1 << 7)); \
                                                             VSRC((1 << 4) | (1 << 7)); WAIT; csrsi mstatus, 8; WAIT; WAIT)
    //Прямой режим mtvec (MODE = 0): векторный режим PLIC не действует - вход BASE, claim программой
    csrci mstatus, 8
    LA_ABS(x1, direct_isr); csrw mtvec, x1
    TEST_CASE(31, x26, 5, ("mtvec-direct:claim-by-isr=5"),   li x23, 0; li x26, 0; PRIO(5, 1); ENABLE(1 << 5); SRC(1 << 5); csrsi mstatus, 8; WAIT)
    TEST_CASE(32, x20, 0x8000000B, ("mtvec-direct[mcause=11]"), nop)
    csrci mstatus, 8
    LA_ABS(x1, vtable); ori x1, x1, 1; csrw mtvec, x1
    //Векторный режим выключен - снова вход 11 и claim программой
    TEST_CASE(33, x26, 8, ("vector-off:entry-11,claim=8"),   li x2, PLIC_VECTOR; sw x0, 0(x2); li x22, 0; li x26, 0; \
                                                             PRIO(8, 1); ENABLE(1 << 8); SRC(1 << 8); csrsi mstatus, 8; WAIT)
    TEST_CASE(34, x22, 0, ("vector-off:no-vector-entry"),    nop)
    csrci mstatus, 8; csrw mie, x0
    j pass

//Таблица векторов: исключения (ошибка теста), MEI (вход 11) и источники PLIC 1..8 (входы 33..40).
//С векторным режимом PLIC таблица - 64 входа, выравнивание 256 байт
    .balign 256
vtable:
    j bad_isr
    .rept 10
    j bad_isr
    .endr
    j mei_isr       //11
    .rept 20
    j bad_isr
    .endr
    j bad_isr       //32: источник 0 не существует
    j vi1           //33..40: источники 1..8
    j vi2
    j vi3
    j vi4
    j vi5
    j vi6
    j vi7
    j vi8
    .rept 23
    j bad_isr
    .endr

//Векторный обработчик источника S: номер - в x26, порядок входов - в x22 (по 4 бита), ожидание при входе
//(свой источник ещё активен, но уже захвачен) - в x27; снять свой уровень, complete
vi1: li x26, 1; j vec_common
vi2: li x26, 2; j vec_common
vi3: li x26, 3; j vec_common
vi4: li x26, 4; j vec_common
vi5: li x26, 5; j vec_common
vi6: li x26, 6; j vec_common
vi7: li x26, 7; j vec_common
vi8: li x26, 8; j vec_common
vec_common:
    csrr x20, mcause; addi x23, x23, 1
    slli x22, x22, 4; or x22, x22, x26
    li x24, PLIC_PENDING; lw x27, 0(x24)
    li x24, 1; sll x24, x24, x26; not x24, x24; and x21, x21, x24
    li x25, SIM_PLIC_SRC; sw x21, 0(x25)
    li x24, PLIC_CLAIM; sw x26, 0(x24)
    mret

//Прямой режим mtvec: все ловушки сюда; прерывание MEI - claim, снять источник, complete
    .balign 4
direct_isr:
    csrr x20, mcause; addi x23, x23, 1
    li x24, 0x8000000B; bne x20, x24, bad_isr
    li x24, PLIC_CLAIM; lw x26, 0(x24)
    li x25, SIM_PLIC_SRC; sw x0, 0(x25)
    sw x26, 0(x24)
    mret

//Обработчик MEI: claim, сбросить источник (у тестбенча или таймера), complete
mei_isr:
    csrr x20, mcause; addi x23, x23, 1
    li x24, PLIC_CLAIM; lw x26, 0(x24)
    li x25, 1; bne x26, x25, 1f
    li x25, TBTIM_BASE; sw x0, TBTIM_CR(x25); li x21, 1; sw x21, TBTIM_SR(x25)   //таймер: выключить и сбросить UIF
    j 2f
1:  li x25, SIM_PLIC_SRC; sw x0, 0(x25)
2:  sw x26, 0(x24)
    mret

bad_isr:
    csrr ACTUAL, mcause; li EXPECTED, -1; j fail
RVTEST_CODE_END
