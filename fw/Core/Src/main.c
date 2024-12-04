#include "main.h"
#include "gpio.h"
#include "tm1638.h"

#define STIM_Prescaler   	0x13000000
#define STIM_CounterMode 	0x13000004
#define STIM_CounterPeriod  0x13000008
#define STIM_Pulse			0x1300000c
#define STIM_OutCount	  	0x13000010

#define READ_STIM(dir) (*(volatile unsigned *)dir)
#define WRITE_STIM(dir, value) { (*(volatile unsigned *)dir) = (value); }

/*Прототипы функций*/
unsigned int dig_transform(unsigned int digit);

//unsigned int globalvar = 5;
unsigned int c;
unsigned int keys = 0;
unsigned int tn_keys = 0;

int main(void) {
	//#1 Инициализация периферийных устройства
	GPIO_Init();
	TM1638_Init();
	c = 1;
	GPIO_PinsMode(0xFFFFFFFF); //Все порты на выход

	//Инициализация переменных простого таймера
	unsigned int count = 0;
	unsigned int prescaler = 1000000;
	WRITE_STIM(STIM_Prescaler, prescaler);
	WRITE_STIM(STIM_CounterMode, 5); //0101 - DOWN
	WRITE_STIM(STIM_CounterPeriod, 100);

	while(1) {
		//#Считывание значения таймера
		count = READ_STIM(STIM_OutCount);

		if(count == 50) {
			WRITE_STIM(STIM_CounterPeriod, 75);
		}
		//c = c + 1;
		//#Светодиоды tangnano
		//GPIO_WritePins(~c);
		//GPIO_WritePins(count);

		//#Светодиоды tm1638
		keys = TM1638_ReadKeys();
		TM1638_WriteLeds(keys);

		//#Сегментный индикатор tm1638
		//TM1638_WriteSegs(c);
		TM1638_WriteSegs(dig_transform(count));
		if(keys == 1) {
			WRITE_STIM(STIM_CounterMode, 13); //0101 - DOWN
		}
		else {
			WRITE_STIM(STIM_CounterMode, 5); //0101 - DOWN
		}
/*
		if(keys == 0) {
			WRITE_STIM(STIM_CounterMode, 0); //OFF
		}
		if(keys == 1) {
			WRITE_STIM(STIM_CounterMode, 12); //1100 -UP
		}
		if(keys == 2) {
			WRITE_STIM(STIM_CounterMode, 13); //1101 - DOWN
		}
		if(keys == 3) {
			WRITE_STIM(STIM_CounterMode, 14);//1110 - UP/DOWN
		}
*/
		//for(int i = 0; i<100000; i++);
	}
}

unsigned int dig_transform(unsigned int digit) {
	unsigned int d_out = 0;
	unsigned int d_in  = digit;
	d_in = d_in % 100000000;
	d_out = d_out | ((d_in / 10000000) << 28);
	d_in = d_in % 10000000;
	d_out = d_out | ((d_in / 1000000)  << 24);
	d_in = d_in % 1000000;
	d_out = d_out | ((d_in / 100000)   << 20);
	d_in = d_in % 100000;
	d_out = d_out | ((d_in / 10000)    << 16);
	d_in = d_in % 10000;
	d_out = d_out | ((d_in / 1000)     << 12);
	d_in = d_in % 1000;
	d_out = d_out | ((d_in / 100)      <<  8);
	d_in = d_in % 100;
	d_out = d_out | ((d_in / 10)       <<  4);
	d_out = d_out |  (d_in % 10);
	return d_out;
}

