#include "main.h"
#include "gpio.h"
#include "tm1638.h"
#include "tim.h"

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
	STIM_Init();
	c = 1;
	GPIO_PinsMode(0xFFFFFFFF); //Все порты на выход

	STIM_STATE(TIM_ENABLE);

	unsigned int count = 0;

	while(1) {

		//#Считывание значения таймера
		count = STIM_GET_COUNT();

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

