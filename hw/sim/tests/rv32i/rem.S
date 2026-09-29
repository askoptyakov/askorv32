// rem.S - тесты инструкции REM: расширение M
// Сгенерировано gen_rv32i.py - не редактировать вручную.
#include "riscv_test.h"

RVTEST_CODE_BEGIN

    //Значения
    TEST_RR_OP(1, rem, 0x00000000, 0x00000000, 0x00000000)
    TEST_RR_OP(2, rem, 0x00000000, 0x00000001, 0x00000001)
    TEST_RR_OP(3, rem, 0x00000003, 0x00000003, 0x00000007)
    TEST_RR_OP(4, rem, 0x00000000, 0x00000000, 0xffff8000)
    TEST_RR_OP(5, rem, 0x80000000, 0x80000000, 0x00000000)
    TEST_RR_OP(6, rem, 0x00000000, 0x80000000, 0xffff8000)
    TEST_RR_OP(7, rem, 0x00000000, 0x00000000, 0x00007fff)
    TEST_RR_OP(8, rem, 0x7fffffff, 0x7fffffff, 0x00000000)
    TEST_RR_OP(9, rem, 0x00000001, 0x7fffffff, 0x00007fff)
    TEST_RR_OP(10, rem, 0xfffffffe, 0x80000000, 0x00007fff)
    TEST_RR_OP(11, rem, 0x00007fff, 0x7fffffff, 0xffff8000)
    TEST_RR_OP(12, rem, 0x00000000, 0x00000000, 0xffffffff)
    TEST_RR_OP(13, rem, 0x00000000, 0xffffffff, 0x00000001)
    TEST_RR_OP(14, rem, 0x00000000, 0xffffffff, 0xffffffff)
    TEST_RR_OP(15, rem, 0x00000001, 0x00000001, 0x7fffffff)
    TEST_RR_OP(16, rem, 0x7fffffff, 0x7fffffff, 0x80000000)
    TEST_RR_OP(17, rem, 0xffffffff, 0x80000000, 0x7fffffff)
    TEST_RR_OP(18, rem, 0xffffffff, 0xffffffff, 0x00000000)
    TEST_RR_OP(19, rem, 0x55555555, 0x55555555, 0xaaaaaaaa)
    TEST_RR_OP(20, rem, 0x01234560, 0x12345678, 0xfedcba98)
    TEST_RR_OP(21, rem, 0x001e001e, 0x0f0f0f0f, 0x00ff00ff)
    TEST_RR_OP(22, rem, 0x00000000, 0x80000000, 0xffffffff)
    TEST_RR_OP(23, rem, 0x00000000, 0x80000000, 0x00000001)
    TEST_RR_OP(24, rem, 0x00000001, 0x00000007, 0xfffffffd)
    TEST_RR_OP(25, rem, 0xffffffff, 0xfffffff9, 0x00000003)
    TEST_RR_OP(26, rem, 0xffffffff, 0xfffffff9, 0xfffffffd)
    TEST_RR_OP(27, rem, 0x00000001, 0x00000007, 0x00000003)
    TEST_RR_OP(28, rem, 0x00000000, 0xfffffffe, 0xffffffff)
    TEST_RR_OP(29, rem, 0xffffffff, 0xffffffff, 0x80000000)
    TEST_RR_OP(30, rem, 0x00003dd8, 0x12345678, 0x0000abcd)
    TEST_RR_OP(31, rem, 0xffffffff, 0xdeadbeef, 0x00000010)
    TEST_RR_OP(32, rem, 0x00000000, 0x00010000, 0x00010000)
    TEST_RR_OP(33, rem, 0xffffffff, 0xffff0000, 0x0000ffff)
    TEST_RR_OP(34, rem, 0x0001e240, 0x0001e240, 0x80000001)
    TEST_RR_OP(35, rem, 0xffffffff, 0xffffffff, 0x7fffffff)
    TEST_RR_OP(36, rem, 0x76543210, 0x76543210, 0x76543211)

    //Совпадение регистров
    TEST_RR_SRC1_EQ_DEST(37, rem, 0xffffffff, 0x87654321, 0x0000000b)
    TEST_RR_SRC2_EQ_DEST(38, rem, 0xffffffff, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_EQ_DEST(39, rem, 0x00000000, 0x0000000d)

    //Байпас (конвейер)
    TEST_RR_DEST_BYPASS(40, 0, rem, 0xffffffff, 0x87654321, 0x0000000b)
    TEST_RR_DEST_BYPASS(41, 1, rem, 0xffffffff, 0x87654321, 0x0000000b)
    TEST_RR_DEST_BYPASS(42, 2, rem, 0xffffffff, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(43, 0, 0, rem, 0xffffffff, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(44, 0, 1, rem, 0xffffffff, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(45, 0, 2, rem, 0xffffffff, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(46, 1, 0, rem, 0xffffffff, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(47, 1, 1, rem, 0xffffffff, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(48, 2, 0, rem, 0xffffffff, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(49, 0, 0, rem, 0xffffffff, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(50, 0, 1, rem, 0xffffffff, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(51, 0, 2, rem, 0xffffffff, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(52, 1, 0, rem, 0xffffffff, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(53, 1, 1, rem, 0xffffffff, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(54, 2, 0, rem, 0xffffffff, 0x87654321, 0x0000000b)

    //Регистр x0
    TEST_RR_ZEROSRC1(55, rem, 0x00000000, 0x0000000b)
    TEST_RR_ZEROSRC2(56, rem, 0x87654321, 0x87654321)
    TEST_RR_ZEROSRC12(57, rem, 0x00000000)
    TEST_RR_ZERODEST(58, rem, 0x87654321, 0x0000000b)

    //Зависимые цепочки (конвейер)
    TEST_CASE(59, x14, 0xffffffff, ("rem->rem"), li x1, 0x87654321; li x2, 0x0000000b; rem x3, x1, x2; rem x14, x3, x2)
    TEST_CASE(60, x14, 0xfffffffb, ("rem->mul"), li x1, 0x87654321; li x2, 0x0000000b; li x4, 0x00000005; rem x3, x1, x2; mul x14, x3, x4)
    TEST_CASE(61, x14, 0xfffffff8, ("mul->rem"), li x1, 0x87654321; li x2, 0x0000000b; li x4, 0x00000005; mul x3, x1, x4; rem x14, x3, x2)
    TEST_CASE(62, x14, 0x87654323, ("rem[addi,addi,add]"), li x1, 0x87654321; li x2, 0x0000000b; rem x3, x1, x2; addi x4, x1, 1; addi x4, x4, 2; add x14, x3, x4)
    TEST_CASE(63, x14, 0xffffffff, ("rem->sw->lw"), la x5, md_buf; li x1, 0x87654321; li x2, 0x0000000b; rem x3, x1, x2; sw x3, 0(x5); lw x14, 0(x5))
    TEST_CASE(64, x14, 0x00000002, ("rem->bnez"), li x1, 0x87654321; li x2, 0x0000000b; li x14, 2; rem x3, x1, x2; bnez x3, 1f; li x14, 1; 1: nop)

    j pass
RVTEST_CODE_END

RVTEST_DATA_BEGIN
    .align 2
md_buf: .word 0
