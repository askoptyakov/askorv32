/*
 *****************************************************************************************
 * @file		start.S
 * @author		Alexander Koptyakov
 * @device		AskoRV32
 * @brief		Startup
 ******************************************************************************************
 */
 


	//.section .text
.text
.balign 16

.globl start

/* //Скрипт для проверки приостановки конвейера от конфликта данных инстр. lw
start:
	addi x2, x0, 5      //x2 = 5
	addi x3, x0, 12     //x3 = 12
	addi x7, x3, -9     //x7 = 12  -  9   = 3
	or   x4, x7, x2     //x4 = 3  OR  5   = 7
	and  x5, x3, x4     //x5 = 12 AND 7   = 4
	add  x5, x5, x4     //x5 = 4   +  7   = 11
	sw   x5, -12(x3)    //      dmem[0]  <- 11
	addi x7, x0, 5      //x7 = 5
	addi x9, x0, 6      //x9 = 6
	lw   x2, 0(x0)      //x2 -> dmem[0]   = 11
	add  x8, x2, x4     //x8 = 11  +  7   = 18
	sub  x9, x8, x3     //x9 = 18  -  12  = 6
	addi x2, x0, 56     //x2 = 56
	add  x3, x2, x9     //x3 = 56  +  6   = 62

.end
*/
/*
//Основной скрипт
start:
	addi x2, x0, 5      //x2 = 5
	addi x3, x0, 12     //x3 = 12
	addi x7, x3, -9     //x7 = 12  -  9   = 3
	or   x4, x7, x2     //x4 = 3  OR  5   = 7
	and  x5, x3, x4     //x5 = 12 AND 7   = 4
	add  x5, x5, x4     //x5 = 4   +  7   = 11
	beq  x5, x7, end    //pc = (11 == 3)? end : pc + 4    #Ложь
	slt  x4, x3, x4     //x4 = 12  <  7   = 0
	beq  x4, x0, around //pc = (0 == 0)? around : pc + 4  #Истина, переход к around
	addi x5, x0, 0      //!x5= 0   +  0   = 0             #Не выполняется
around:
	slt  x4, x7, x2     //x4 = 3   <  5   = 1
	add  x7, x4, x5     //x7 = 1   +  11  = 12
	sub  x7, x7, x2     //x7 = 12  -  5   = 7
	sw   x7, -12(x3)    //      dmem[0] <- 7
	lw   x2, 0(x0)      //x2 -> dmem[0]  = 7
	add  x9, x2, x5     //x9 = 7   +  11  = 18
	jal  x3, end        //pc = end, x3 = 0x44             #Переход к end
	addi x2, x0, 1      //!x2= 0   +  1   = 1
end:
	add  x2, x2, x9     //x2 = 7   +  18  = 25
	sw   x2, -64(x3)    //      dmem[4] <- 25
done:
	beq  x2, x2, done   //pc = (25 == 25)? done : pc + 4  #Истина, бесконечный цикл
*/
//Cкрипт для проверки команд slti,ori,andi,xor,xori,sll,slli,srl,srli,bne
start:
	addi x2, x0, 1		//x2 = 1
	addi x3, x0, 2		//x3 = 2
	addi x7, x0, 7		//x7 = 7
	addi x4, x0, 11		//x4 = 11
	addi x5, x0, 15		//x5 = 15
	add  x9, x2, x3     //x9 = 1 + 2 = 3
beq0:
	addi x2, x2, 1      //x2 = 1   +  1   = 2
	beq  x2, x3, beq0	//pc = (2 == 2)? beq0 : pc + 4    #1:первый проход; 0: второй проход
bne0:
	addi x2, x2, 2      //x2 = 5
	bne  x2, x7, bne0	//pc = (5 != 7)? bne0 : pc + 4    #1:первый проход; 0: второй проход
blt0:
	addi x2, x2, 2		//x2 = 9
	blt  x2, x4, blt0	//pc = (9 < 11)? blt0 : pc + 4    #1:первый проход; 0: второй проход
bge0:
	sub  x2, x2, x3		//x2 = 11  -  2   = 9
	bge  x2, x7, bge0	//pc = (9 >= 7)? bge0 : pc + 4   #1:первый/второй проход; 0: третий проход
bltu0:
	addi x2, x2, -3		//x2 = 5   -  3   = 2
	bltu x2, x9, bltu0	//pc = (2 < 3)? bltu0 : pc + 4    #1:первый проход; 0: второй проход
	addi x2, x2, -12    //x2 = -1  - 12   = -13
bgeu0:
	add   x2, x2, x7	//x2 = -13  +  7   = -6
	bgeu  x2, x7, bgeu0	//pc = (-6 >= 7)? bgeu0 : pc + 4   #1:первый/второй проход; 0: третий проход

	li   x2, 0xFFFFAAA  //x2 = 268 434 090
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
	bne  x9, x4, around //pc = (1 != 1)? around : pc + 4  #Ложь, нет перехода к around
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
	beq  x5, x7, end    //pc = (11 == 3)? end : pc + 4    #Ложь
	slt  x4, x3, x4     //x4 = 12  <  7   = 0
	beq  x4, x0, around //pc = (0 == 0)? around : pc + 4  #Истина, переход к around
	addi x5, x0, 0      //!x5= 0   +  0   = 0             #Не выполняется
around:
	slt  x4, x7, x2     //x4 = 3   <  5   = 1
	add  x7, x4, x5     //x7 = 1   +  11  = 12
	sub  x7, x7, x2     //x7 = 12  -  5   = 7
	sw   x7, -12(x3)    //      dmem[0] <- 7
	lw   x2, 0(x0)      //x2 -> dmem[0]  = 7
	add  x9, x2, x5     //x9 = 7   +  11  = 18
	jal  x3, end        //pc = end, x3 = 0x44             #Переход к end
	addi x2, x0, 1      //!x2= 0   +  1   = 1
end:
	add  x2, x2, x9     //x2 = 7   +  18  = 25
	sw   x2, -64(x3)    //      dmem[4] <- 25
done:
	beq  x2, x2, done   //pc = (25 == 25)? done : pc + 4  #Истина, бесконечный цикл
.end
