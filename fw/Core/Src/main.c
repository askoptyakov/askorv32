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
unsigned int settingOfDuty(unsigned int *duty);
//unsigned int globalvar = 5;
unsigned int duty;
unsigned int dutyOld;
unsigned int option;
unsigned int keys = 0;
unsigned int tn_keys = 0;
uint8_t flagOfStep = 0;
uint8_t flagOfOption = 0;

int main(void)
{
	//#1 Инициализация периферийных устройства
	GPIO_Init();
	TM1638_Init();
	STIM_Init();
	duty = 50;
	dutyOld = 0;
	option = 0;
	unsigned int frequency = 10000;
	unsigned int frequencyOld = 0;
	//GPIO_PinsMode(0xFFFFFFFF); //Все порты на выход
	STIM_SET_PERIOD(100);
	STIM_STATE(TIM_ENABLE);
	GPIO_WritePin(GPIO_GMB_DRE_G1, GPIO_PIN_SET);
	GPIO_WritePin(GPIO_GMB_DRE_G2, GPIO_PIN_SET);

	int i = 0;
	uint32_t buf = 0;
	uint32_t res = 0.0f;
	WRITE_STIM(ADC_V_Enable, 1); //вкл ацп

	unsigned int count = 0;

	while(1)
	{

		//#Считывание значения ацп
		buf += READ_STIM(ADC_V_Data);
		i++;
		if(i == 200) { //усреднение
			//ед.ацп -> Вольт
			res = ((buf/i) * 222) / 1000; // почему-то не работает умножение с float
			buf = 0;
			i = 0;
		}

		//TM1638_WriteSegs(dig_transform(100-/*settingOfDuty(&duty)*/10));
		TM1638_WriteSegs(dig_transform(res));
		STIM_STATE(TIM_ENABLE);
		STIM_SET_PULSE(/*duty*/10);
	}
}

unsigned int settingOfDuty(unsigned int *duty)
{
	TM1638_WriteLeds(255);

	if(TM1638_ReadKey(TM1638_KEY0))
	{
		if (!flagOfStep && *duty < 100)
		{
			(*duty)++;
			flagOfStep = 1;
		}
	}
	else if (TM1638_ReadKey(TM1638_KEY1))
	{
		if (!flagOfStep && *duty > 0)
		{
			(*duty)--;
			flagOfStep = 1;
		}
	}
	else if (TM1638_ReadKey(TM1638_KEY2))
	{
		if (!flagOfStep && *duty <= 90)
		{
			(*duty)+=10;
			flagOfStep = 1;
		}
	}
	else if (TM1638_ReadKey(TM1638_KEY3))
	{
		if (!flagOfStep && *duty >= 10)
		{
			(*duty)-=10;
			flagOfStep = 1;
		}
	}
	else
		flagOfStep = 0;

	return *duty;
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

