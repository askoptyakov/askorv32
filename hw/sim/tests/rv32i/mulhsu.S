// mulhsu.S - тесты инструкции MULHSU: расширение M
// Сгенерировано gen_rv32i.py - не редактировать вручную.
#include "riscv_test.h"

RVTEST_CODE_BEGIN

    //Значения
    TEST_RR_OP(1, mulhsu, 0x00000000, 0x00000000, 0x00000000)
    TEST_RR_OP(2, mulhsu, 0x00000000, 0x00000001, 0x00000001)
    TEST_RR_OP(3, mulhsu, 0x00000000, 0x00000003, 0x00000007)
    TEST_RR_OP(4, mulhsu, 0x00000000, 0x00000000, 0xffff8000)
    TEST_RR_OP(5, mulhsu, 0x00000000, 0x80000000, 0x00000000)
    TEST_RR_OP(6, mulhsu, 0x80004000, 0x80000000, 0xffff8000)
    TEST_RR_OP(7, mulhsu, 0x00000000, 0x00000000, 0x00007fff)
    TEST_RR_OP(8, mulhsu, 0x00000000, 0x7fffffff, 0x00000000)
    TEST_RR_OP(9, mulhsu, 0x00003fff, 0x7fffffff, 0x00007fff)
    TEST_RR_OP(10, mulhsu, 0xffffc000, 0x80000000, 0x00007fff)
    TEST_RR_OP(11, mulhsu, 0x7fffbfff, 0x7fffffff, 0xffff8000)
    TEST_RR_OP(12, mulhsu, 0x00000000, 0x00000000, 0xffffffff)
    TEST_RR_OP(13, mulhsu, 0xffffffff, 0xffffffff, 0x00000001)
    TEST_RR_OP(14, mulhsu, 0xffffffff, 0xffffffff, 0xffffffff)
    TEST_RR_OP(15, mulhsu, 0x00000000, 0x00000001, 0x7fffffff)
    TEST_RR_OP(16, mulhsu, 0x3fffffff, 0x7fffffff, 0x80000000)
    TEST_RR_OP(17, mulhsu, 0xc0000000, 0x80000000, 0x7fffffff)
    TEST_RR_OP(18, mulhsu, 0x00000000, 0xffffffff, 0x00000000)
    TEST_RR_OP(19, mulhsu, 0x38e38e38, 0x55555555, 0xaaaaaaaa)
    TEST_RR_OP(20, mulhsu, 0x121fa00a, 0x12345678, 0xfedcba98)
    TEST_RR_OP(21, mulhsu, 0x000f000e, 0x0f0f0f0f, 0x00ff00ff)
    TEST_RR_OP(22, mulhsu, 0x80000000, 0x80000000, 0xffffffff)
    TEST_RR_OP(23, mulhsu, 0xffffffff, 0x80000000, 0x00000001)
    TEST_RR_OP(24, mulhsu, 0x00000006, 0x00000007, 0xfffffffd)
    TEST_RR_OP(25, mulhsu, 0xffffffff, 0xfffffff9, 0x00000003)
    TEST_RR_OP(26, mulhsu, 0xfffffff9, 0xfffffff9, 0xfffffffd)
    TEST_RR_OP(27, mulhsu, 0x00000000, 0x00000007, 0x00000003)
    TEST_RR_OP(28, mulhsu, 0xfffffffe, 0xfffffffe, 0xffffffff)
    TEST_RR_OP(29, mulhsu, 0xffffffff, 0xffffffff, 0x80000000)
    TEST_RR_OP(30, mulhsu, 0x00000c37, 0x12345678, 0x0000abcd)
    TEST_RR_OP(31, mulhsu, 0xfffffffd, 0xdeadbeef, 0x00000010)
    TEST_RR_OP(32, mulhsu, 0x00000001, 0x00010000, 0x00010000)
    TEST_RR_OP(33, mulhsu, 0xffffffff, 0xffff0000, 0x0000ffff)
    TEST_RR_OP(34, mulhsu, 0x0000f120, 0x0001e240, 0x80000001)
    TEST_RR_OP(35, mulhsu, 0xffffffff, 0xffffffff, 0x7fffffff)
    TEST_RR_OP(36, mulhsu, 0x36b1b9d8, 0x76543210, 0x76543211)

    //Совпадение регистров
    TEST_RR_SRC1_EQ_DEST(37, mulhsu, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC2_EQ_DEST(38, mulhsu, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_EQ_DEST(39, mulhsu, 0x00000000, 0x0000000d)

    //Байпас (конвейер)
    TEST_RR_DEST_BYPASS(40, 0, mulhsu, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_DEST_BYPASS(41, 1, mulhsu, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_DEST_BYPASS(42, 2, mulhsu, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(43, 0, 0, mulhsu, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(44, 0, 1, mulhsu, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(45, 0, 2, mulhsu, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(46, 1, 0, mulhsu, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(47, 1, 1, mulhsu, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(48, 2, 0, mulhsu, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(49, 0, 0, mulhsu, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(50, 0, 1, mulhsu, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(51, 0, 2, mulhsu, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(52, 1, 0, mulhsu, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(53, 1, 1, mulhsu, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(54, 2, 0, mulhsu, 0xfffffffa, 0x87654321, 0x0000000b)

    //Регистр x0
    TEST_RR_ZEROSRC1(55, mulhsu, 0x00000000, 0x0000000b)
    TEST_RR_ZEROSRC2(56, mulhsu, 0x00000000, 0x87654321)
    TEST_RR_ZEROSRC12(57, mulhsu, 0x00000000)
    TEST_RR_ZERODEST(58, mulhsu, 0x87654321, 0x0000000b)

    //Зависимые цепочки (конвейер)
    TEST_CASE(59, x14, 0xffffffff, ("mulhsu->mulhsu"), li x1, 0x87654321; li x2, 0x0000000b; mulhsu x3, x1, x2; mulhsu x14, x3, x2)
    TEST_CASE(60, x14, 0x33333332, ("mulhsu->divu"), li x1, 0x87654321; li x2, 0x0000000b; li x4, 0x00000005; mulhsu x3, x1, x2; divu x14, x3, x4)
    TEST_CASE(61, x14, 0x00000001, ("divu->mulhsu"), li x1, 0x87654321; li x2, 0x0000000b; li x4, 0x00000005; divu x3, x1, x4; mulhsu x14, x3, x2)
    TEST_CASE(62, x14, 0x8765431e, ("mulhsu[addi,addi,add]"), li x1, 0x87654321; li x2, 0x0000000b; mulhsu x3, x1, x2; addi x4, x1, 1; addi x4, x4, 2; add x14, x3, x4)
    TEST_CASE(63, x14, 0xfffffffa, ("mulhsu->sw->lw"), la x5, md_buf; li x1, 0x87654321; li x2, 0x0000000b; mulhsu x3, x1, x2; sw x3, 0(x5); lw x14, 0(x5))
    TEST_CASE(64, x14, 0x00000002, ("mulhsu->bnez"), li x1, 0x87654321; li x2, 0x0000000b; li x14, 2; mulhsu x3, x1, x2; bnez x3, 1f; li x14, 1; 1: nop)

    j pass
RVTEST_CODE_END

RVTEST_DATA_BEGIN
    .align 2
md_buf: .word 0
