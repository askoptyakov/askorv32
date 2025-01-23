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
#define   STIM_BASE		(0x13000000U)

/* ���������� �������� ��������� */
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

typedef struct
{
  __IO uint32_t PR;    				//0x00: ������� ������������ ��������� ������� ������� (PRESCALER)
  union {
	  __IO uint32_t CR;  			//0x04: ������� ���������� �������� (CONTROL REG)
	  struct {
		  uint32_t CR_CM	: 2;	// counter mode - ������ ���������� �����
		  uint32_t CR_ARP 	: 1;    // autoReloadPreload
		  uint32_t CR_EN  	: 1;	// enable - ��������� �������
	  };
  };
  __IO uint32_t PER;   	  			//0x08: ������� ������ �������� ������������ ������� (PERIOD)
  __IO uint32_t PUL;         		//0x0C: ������� �������� ��������� (PULSE)
  __IO uint32_t CNT;  	      		//0x10: ������� �������� �������� �������� ������� (COUNT)
} STIM_TypeDef;

/* ��������� ������� ��� ������������� */
#define STIM_PRESCALER 				1000000;
#define STIM_PERIOD 				100;
#define STIM_COUNTER_MODE 			STIM_COUNTER_MODE_DOWN;
#define STIM_AUTO_RELOAD_PRELOAD 	1;

/* ���������� ���������� �� ��������� ������ */
#define GPIO 	((GPIO_TypeDef*) 	GPIO_BASE)
#define TM1638 	((TM1638_TypeDef*) 	TM1638_BASE)
#define STIM 	((STIM_TypeDef*) 	STIM_BASE)

#endif /* __PERIPHERY_H */
