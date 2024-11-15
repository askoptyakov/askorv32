/*
 ******************************************************************************
 * @file        periphery.h
 * @author		Alexander Koptyakov
 * @device		AskoRV32
 * @brief       ������������ ���� ������� � ������������ �����������.
 *****************************************************************************************
 */

#ifndef __PERIPHERY_H
#define __PERIPHERY_H

/* ������������ ���������� */
#include <stdint.h>

/* ������������ */
#define __INLINE				__attribute__((always_inline)) inline
#define __I                     volatile const	//������ ��� ������
#define __O                     volatile        //������ ��� ������
#define __IO                    volatile        //������ � ������

/* ����� ������ ������������ ��������� */
#define   GPIO_BASE		(0x11000000U)
#define TM1638_BASE		(0x12000000U)

/* ���������� ������� ��������� */
typedef struct
{
  __IO uint32_t MODE;  	//0x00: ������� ������ ������ ����/����� �����
  __IO uint32_t  OUT;   //0x04: ������� �������� ������ �����
  __IO uint32_t   IN;  	//0x08: ������� ������� ������ �����
} GPIO_TypeDef;

typedef struct
{
  __IO uint32_t SEGS;  	//0x00: ������� ������ �� �������������� ���������� ��. �����(HEX)
  __IO uint32_t LEDS;   //0x04: ������� ������ �� ����������� ��. �����
  __IO uint32_t KEYS;  	//0x08: ������� ������ ��������� ������ ��. �����
} TM1638_TypeDef;

/* ���������� ��������� �� ��������� ������ */
#define GPIO 	((GPIO_TypeDef*) 	GPIO_BASE)
#define TM1638 	((TM1638_TypeDef*) 	TM1638_BASE)

#endif /* __PERIPHERY_H */
