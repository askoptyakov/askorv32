/*
 *****************************************************************************************
 * @file		start.S
 * @author		Alexander Koptyakov
 * @device		AskoRV32
 * @brief		������������ ��� ������������� ����������
 *****************************************************************************************
 */

.section .text
.balign 16

.globl start
.global main

start:
	.option push
	.option norelax
	la gp, __global_pointer$
	.option pop
  	la sp, _estack

	#������������� ������������ ����� �������� ����������
	/*
	addi x1, zero, 0
	//addi x2, zero, 0 //sp(stack pointer)
	//addi x3, zero, 0 //gp(global pointer)
	addi x4, zero, 0
	addi x5, zero, 0
	addi x6, zero, 0
	addi x7, zero, 0
	addi x8, zero, 0
	addi x9, zero, 0
	addi x10, zero, 0
	addi x11, zero, 0
	addi x12, zero, 0
	addi x13, zero, 0
	addi x14, zero, 0
	addi x15, zero, 0
	addi x16, zero, 0
	addi x17, zero, 0
	addi x18, zero, 0
	addi x19, zero, 0
	addi x20, zero, 0
	addi x21, zero, 0
	addi x22, zero, 0
	addi x23, zero, 0
	addi x24, zero, 0
	addi x25, zero, 0
	addi x26, zero, 0
	addi x27, zero, 0
	addi x28, zero, 0
	addi x29, zero, 0
	addi x30, zero, 0
	addi x31, zero, 0
	*/

# ������������� ������ bss �������� ����������
	la a0, _sbss
	la a1, _ebss
	bge a0, a1, end_init_bss
loop_init_bss:
	sw zero, 0(a0)
	addi a0, a0, 4
	blt a0, a1, loop_init_bss
end_init_bss:

# ������� � ������� main
	call main

.end

