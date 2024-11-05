#include "main.h"

#define GPIO_LEDs   0x11000000

#define WRITE_GPIO(dir, value) { (*(volatile unsigned *)dir) = (value); }

int globalvar = 5;
int c;

int main(void) {
	c = 1;
	while(1) {
		globalvar = globalvar + c;
		//glob = glob + globalvar + globalvar1;
		WRITE_GPIO(GPIO_LEDs, ~globalvar);
		for(int i = 0; i<500000; i++);
	}
}
