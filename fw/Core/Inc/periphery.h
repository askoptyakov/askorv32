/*
 ******************************************************************************
 * @file        periphery.h
 * @author		Alexander Koptyakov
 * @device		AskoRV32
 * @brief       Общие определения для драйверов периферии. Типы регистров и биты устройств - в
 *              заголовках драйверов (gpio.h, uart.h, tim.h, tm1638.h, clint.h, plic.h); адреса,
 *              указатели и настройки собранной ПЛИС - в soc.h (создаёт конфигуратор ПЛИС).
 *****************************************************************************************
 */

#ifndef __PERIPHERY_H
#define __PERIPHERY_H

/* Подключаемые библиотеки */
#include <stdint.h>
#include "soc.h"	//Создаёт конфигуратор ПЛИС: SYSCLK_HZ, адреса и указатели устройств, источники PLIC, имена выводов

/* Терминология */
#define __INLINE				__attribute__((always_inline)) inline
#define __I                     volatile const	//Только для чтения
#define __O                     volatile        //Только для записи
#define __IO                    volatile        //Чтение и запись

#endif /* __PERIPHERY_H */
