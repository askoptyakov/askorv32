// mulh.S - тесты инструкции MULH: расширение M
// Сгенерировано gen_rv32i.py - не редактировать вручную.
#include "riscv_test.h"

RVTEST_CODE_BEGIN

    //Значения
    TEST_RR_OP(1, mulh, 0x00000000, 0x00000000, 0x00000000)
    TEST_RR_OP(2, mulh, 0x00000000, 0x00000001, 0x00000001)
    TEST_RR_OP(3, mulh, 0x00000000, 0x00000003, 0x00000007)
    TEST_RR_OP(4, mulh, 0x00000000, 0x00000000, 0xffff8000)
    TEST_RR_OP(5, mulh, 0x00000000, 0x80000000, 0x00000000)
    TEST_RR_OP(6, mulh, 0x00004000, 0x80000000, 0xffff8000)
    TEST_RR_OP(7, mulh, 0x00000000, 0x00000000, 0x00007fff)
    TEST_RR_OP(8, mulh, 0x00000000, 0x7fffffff, 0x00000000)
    TEST_RR_OP(9, mulh, 0x00003fff, 0x7fffffff, 0x00007fff)
    TEST_RR_OP(10, mulh, 0xffffc000, 0x80000000, 0x00007fff)
    TEST_RR_OP(11, mulh, 0xffffc000, 0x7fffffff, 0xffff8000)
    TEST_RR_OP(12, mulh, 0x00000000, 0x00000000, 0xffffffff)
    TEST_RR_OP(13, mulh, 0xffffffff, 0xffffffff, 0x00000001)
    TEST_RR_OP(14, mulh, 0x00000000, 0xffffffff, 0xffffffff)
    TEST_RR_OP(15, mulh, 0x00000000, 0x00000001, 0x7fffffff)
    TEST_RR_OP(16, mulh, 0xc0000000, 0x7fffffff, 0x80000000)
    TEST_RR_OP(17, mulh, 0xc0000000, 0x80000000, 0x7fffffff)
    TEST_RR_OP(18, mulh, 0x00000000, 0xffffffff, 0x00000000)
    TEST_RR_OP(19, mulh, 0xe38e38e3, 0x55555555, 0xaaaaaaaa)
    TEST_RR_OP(20, mulh, 0xffeb4992, 0x12345678, 0xfedcba98)
    TEST_RR_OP(21, mulh, 0x000f000e, 0x0f0f0f0f, 0x00ff00ff)
    TEST_RR_OP(22, mulh, 0x00000000, 0x80000000, 0xffffffff)
    TEST_RR_OP(23, mulh, 0xffffffff, 0x80000000, 0x00000001)
    TEST_RR_OP(24, mulh, 0xffffffff, 0x00000007, 0xfffffffd)
    TEST_RR_OP(25, mulh, 0xffffffff, 0xfffffff9, 0x00000003)
    TEST_RR_OP(26, mulh, 0x00000000, 0xfffffff9, 0xfffffffd)
    TEST_RR_OP(27, mulh, 0x00000000, 0x00000007, 0x00000003)
    TEST_RR_OP(28, mulh, 0x00000000, 0xfffffffe, 0xffffffff)
    TEST_RR_OP(29, mulh, 0x00000000, 0xffffffff, 0x80000000)
    TEST_RR_OP(30, mulh, 0x00000c37, 0x12345678, 0x0000abcd)
    TEST_RR_OP(31, mulh, 0xfffffffd, 0xdeadbeef, 0x00000010)
    TEST_RR_OP(32, mulh, 0x00000001, 0x00010000, 0x00010000)
    TEST_RR_OP(33, mulh, 0xffffffff, 0xffff0000, 0x0000ffff)
    TEST_RR_OP(34, mulh, 0xffff0ee0, 0x0001e240, 0x80000001)
    TEST_RR_OP(35, mulh, 0xffffffff, 0xffffffff, 0x7fffffff)
    TEST_RR_OP(36, mulh, 0x36b1b9d8, 0x76543210, 0x76543211)

    //Совпадение регистров
    TEST_RR_SRC1_EQ_DEST(37, mulh, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC2_EQ_DEST(38, mulh, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_EQ_DEST(39, mulh, 0x00000000, 0x0000000d)

    //Байпас (конвейер)
    TEST_RR_DEST_BYPASS(40, 0, mulh, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_DEST_BYPASS(41, 1, mulh, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_DEST_BYPASS(42, 2, mulh, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(43, 0, 0, mulh, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(44, 0, 1, mulh, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(45, 0, 2, mulh, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(46, 1, 0, mulh, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(47, 1, 1, mulh, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(48, 2, 0, mulh, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(49, 0, 0, mulh, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(50, 0, 1, mulh, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(51, 0, 2, mulh, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(52, 1, 0, mulh, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(53, 1, 1, mulh, 0xfffffffa, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(54, 2, 0, mulh, 0xfffffffa, 0x87654321, 0x0000000b)

    //Регистр x0
    TEST_RR_ZEROSRC1(55, mulh, 0x00000000, 0x0000000b)
    TEST_RR_ZEROSRC2(56, mulh, 0x00000000, 0x87654321)
    TEST_RR_ZEROSRC12(57, mulh, 0x00000000)
    TEST_RR_ZERODEST(58, mulh, 0x87654321, 0x0000000b)

    //Зависимые цепочки (конвейер)
    TEST_CASE(59, x14, 0xffffffff, ("mulh->mulh"), li x1, 0x87654321; li x2, 0x0000000b; mulh x3, x1, x2; mulh x14, x3, x2)
    TEST_CASE(60, x14, 0x33333332, ("mulh->divu"), li x1, 0x87654321; li x2, 0x0000000b; li x4, 0x00000005; mulh x3, x1, x2; divu x14, x3, x4)
    TEST_CASE(61, x14, 0x00000001, ("divu->mulh"), li x1, 0x87654321; li x2, 0x0000000b; li x4, 0x00000005; divu x3, x1, x4; mulh x14, x3, x2)
    TEST_CASE(62, x14, 0x8765431e, ("mulh[addi,addi,add]"), li x1, 0x87654321; li x2, 0x0000000b; mulh x3, x1, x2; addi x4, x1, 1; addi x4, x4, 2; add x14, x3, x4)
    TEST_CASE(63, x14, 0xfffffffa, ("mulh->sw->lw"), la x5, md_buf; li x1, 0x87654321; li x2, 0x0000000b; mulh x3, x1, x2; sw x3, 0(x5); lw x14, 0(x5))
    TEST_CASE(64, x14, 0x00000002, ("mulh->bnez"), li x1, 0x87654321; li x2, 0x0000000b; li x14, 2; mulh x3, x1, x2; bnez x3, 1f; li x14, 1; 1: nop)

    j pass
RVTEST_CODE_END

RVTEST_DATA_BEGIN
    .align 2
md_buf: .word 0