/* //��� ������ ���������� ����������
start:
	la   x2, 0xFFFFAAA  //x2 = 268�434�090
	jal	 funct0         //pc = funct0, ra = pc + 4      #������� � funct0
	addi x3, x0, 518	//x3 = 518 						#������ ���������� ��� ��������
	addi x2, x0, 128	//x2 = 128
	sb	 x2, 2(x0)		//dmem[2] <- 128
	li   x3, 32768  	//x3 = 32768
	lb	 x7, 2(x0)		//x7 -> dmem[2]  = 4�294�967�168
	lbu	 x4, 2(x0)		//x4 -> dmem[2]  = 128
	sh	 x3, 7(x0)		//dmem[7] <- 32768
	lh	 x7, 7(x0)		//x7 -> dmem[7]  = 4�294�934�528
	lhu	 x4, 7(x0)		//x4 -> dmem[7]  = 32768

	addi x2, x0, 1		//x2 = 1
	addi x3, x0, 2		//x3 = 2
	addi x7, x0, 7		//x7 = 7
	addi x9, x0, -5		//x9 = -5
	slt  x4, x9, x3		//x4 = -5 < 2 = 1
	sltu x4, x9, x3		//x5 = -5 < 2 = 0
	slti x4, x9, -2     //x4 = -5 < -2 = 1
	sltiu x4, x9, -2    //x5 = -5 < -2 = 1
	slti x4, x9, 2      //x4 = -5 < 2 = 1
	sltiu x4, x9, 2     //x4 = -5 < 2 = 0
	addi x4, x0, 11		//x4 = 11
	addi x5, x0, 15		//x5 = 15
	add  x9, x2, x3     //x9 = 1 + 2 = 3
beq0:
	addi x2, x2, 1      //x2 = 1   +  1   = 2
	beq  x2, x3, beq0	//pc = (2 == 2)? beq0 : pc + 4    #1:������ ������; 0: ������ ������
bne0:
	addi x2, x2, 2      //x2 = 5
	bne  x2, x7, bne0	//pc = (5 != 7)? bne0 : pc + 4    #1:������ ������; 0: ������ ������
blt0:
	addi x2, x2, 2		//x2 = 9
	blt  x2, x4, blt0	//pc = (9 < 11)? blt0 : pc + 4    #1:������ ������; 0: ������ ������
bge0:
	sub  x2, x2, x3		//x2 = 11  -  2   = 9
	bge  x2, x7, bge0	//pc = (9 >= 7)? bge0 : pc + 4   #1:������/������ ������; 0: ������ ������
bltu0:
	addi x2, x2, -3		//x2 = 5   -  3   = 2
	bltu x2, x9, bltu0	//pc = (2 < 3)? bltu0 : pc + 4    #1:������ ������; 0: ������ ������
	addi x2, x2, -12    //x2 = -1  - 12   = -13
bgeu0:
	add   x2, x2, x7	//x2 = -13  +  7   = -6
	bgeu  x2, x7, bgeu0	//pc = (-6 >= 7)? bgeu0 : pc + 4   #1:������/������ ������; 0: ������ ������

	li   x2, 0xFFFFAAA  //x2 = 268�434�090
	addi x2, x0, 5      //x2 = 5
	addi x3, x0, -17    //x3 = -17
	srai x7, x3, 2		//x7 = -17 >>> 2  =-5
	addi x2, x2, -4     //x2 = 5   -  4   = 1
	sra  x3, x7, x2     //x3 = -5  >>> 1  =-3
	addi x2, x3, 8      //x2 = -3  +  8   = 5
	addi x3, x0, 12     //x3 = 12
	addi x7, x3, -9     //x7 = 12  -  9   = 3
	slti x4, x2, 33		//x4 = 5   <  33  = 1
	ori  x5, x4, 8		//x5 = 1  OR  8   = 9
	andi x9, x5, 7		//x9 = 9  AND 7   = 1
	bne  x9, x4, around //pc = (1 != 1)? around : pc + 4  #����, ��� �������� � around
	xor  x2, x9, x5     //x2 = 1  XOR 9   = 8
	xori x3, x2, 12     //x3 = 8  XOR 12  = 4
	sll  x7, x3, x7     //x7 = 4  <<  3   = 32
	slli x4, x7, 1      //x4 = 32 <<  1   = 64
	srl  x2, x7, x9     //x2 = 32 >>  1   = 16
	srli x2, x2, 2      //x2 = 16 >>  2   = 4
	addi x3, x2, 8		//x3 = 4   +  8   = 12
	sub  x7, x3, x5     //x7 = 12  -  9   = 3
	addi x2, x7, 2      //x2 = 3   +  2   = 5
	or   x4, x7, x2     //x4 = 3  OR  5   = 7
	and  x5, x3, x4     //x5 = 12 AND 7   = 4
	add  x5, x5, x4     //x5 = 4   +  7   = 11
	beq  x5, x7, end    //pc = (11 == 3)? end : pc + 4    #����
	slt  x4, x3, x4     //x4 = 12  <  7   = 0
	beq  x4, x0, around //pc = (0 == 0)? around : pc + 4  #������, ������� � around
	addi x5, x0, 0      //!x5= 0   +  0   = 0             #�� �����������
around:
	slt  x4, x7, x2     //x4 = 3   <  5   = 1
	add  x7, x4, x5     //x7 = 1   +  11  = 12
	sub  x7, x7, x2     //x7 = 12  -  5   = 7
	sw   x7, -12(x3)    //      dmem[0] <- 7
	lw   x2, 0(x0)      //x2 -> dmem[0]  = 7
	add  x9, x2, x5     //x9 = 7   +  11  = 18
	jal  x3, end        //pc = end, x3 = 0x44             #������� � end
	addi x2, x0, 1      //!x2= 0   +  1   = 1
end:
	add  x2, x2, x9     //x2 = 7   +  18  = 25
	sw   x2, -64(x3)    //      dmem[4] <- 25

	//la   x7, 9000
	//sw	 x3, 0(x7)
	//lw   x4, 0(x7)
done:
	beq  x2, x2, done   //pc = (25 == 25)? done : pc + 4  #������, ����������� ����
funct0:
	addi x2, x2, 1
	jalr x1, x1, 4
.end
*/
