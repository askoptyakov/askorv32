/*
 ******************************************************************************
 * @file        tm1638.�
 * @author		Alexander Koptyakov
 * @device		AskoRV32
 * @brief       ������� ������ ����� � ������������ TM1638
 *****************************************************************************************
 */

#include "tm1638.h"

void TM1638_Init(void) {
	TM1638->SEGS = 0;
	TM1638->LEDS = 0;
	TM1638->KEYS = 0; //����� �� ���������� ����
}
