// mulhu.S - тесты инструкции MULHU: расширение M
// Сгенерировано gen_rv32i.py - не редактировать вручную.
#include "riscv_test.h"

RVTEST_CODE_BEGIN

    //Значения
    TEST_RR_OP(1, mulhu, 0x00000000, 0x00000000, 0x00000000)
    TEST_RR_OP(2, mulhu, 0x00000000, 0x00000001, 0x00000001)
    TEST_RR_OP(3, mulhu, 0x00000000, 0x00000003, 0x00000007)
    TEST_RR_OP(4, mulhu, 0x00000000, 0x00000000, 0xffff8000)
    TEST_RR_OP(5, mulhu, 0x00000000, 0x80000000, 0x00000000)
    TEST_RR_OP(6, mulhu, 0x7fffc000, 0x80000000, 0xffff8000)
    TEST_RR_OP(7, mulhu, 0x00000000, 0x00000000, 0x00007fff)
    TEST_RR_OP(8, mulhu, 0x00000000, 0x7fffffff, 0x00000000)
    TEST_RR_OP(9, mulhu, 0x00003fff, 0x7fffffff, 0x00007fff)
    TEST_RR_OP(10, mulhu, 0x00003fff, 0x80000000, 0x00007fff)
    TEST_RR_OP(11, mulhu, 0x7fffbfff, 0x7fffffff, 0xffff8000)
    TEST_RR_OP(12, mulhu, 0x00000000, 0x00000000, 0xffffffff)
    TEST_RR_OP(13, mulhu, 0x00000000, 0xffffffff, 0x00000001)
    TEST_RR_OP(14, mulhu, 0xfffffffe, 0xffffffff, 0xffffffff)
    TEST_RR_OP(15, mulhu, 0x00000000, 0x00000001, 0x7fffffff)
    TEST_RR_OP(16, mulhu, 0x3fffffff, 0x7fffffff, 0x80000000)
    TEST_RR_OP(17, mulhu, 0x3fffffff, 0x80000000, 0x7fffffff)
    TEST_RR_OP(18, mulhu, 0x00000000, 0xffffffff, 0x00000000)
    TEST_RR_OP(19, mulhu, 0x38e38e38, 0x55555555, 0xaaaaaaaa)
    TEST_RR_OP(20, mulhu, 0x121fa00a, 0x12345678, 0xfedcba98)
    TEST_RR_OP(21, mulhu, 0x000f000e, 0x0f0f0f0f, 0x00ff00ff)
    TEST_RR_OP(22, mulhu, 0x7fffffff, 0x80000000, 0xffffffff)
    TEST_RR_OP(23, mulhu, 0x00000000, 0x80000000, 0x00000001)
    TEST_RR_OP(24, mulhu, 0x00000006, 0x00000007, 0xfffffffd)
    TEST_RR_OP(25, mulhu, 0x00000002, 0xfffffff9, 0x00000003)
    TEST_RR_OP(26, mulhu, 0xfffffff6, 0xfffffff9, 0xfffffffd)
    TEST_RR_OP(27, mulhu, 0x00000000, 0x00000007, 0x00000003)
    TEST_RR_OP(28, mulhu, 0xfffffffd, 0xfffffffe, 0xffffffff)
    TEST_RR_OP(29, mulhu, 0x7fffffff, 0xffffffff, 0x80000000)
    TEST_RR_OP(30, mulhu, 0x00000c37, 0x12345678, 0x0000abcd)
    TEST_RR_OP(31, mulhu, 0x0000000d, 0xdeadbeef, 0x00000010)
    TEST_RR_OP(32, mulhu, 0x00000001, 0x00010000, 0x00010000)
    TEST_RR_OP(33, mulhu, 0x0000fffe, 0xffff0000, 0x0000ffff)
    TEST_RR_OP(34, mulhu, 0x0000f120, 0x0001e240, 0x80000001)
    TEST_RR_OP(35, mulhu, 0x7ffffffe, 0xffffffff, 0x7fffffff)
    TEST_RR_OP(36, mulhu, 0x36b1b9d8, 0x76543210, 0x76543211)

    //Совпадение регистров
    TEST_RR_SRC1_EQ_DEST(37, mulhu, 0x00000005, 0x87654321, 0x0000000b)
    TEST_RR_SRC2_EQ_DEST(38, mulhu, 0x00000005, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_EQ_DEST(39, mulhu, 0x00000000, 0x0000000d)

    //Байпас (конвейер)
    TEST_RR_DEST_BYPASS(40, 0, mulhu, 0x00000005, 0x87654321, 0x0000000b)
    TEST_RR_DEST_BYPASS(41, 1, mulhu, 0x00000005, 0x87654321, 0x0000000b)
    TEST_RR_DEST_BYPASS(42, 2, mulhu, 0x00000005, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(43, 0, 0, mulhu, 0x00000005, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(44, 0, 1, mulhu, 0x00000005, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(45, 0, 2, mulhu, 0x00000005, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(46, 1, 0, mulhu, 0x00000005, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(47, 1, 1, mulhu, 0x00000005, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(48, 2, 0, mulhu, 0x00000005, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(49, 0, 0, mulhu, 0x00000005, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(50, 0, 1, mulhu, 0x00000005, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(51, 0, 2, mulhu, 0x00000005, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(52, 1, 0, mulhu, 0x00000005, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(53, 1, 1, mulhu, 0x00000005, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(54, 2, 0, mulhu, 0x00000005, 0x87654321, 0x0000000b)

    //Регистр x0
    TEST_RR_ZEROSRC1(55, mulhu, 0x00000000, 0x0000000b)
    TEST_RR_ZEROSRC2(56, mulhu, 0x00000000, 0x87654321)
    TEST_RR_ZEROSRC12(57, mulhu, 0x00000000)
    TEST_RR_ZERODEST(58, mulhu, 0x87654321, 0x0000000b)

    //Зависимые цепочки (конвейер)
    TEST_CASE(59, x14, 0x00000000, ("mulhu->mulhu"), li x1, 0x87654321; li x2, 0x0000000b; mulhu x3, x1, x2; mulhu x14, x3, x2)
    TEST_CASE(60, x14, 0x00000001, ("mulhu->divu"), li x1, 0x87654321; li x2, 0x0000000b; li x4, 0x00000005; mulhu x3, x1, x2; divu x14, x3, x4)
    TEST_CASE(61, x14, 0x00000001, ("divu->mulhu"), li x1, 0x87654321; li x2, 0x0000000b; li x4, 0x00000005; divu x3, x1, x4; mulhu x14, x3, x2)
    TEST_CASE(62, x14, 0x87654329, ("mulhu[addi,addi,add]"), li x1, 0x87654321; li x2, 0x0000000b; mulhu x3, x1, x2; addi x4, x1, 1; addi x4, x4, 2; add x14, x3, x4)
    TEST_CASE(63, x14, 0x00000005, ("mulhu->sw->lw"), la x5, md_buf; li x1, 0x87654321; li x2, 0x0000000b; mulhu x3, x1, x2; sw x3, 0(x5); lw x14, 0(x5))
    TEST_CASE(64, x14, 0x00000002, ("mulhu->bnez"), li x1, 0x87654321; li x2, 0x0000000b; li x14, 2; mulhu x3, x1, x2; bnez x3, 1f; li x14, 1; 1: nop)

    j pass
RVTEST_CODE_END

RVTEST_DATA_BEGIN
    .align 2
md_buf: .word 0
