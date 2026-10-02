/*
 ******************************************************************************
 * @file        spiflash.c
 * @author      Alexander Koptyakov
 * @device      AskoRV32
 * @brief       Драйвер внешней SPI-флеш: чтение, запись страниц, стирание, ID, состояние
 *****************************************************************************************
 */

#include "spiflash.h"

#if SPIFLASH_PRESENT

#include "core_riscv.h"

/* Предельные времена операций, мс (P25Q32U: страница до 3 мс, сектор до 0.3 с, блок до 2 с) */
#define T_PAGE_MS		10U
#define T_SECTOR_MS		500U
#define T_BLOCK_MS		3000U

void SPIFLASH_Init(uint32_t div) {
	SPIFLASH_WaitIdle();
	SPIFLASH->CTRL = 0U;
	SPIFLASH->DIV = div;
	SPIFLASH->STAT = SPIFLASH_STAT_OVR;
	SPIFLASH_WakeUp();
}

uint32_t SPIFLASH_ReadID(void) {
	uint32_t r = SPIFLASH_Xfer32(SPIFLASH_CMD_JEDEC_ID);		//Байты 1..3 - производитель, тип, объём
	return ((r >> 8) & 0xFFU) << 16 | ((r >> 16) & 0xFFU) << 8 | (r >> 24);
}

uint32_t SPIFLASH_ReadStatus(void) {
	return SPIFLASH_Xfer16(SPIFLASH_CMD_READ_STATUS) >> 8;		//Байт 1 - ответ на команду
}

SPIFLASH_Status SPIFLASH_WaitReady(uint32_t timeout_ms) {
	uint64_t end = CORE_GetCycles() + (uint64_t)timeout_ms * (SYSCLK_HZ / 1000U);
	while (SPIFLASH_ReadStatus() & SPIFLASH_SR_WIP)
		if (CORE_GetCycles() > end) return SPIFLASH_ERR_TIMEOUT;
	return SPIFLASH_OK;
}

/* Проверка области: внутри флеш; для записи и стирания - вне образа программы */
static SPIFLASH_Status check(uint32_t addr, uint32_t len, int modify) {
	if (addr >= SPIFLASH_SIZE || len > SPIFLASH_SIZE - addr) return SPIFLASH_ERR_ADDR;
#if SPIFLASH_PROTECT_BOOT
	if (modify && addr < SPIFLASH_USER_ADDR)					//Конфигурация ПЛИС и образ программы
		return SPIFLASH_ERR_PROTECT;
#else
	(void)modify;
#endif
	return SPIFLASH_OK;
}

static SPIFLASH_Status write_enable(void) {
	SPIFLASH_Xfer8(SPIFLASH_CMD_WRITE_ENABLE);
	return (SPIFLASH_ReadStatus() & SPIFLASH_SR_WEL) ? SPIFLASH_OK : SPIFLASH_ERR_WEL;
}

/* Чтение: кадр с автозапуском - каждое чтение DATA отдаёт 4 байта и запускает обмен следующими */
SPIFLASH_Status SPIFLASH_Read(uint32_t addr, void *buf, uint32_t len) {
	uint8_t *p = (uint8_t*)buf;
	SPIFLASH_Status st = check(addr, len, 0);
	if (st != SPIFLASH_OK || len == 0U) return st;
	SPIFLASH_WaitIdle();
	SPIFLASH->CTRL = SPIFLASH_CTRL_CS | SPIFLASH_CTRL_RDAUTO;
	SPIFLASH->DATA = SPIFLASH_CmdAddr(SPIFLASH_CMD_READ, addr);
	SPIFLASH_WaitIdle();
	(void)SPIFLASH->DATA;										//Ответ на команду; запускает обмен первым словом
	while (len) {
		uint32_t w, n = (len < 4U) ? len : 4U;
		SPIFLASH_WaitIdle();
		if (len <= 4U) SPIFLASH->CTRL = SPIFLASH_CTRL_CS;		//Последнее слово - без нового обмена
		w = SPIFLASH->DATA;
		len -= n;
		while (n--) { *p++ = (uint8_t)w; w >>= 8; }
	}
	SPIFLASH->CTRL = 0U;
	return SPIFLASH_OK;
}

/* Запись не больше страницы и в её пределах */
static SPIFLASH_Status page_program(uint32_t addr, const uint8_t *p, uint32_t n) {
	SPIFLASH_Status st = write_enable();
	if (st != SPIFLASH_OK) return st;
	SPIFLASH_Select();
	SPIFLASH->DATA = SPIFLASH_CmdAddr(SPIFLASH_CMD_PAGE_PROGRAM, addr);
	for (; n >= 4U; n -= 4U, p += 4) {
		uint32_t w = (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
		SPIFLASH_WaitIdle();
		SPIFLASH->DATA = w;
	}
	for (; n; n--) {
		SPIFLASH_WaitIdle();
		*(__IO uint8_t*)&SPIFLASH->DATA = *p++;
	}
	SPIFLASH_Deselect();										//CS поднимется после последнего обмена - запись пошла
	return SPIFLASH_WaitReady(T_PAGE_MS);
}

SPIFLASH_Status SPIFLASH_Write(uint32_t addr, const void *buf, uint32_t len) {
	const uint8_t *p = (const uint8_t*)buf;
	SPIFLASH_Status st = check(addr, len, 1);
	while (st == SPIFLASH_OK && len) {
		uint32_t n = SPIFLASH_PAGE_SIZE - (addr & (SPIFLASH_PAGE_SIZE - 1U));	//До конца страницы
		if (n > len) n = len;
		st = page_program(addr, p, n);
		addr += n; p += n; len -= n;
	}
	return st;
}

static SPIFLASH_Status erase(uint32_t cmd, uint32_t addr, uint32_t size, uint32_t timeout_ms) {
	addr &= ~(size - 1U);
	SPIFLASH_Status st = check(addr, size, 1);
	if (st == SPIFLASH_OK) st = write_enable();
	if (st != SPIFLASH_OK) return st;
	SPIFLASH_Xfer32(SPIFLASH_CmdAddr(cmd, addr));
	return SPIFLASH_WaitReady(timeout_ms);
}

SPIFLASH_Status SPIFLASH_EraseSector(uint32_t addr) {
	return erase(SPIFLASH_CMD_SECTOR_ERASE, addr, SPIFLASH_SECTOR_SIZE, T_SECTOR_MS);
}

SPIFLASH_Status SPIFLASH_EraseBlock(uint32_t addr) {
	return erase(SPIFLASH_CMD_BLOCK_ERASE, addr, SPIFLASH_BLOCK_SIZE, T_BLOCK_MS);
}

SPIFLASH_Status SPIFLASH_Erase(uint32_t addr, uint32_t len) {
	SPIFLASH_Status st = check(addr, len, 1);
	uint32_t end = addr + len;
	for (addr &= ~(SPIFLASH_SECTOR_SIZE - 1U); st == SPIFLASH_OK && addr < end; addr += SPIFLASH_SECTOR_SIZE)
		st = SPIFLASH_EraseSector(addr);
	return st;
}

void SPIFLASH_PowerDown(void) {
	SPIFLASH_Xfer8(SPIFLASH_CMD_POWER_DOWN);
}

void SPIFLASH_WakeUp(void) {
	uint64_t end;
	SPIFLASH_Xfer8(SPIFLASH_CMD_RELEASE_PD);
	end = CORE_GetCycles() + SYSCLK_HZ / 20000U;				//tRES1 - до 30 мкс; ждём 50 мкс
	while (CORE_GetCycles() < end) ;
}

#endif /* SPIFLASH_PRESENT */
