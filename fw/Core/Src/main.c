#include "main.h"

#define GPIO_LEDs   0x11000000
#define TM_SEGMETs  0x12000000
#define TM_LEDs		0x12000004
#define TM_KEYs		0x12000008

#define WRITE_REG(dir, value) { (*(volatile unsigned *)dir) = (value); }
#define READ_GPIO(dir) (*(volatile unsigned *)dir)

/*Прототипы функций*/
unsigned int dig_transform(unsigned int digit);

//unsigned int globalvar = 5;
unsigned int c;
unsigned int keys = 0;

int main(void) {
	c = 1;
	//unsigned int d;
	while(1) {
		c = c + 1;
		//#Светодиоды tangnano
		WRITE_REG(GPIO_LEDs,  ~c);
		//#Светодиоды tm1638
		keys = READ_GPIO(TM_KEYs);
		WRITE_REG(TM_LEDs, keys);
		//WRITE_REG(TM_LEDs,  globalvar);
		//#Сегментный индикатор tm1638
		//WRITE_REG(TM_SEGMETs, c);
		WRITE_REG(TM_SEGMETs, dig_transform(c));
		for(int i = 0; i<100000; i++);
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

