#include "main.h"
#include "gpio.h"
#include "tm1638.h"
#include "tim.h"

#define READ_STIM(dir) (*(volatile unsigned *)dir)
#define WRITE_STIM(dir, value) { (*(volatile unsigned *)dir) = (value); }

#define ADC_V_Enable  	0x14000000
#define ADC_V_Data 	    0x14000004

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

	int i = 0;
	uint32_t buf = 0;
	uint32_t res = 0.0f;
	WRITE_STIM(ADC_V_Enable, 1); //вкл ацп

	float a = 0.222f;
	float b = 0.383f;

	while(1) {

		//#Считывание значения таймера
		//count = READ_STIM(ADC_V_Data);

		//#Считывание значения ацп
		buf += READ_STIM(ADC_V_Data);
		i++;
		if(i == 200) { //усреднение
			//ед.ацп -> Вольт
			res = ((buf/i) * 222) / 1000; // почему-то не работает умножение с float
			buf = 0;
			i = 0;
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
		TM1638_WriteSegs(dig_transform(res));


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

