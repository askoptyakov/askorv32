/*
 ******************************************************************************
 * @file        spiflash.h
 * @author      Alexander Koptyakov
 * @device      AskoRV32
 * @brief       Драйвер контроллера внешней SPI-флеш (spiflash_top, hw/src/periph/spiflash).
 *
 *  Контроллер делает две вещи:
 *  1) после сброса копирует программу из флеш в IMEM/DMEM (загрузчик; итог - SPIFLASH_BootStatus);
 *  2) обменивается с флеш байтами по командам программы - этим драйвером: чтение, запись страниц,
 *     стирание, ID, состояние. Так хранятся параметры в свободной области флеш.
 *
 *  Карта флеш (soc.h, настройки блока SPIFLASH в конфигураторе):
 *     SPIFLASH_BOOT_ADDR .. + SPIFLASH_BOOT_SIZE - образ программы (его пишет openFPGALoader);
 *     SPIFLASH_USER_ADDR .. + SPIFLASH_USER_SIZE - свободная область для данных программы.
 *  Если флеш хранит и конфигурацию ПЛИС (режим MSPI, SPIFLASH_FPGA_CONFIG = 1), битовый поток
 *  лежит с адреса 0, а образ программы - выше него. Запись и стирание ниже SPIFLASH_USER_ADDR
 *  (конфигурация ПЛИС и образ программы) драйвер не выполняет (SPIFLASH_ERR_PROTECT), пока
 *  SPIFLASH_PROTECT_BOOT = 1.
 *
 *  Флеш NOR: запись только сбрасывает биты (1 -> 0), вернуть 1 можно лишь стиранием сектора
 *  (4 кБайт, 0xFF). Порядок обновления данных: SPIFLASH_EraseSector, затем SPIFLASH_Write.
 *  Запись страницы длится до ~3 мс, стирание сектора - до ~0.3 с: функции ждут окончания.
 *
 *  Пример:
 *    SPIFLASH_InitDefault();
 *    uint32_t id = SPIFLASH_ReadID();                     //0x856016 - PUYA P25Q32U (Tang Nano 9K)
 *    SPIFLASH_EraseSector(SPIFLASH_USER_ADDR);
 *    SPIFLASH_Write(SPIFLASH_USER_ADDR, &param, sizeof param);
 *    SPIFLASH_Read(SPIFLASH_USER_ADDR, &param, sizeof param);
 *
 *  Функции не рассчитаны на вызов из прерываний одновременно с основной программой.
 *****************************************************************************************
 */

#ifndef __SPIFLASH_H
#define __SPIFLASH_H

#include "periphery.h"

/* Регистры контроллера */
typedef struct
{
  __IO uint32_t CTRL;		//0x00: [0] CS - удерживать CS (кадр из нескольких обменов), [1] RDAUTO - чтение DATA запускает обмен 4 байтами
  __IO uint32_t STAT;		//0x04: [0] BUSY - идёт обмен или пауза CS, [1] OVR - запуск при BUSY (обмен пропущен), сброс записью 1
  __IO uint32_t DIV;		//0x08: SCK = SYSCLK_HZ / (2 * (DIV + 1))
  __IO uint32_t DATA;		//0x0C: Запись байта/полуслова/слова - обмен этими байтами (младший первым); чтение - принятые байты на тех же местах
  __I  uint32_t BOOT;		//0x10: Загрузчик: [2:0] итог (SPIFLASH_BootResult), [31:16] загружено слов
  uint32_t      RESERVED[59];
  __IO uint32_t WIN[64];	//0x100..0x1FC: окно DATA - пакетная запись/чтение (memcpy, отладчик)
} SPIFLASH_TypeDef;

/* Биты регистров */
#define SPIFLASH_CTRL_CS			(1U << 0)
#define SPIFLASH_CTRL_RDAUTO		(1U << 1)
#define SPIFLASH_STAT_BUSY			(1U << 0)
#define SPIFLASH_STAT_OVR			(1U << 1)
#define SPIFLASH_BOOT_RESULT_Msk	(7U)
#define SPIFLASH_BOOT_WORDS_Pos		16U

/* Итог загрузки программы из флеш (регистр BOOT) */
typedef enum
{
  SPIFLASH_BOOT_OFF      = 0,		//Загрузчик выключен (в конфигураторе)
  SPIFLASH_BOOT_OK       = 1,		//Программа загружена из флеш
  SPIFLASH_BOOT_NOIMAGE  = 2,		//Образа нет - работает программа из битового потока ПЛИС
  SPIFLASH_BOOT_CHECKSUM = 3,		//Образ испорчен (контрольная сумма) - память не тронута
  SPIFLASH_BOOT_FORMAT   = 4		//Неверная разметка образа - память не тронута
} SPIFLASH_BootResult;

/* Команды флеш (общие для 25-й серии: PUYA P25Q, Winbond W25Q, GigaDevice GD25Q...) */
#define SPIFLASH_CMD_READ			0x03U
#define SPIFLASH_CMD_FAST_READ		0x0BU
#define SPIFLASH_CMD_PAGE_PROGRAM	0x02U
#define SPIFLASH_CMD_SECTOR_ERASE	0x20U		//4 кБайт
#define SPIFLASH_CMD_BLOCK_ERASE	0xD8U		//64 кБайт
#define SPIFLASH_CMD_CHIP_ERASE		0xC7U
#define SPIFLASH_CMD_WRITE_ENABLE	0x06U
#define SPIFLASH_CMD_WRITE_DISABLE	0x04U
#define SPIFLASH_CMD_READ_STATUS	0x05U
#define SPIFLASH_CMD_JEDEC_ID		0x9FU
#define SPIFLASH_CMD_POWER_DOWN		0xB9U
#define SPIFLASH_CMD_RELEASE_PD		0xABU
#define SPIFLASH_SR_WIP				(1U << 0)	//Регистр состояния: идёт запись/стирание
#define SPIFLASH_SR_WEL				(1U << 1)	//Запись разрешена

