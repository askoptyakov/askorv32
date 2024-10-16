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

.end
