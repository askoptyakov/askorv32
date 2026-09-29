// mul.S - тесты инструкции MUL: расширение M
// Сгенерировано gen_rv32i.py - не редактировать вручную.
#include "riscv_test.h"

RVTEST_CODE_BEGIN

    //Значения
    TEST_RR_OP(1, mul, 0x00000000, 0x00000000, 0x00000000)
    TEST_RR_OP(2, mul, 0x00000001, 0x00000001, 0x00000001)
    TEST_RR_OP(3, mul, 0x00000015, 0x00000003, 0x00000007)
    TEST_RR_OP(4, mul, 0x00000000, 0x00000000, 0xffff8000)
    TEST_RR_OP(5, mul, 0x00000000, 0x80000000, 0x00000000)
    TEST_RR_OP(6, mul, 0x00000000, 0x80000000, 0xffff8000)
    TEST_RR_OP(7, mul, 0x00000000, 0x00000000, 0x00007fff)
    TEST_RR_OP(8, mul, 0x00000000, 0x7fffffff, 0x00000000)
    TEST_RR_OP(9, mul, 0x7fff8001, 0x7fffffff, 0x00007fff)
    TEST_RR_OP(10, mul, 0x80000000, 0x80000000, 0x00007fff)
    TEST_RR_OP(11, mul, 0x00008000, 0x7fffffff, 0xffff8000)
    TEST_RR_OP(12, mul, 0x00000000, 0x00000000, 0xffffffff)
    TEST_RR_OP(13, mul, 0xffffffff, 0xffffffff, 0x00000001)
    TEST_RR_OP(14, mul, 0x00000001, 0xffffffff, 0xffffffff)
    TEST_RR_OP(15, mul, 0x7fffffff, 0x00000001, 0x7fffffff)
    TEST_RR_OP(16, mul, 0x80000000, 0x7fffffff, 0x80000000)
    TEST_RR_OP(17, mul, 0x80000000, 0x80000000, 0x7fffffff)
    TEST_RR_OP(18, mul, 0x00000000, 0xffffffff, 0x00000000)
    TEST_RR_OP(19, mul, 0x71c71c72, 0x55555555, 0xaaaaaaaa)
    TEST_RR_OP(20, mul, 0x35068740, 0x12345678, 0xfedcba98)
    TEST_RR_OP(21, mul, 0xfff0fff1, 0x0f0f0f0f, 0x00ff00ff)
    TEST_RR_OP(22, mul, 0x80000000, 0x80000000, 0xffffffff)
    TEST_RR_OP(23, mul, 0x80000000, 0x80000000, 0x00000001)
    TEST_RR_OP(24, mul, 0xffffffeb, 0x00000007, 0xfffffffd)
    TEST_RR_OP(25, mul, 0xffffffeb, 0xfffffff9, 0x00000003)
    TEST_RR_OP(26, mul, 0x00000015, 0xfffffff9, 0xfffffffd)
    TEST_RR_OP(27, mul, 0x00000015, 0x00000007, 0x00000003)
    TEST_RR_OP(28, mul, 0x00000002, 0xfffffffe, 0xffffffff)
    TEST_RR_OP(29, mul, 0x80000000, 0xffffffff, 0x80000000)
    TEST_RR_OP(30, mul, 0x89ab6618, 0x12345678, 0x0000abcd)
    TEST_RR_OP(31, mul, 0xeadbeef0, 0xdeadbeef, 0x00000010)
    TEST_RR_OP(32, mul, 0x00000000, 0x00010000, 0x00010000)
    TEST_RR_OP(33, mul, 0x00010000, 0xffff0000, 0x0000ffff)
    TEST_RR_OP(34, mul, 0x0001e240, 0x0001e240, 0x80000001)
    TEST_RR_OP(35, mul, 0x80000001, 0xffffffff, 0x7fffffff)
    TEST_RR_OP(36, mul, 0x1a9e7310, 0x76543210, 0x76543211)

    //Совпадение регистров
    TEST_RR_SRC1_EQ_DEST(37, mul, 0xd159e26b, 0x87654321, 0x0000000b)
    TEST_RR_SRC2_EQ_DEST(38, mul, 0xd159e26b, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_EQ_DEST(39, mul, 0x000000a9, 0x0000000d)

    //Байпас (конвейер)
    TEST_RR_DEST_BYPASS(40, 0, mul, 0xd159e26b, 0x87654321, 0x0000000b)
    TEST_RR_DEST_BYPASS(41, 1, mul, 0xd159e26b, 0x87654321, 0x0000000b)
    TEST_RR_DEST_BYPASS(42, 2, mul, 0xd159e26b, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(43, 0, 0, mul, 0xd159e26b, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(44, 0, 1, mul, 0xd159e26b, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(45, 0, 2, mul, 0xd159e26b, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(46, 1, 0, mul, 0xd159e26b, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(47, 1, 1, mul, 0xd159e26b, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(48, 2, 0, mul, 0xd159e26b, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(49, 0, 0, mul, 0xd159e26b, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(50, 0, 1, mul, 0xd159e26b, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(51, 0, 2, mul, 0xd159e26b, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(52, 1, 0, mul, 0xd159e26b, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(53, 1, 1, mul, 0xd159e26b, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(54, 2, 0, mul, 0xd159e26b, 0x87654321, 0x0000000b)

    //Регистр x0
    TEST_RR_ZEROSRC1(55, mul, 0x00000000, 0x0000000b)
    TEST_RR_ZEROSRC2(56, mul, 0x00000000, 0x87654321)
    TEST_RR_ZEROSRC12(57, mul, 0x00000000)
    TEST_RR_ZERODEST(58, mul, 0x87654321, 0x0000000b)

    //Зависимые цепочки (конвейер)
    TEST_CASE(59, x14, 0xfedcba99, ("mul->mul"), li x1, 0x87654321; li x2, 0x0000000b; mul x3, x1, x2; mul x14, x3, x2)
    TEST_CASE(60, x14, 0x29dec6e2, ("mul->divu"), li x1, 0x87654321; li x2, 0x0000000b; li x4, 0x00000005; mul x3, x1, x2; divu x14, x3, x4)
    TEST_CASE(61, x14, 0x29dec6e0, ("divu->mul"), li x1, 0x87654321; li x2, 0x0000000b; li x4, 0x00000005; divu x3, x1, x4; mul x14, x3, x2)
    TEST_CASE(62, x14, 0x58bf258f, ("mul[addi,addi,add]"), li x1, 0x87654321; li x2, 0x0000000b; mul x3, x1, x2; addi x4, x1, 1; addi x4, x4, 2; add x14, x3, x4)
    TEST_CASE(63, x14, 0xd159e26b, ("mul->sw->lw"), la x5, md_buf; li x1, 0x87654321; li x2, 0x0000000b; mul x3, x1, x2; sw x3, 0(x5); lw x14, 0(x5))
    TEST_CASE(64, x14, 0x00000002, ("mul->bnez"), li x1, 0x87654321; li x2, 0x0000000b; li x14, 2; mul x3, x1, x2; bnez x3, 1f; li x14, 1; 1: nop)

    j pass
RVTEST_CODE_END

RVTEST_DATA_BEGIN
    .align 2
md_buf: .word 0