#define SPIFLASH_PAGE_SIZE			256U
#define SPIFLASH_SECTOR_SIZE		4096U
#define SPIFLASH_BLOCK_SIZE			65536U

#if SPIFLASH_PRESENT	//Блок есть в ПЛИС (soc.h)

#ifndef SPIFLASH_PROTECT_BOOT
#define SPIFLASH_PROTECT_BOOT		1		//1 - запись и стирание ниже SPIFLASH_USER_ADDR запрещены
#endif

typedef enum
{
  SPIFLASH_OK = 0,
  SPIFLASH_ERR_ADDR,		//Вне флеш (SPIFLASH_SIZE)
  SPIFLASH_ERR_PROTECT,		//Ниже SPIFLASH_USER_ADDR: конфигурация ПЛИС, образ программы (SPIFLASH_PROTECT_BOOT)
  SPIFLASH_ERR_WEL,			//Флеш не разрешила запись: нет микросхемы или защита записи
  SPIFLASH_ERR_TIMEOUT		//Запись/стирание не закончились за отведённое время
} SPIFLASH_Status;

/* --- Нижний уровень: кадры и обмен --- */
__INLINE void SPIFLASH_WaitIdle(void) { while (SPIFLASH->STAT & SPIFLASH_STAT_BUSY) ; }
/* Кадр из нескольких обменов: CS удерживается до SPIFLASH_Deselect (поднимется после текущего обмена).
   Без Select каждый обмен SPIFLASH_Xfer* - отдельный кадр */
__INLINE void SPIFLASH_Select(void)   { SPIFLASH_WaitIdle(); SPIFLASH->CTRL = SPIFLASH_CTRL_CS; }
__INLINE void SPIFLASH_Deselect(void) { SPIFLASH->CTRL = 0U; }
/* Обмен 1, 2 или 4 байтами: передаются младшие байты data (младший первым), возвращаются принятые на тех же местах */
__INLINE uint32_t SPIFLASH_Xfer8(uint32_t data) {
	SPIFLASH_WaitIdle(); *(__IO uint8_t*)&SPIFLASH->DATA = (uint8_t)data;
	SPIFLASH_WaitIdle(); return SPIFLASH->DATA & 0xFFU;
}
__INLINE uint32_t SPIFLASH_Xfer16(uint32_t data) {
	SPIFLASH_WaitIdle(); *(__IO uint16_t*)&SPIFLASH->DATA = (uint16_t)data;
	SPIFLASH_WaitIdle(); return SPIFLASH->DATA & 0xFFFFU;
}
__INLINE uint32_t SPIFLASH_Xfer32(uint32_t data) {
	SPIFLASH_WaitIdle(); SPIFLASH->DATA = data;
	SPIFLASH_WaitIdle(); return SPIFLASH->DATA;
}
/* Команда и 24-битный адрес одним словом (байт команды передаётся первым, адрес - старшим байтом вперёд) */
__INLINE uint32_t SPIFLASH_CmdAddr(uint32_t cmd, uint32_t addr) {
	return (cmd & 0xFFU) | ((addr >> 8) & 0xFF00U) | ((addr << 8) & 0xFF0000U) | ((addr << 24) & 0xFF000000U);
}

/* --- Флеш --- */
/* Настройка: делитель SCK (SPIFLASH_SCK = SYSCLK_HZ / (2 * (div + 1))), выход флеш из глубокого сна */
void SPIFLASH_Init(uint32_t div);
#define SPIFLASH_InitDefault()	SPIFLASH_Init(SPIFLASH_DIV_DEFAULT)
uint32_t SPIFLASH_ReadID(void);							//JEDEC ID: (производитель << 16) | (тип << 8) | объём
uint32_t SPIFLASH_ReadStatus(void);						//Регистр состояния 1 (SPIFLASH_SR_WIP, SPIFLASH_SR_WEL)
SPIFLASH_Status SPIFLASH_WaitReady(uint32_t timeout_ms);	//Ждать конца записи/стирания
SPIFLASH_Status SPIFLASH_Read(uint32_t addr, void *buf, uint32_t len);
/* Запись (программирование) любой длины с любого адреса: страницы делятся сами. Стирания нет - область должна
   быть стёрта (0xFF), иначе биты только сбросятся */
SPIFLASH_Status SPIFLASH_Write(uint32_t addr, const void *buf, uint32_t len);
SPIFLASH_Status SPIFLASH_EraseSector(uint32_t addr);		//4 кБайт, содержащих addr
SPIFLASH_Status SPIFLASH_EraseBlock(uint32_t addr);			//64 кБайт, содержащих addr
SPIFLASH_Status SPIFLASH_Erase(uint32_t addr, uint32_t len);	//Все секторы, задетые областью
void SPIFLASH_PowerDown(void);								//Глубокий сон (ток ~1 мкА); загрузчик будит флеш сам
void SPIFLASH_WakeUp(void);

/* --- Загрузчик --- */
__INLINE SPIFLASH_BootResult SPIFLASH_BootStatus(void) { return (SPIFLASH_BootResult)(SPIFLASH->BOOT & SPIFLASH_BOOT_RESULT_Msk); }
__INLINE uint32_t SPIFLASH_BootWords(void) { return SPIFLASH->BOOT >> SPIFLASH_BOOT_WORDS_Pos; }

#endif /* SPIFLASH_PRESENT */
#endif /* __SPIFLASH_H */
