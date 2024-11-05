#include "main.h"

#define GPIO_LEDs   0x11000000

#define WRITE_GPIO(dir, value) { (*(volatile unsigned *)dir) = (value); }

//int globalvar = 5;
//int globalvar1 = 105;


int main(void) {
	unsigned int c;
	while(1) {
		c = c + 1;
		WRITE_GPIO(GPIO_LEDs, ~c);
		//WRITE_GPIO(GPIO_LEDs, globalvar);
		for(int i = 0; i<100000; i++);
		//WRITE_GPIO(GPIO_LEDs, globalvar1);
	}
}
