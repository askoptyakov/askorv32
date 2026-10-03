// Конфигуратор ПЛИС askoRV32 (GW1NR-LV9QN88P - Tang Nano 9K, GW2A-LV18PG256 - Tang Primer 20K): модель .gwsoc,
// структурная схема, изображение корпуса (QFN - выводы по краям, BGA - сетка шариков), настройки блоков справа,
// библиотека периферии. Кристалл - "device" в .gwsoc, его выводы и свойства - в devices.js (sw/socgen/mkdevices.py).
// Правила (адреса, rPLL, проверки, имена) продублированы в socgen.py - при изменении править оба места.
'use strict';

// ============================================================================================
// Данные кристалла и постоянные правила
// ============================================================================================
const DEVICES = window.GWSOC_DEVICES;
const DEFAULT_DEVICE = 'GW1NR-LV9QN88PC6/I5';
//Текущий кристалл (setDevice): выводы корпуса и свойства семейства (пределы rPLL, BSRAM, область битового потока во флеш)
let DEV = null, PIN = {}, IO_PINS = [], JTAG_PINS = {}, PLL = null, BSRAM_TOTAL = 0, CFG_REGION = 0, CFG_USER = 0;
//Вывод: номер у QFN (число), имя шарика у BGA ("H11"); значения из DOM - строки
const pinv = v => (v === '' || v == null) ? null : (/^\d+$/.test(String(v)) ? Number(v) : String(v));
//Порядок выводов: по номеру; у BGA - по ряду (A, B, ... T), затем по столбцу
function pinCmp(a, b) {
  if (typeof a === 'number' && typeof b === 'number') return a - b;
  const ra = /^([A-Z]+)(\d+)$/.exec(String(a)), rb = /^([A-Z]+)(\d+)$/.exec(String(b));
  if (!ra || !rb) return String(a).localeCompare(String(b));
  return (ra[1].length - rb[1].length) || ra[1].localeCompare(rb[1]) || (Number(ra[2]) - Number(rb[2]));
}
function setDevice(part) {
  DEV = DEVICES[part] || DEVICES[DEFAULT_DEVICE];
  PIN = {};
  DEV.pins.forEach(p => { PIN[p.n] = p; });
  IO_PINS = DEV.pins.filter(p => p.type === 'io').map(p => p.n).sort(pinCmp);
  //Выводы JTAG ПЛИС: заняты примитивом GW_JTAG при включённом отладчике
  JTAG_PINS = {};
  for (const f of ['TMS', 'TCK', 'TDI', 'TDO'])
    for (const p of DEV.pins) if ((p.cfg || '').split('/').includes(f)) JTAG_PINS[p.n] = f;
  PLL = DEV.pll;
  BSRAM_TOTAL = DEV.resources.bsram;
  CFG_REGION = DEV.cfgRegion;
  CFG_USER = DEV.cfgUser;
  layoutChip();
}
const jtagText = () => Object.entries(JTAG_PINS).map(([n, f]) => `${f} ${n}`).join(', ');
//Вывод с функцией конфигурации (MCLK, MCS_N, MO, MI...) - для выводов флеш по умолчанию
const pinWithCfg = f => { const p = DEV.pins.find(x => (x.cfg || '').split('/').includes(f)); return p ? p.n : null; };

const ODIV_SET = [2, 4, 8, 16, 32, 48, 64, 80, 96, 112, 128];

const IO_TYPES = ['LVCMOS33', 'LVCMOS25', 'LVCMOS18', 'LVCMOS15', 'LVCMOS12'];
const PULLS = ['UP', 'DOWN', 'NONE', 'KEEPER'];
const DRIVES = ['4', '8', '12', '16', '24'];
const VCCIOS = ['3.3', '2.5', '1.8', '1.5', '1.2'];

//Группы периферии и их цвета на схемах. Системное (процессор, такт, отладчик) - серое
const CATS = {
  iface:  { title: 'Интерфейсы',     color: 'var(--c-iface)' },
  gpio:   { title: 'GPIO',           color: 'var(--c-gpio)' },
  custom: { title: 'Своя периферия', color: 'var(--c-custom)' },
};
//Библиотека устройств (как TYPES в socgen.py). Описание подробнее - README.md в hw/src/periph/<тип>/.
//slot - окно адресов первого экземпляра при "auto" (окно 16 МБайт, маска 0xFF000000)
const TYPES = {
  gpio: { title: 'GPIO', ru: 'Входы/выходы', cat: 'gpio', slot: 0x11, irq: false,
    about: 'Дискретные входы/выходы: до 32 линий, направление каждой линии задаёт программа (регистры MODE, OUT, IN).',
    defaults: () => ({ lines: [] }) },
  tm1638: { title: 'TM1638', ru: 'Индикатор и кнопки', cat: 'custom', slot: 0x12, irq: false,
    about: 'Плата индикации LED&KEY на TM1638: 8 разрядов (HEX и текст cp1251 с кириллицей), 8 светодиодов, 8 кнопок. Знакогенератор занимает 1 блок BSRAM.',
    defaults: () => ({ dio: null, clk: null, stb: null }) },
  stim: { title: 'STIM', ru: 'Таймер, ШИМ', cat: 'custom', slot: 0x13, irq: true,
    about: 'Простой таймер: предделитель, счёт вверх или вниз, выход ШИМ, прерывание по переполнению.',
    defaults: () => ({ width: 16, out: null, irq: 'plic' }) },
  uart: { title: 'UART', ru: 'Приёмопередатчик', cat: 'iface', slot: 0x14, irq: true,
    about: 'Приёмопередатчик UART: FIFO 8–32 байта, чётность, 1–2 стоп-бита, прерывания по заполнению FIFO и по ошибке приёма.',
    defaults: () => ({ tx: null, rx: null, baud: 115200, parity: 'none', stop: 1, fifo: 16, irq: 'plic' }) },
  spiflash: { title: 'SPIFLASH', ru: 'Флеш-память SPI', cat: 'iface', slot: 0x15, irq: false,
    about: 'Контроллер внешней SPI-флеш: загрузка программы в IMEM/DMEM после сброса (образ записывает openFPGALoader), обмен с флеш из программы - хранение параметров. По умолчанию - выводы MSPI (флеш конфигурации ПЛИС): Tang Nano 9K - 59..62, Tang Primer 20K - L10, M9, R10, P10.',
    defaults: () => ({ sck: null, cs: null, mosi: null, miso: null, sizeMB: 4, div: 1, fpgaConfig: false, bootAddr: '0x100000' }),
    cfgPins: { sck: 'MCLK', cs: 'MCS_N', mosi: 'MO', miso: 'MI' } },
  sifu: { title: 'SIFU', ru: 'СИФУ выпрямителя', cat: 'custom', slot: 0x16, irq: true,
    about: 'СИФУ трёхфазного мостового тиристорного выпрямителя: синхронизация от платы NSB (6 оптронов на линейных напряжениях), пила на каждую пару фаз, угол управления ALPHA от точки естественной коммутации, сдвоенные импульсы на тиристоры VS1..VS6, измерение частоты сети, имитатор сети для проверки без силовой части.',
    defaults: () => ({ ab: null, ba: null, bc: null, cb: null, ca: null, ac: null,
                       vs1: null, vs2: null, vs3: null, vs4: null, vs5: null, vs6: null,
                       sawHz: 500000, delayTicks: 400, pulseTicks: 150, sim: true, irq: 'plic' }) },
};
//СИФУ: входы платы синхронизации NSB и выходы на тиристоры (как SIFU_SYNC, SIFU_GATES в socgen.py)
const SIFU_SYNC = ['ab', 'ba', 'bc', 'cb', 'ca', 'ac'];
const SIFU_GATES = ['vs1', 'vs2', 'vs3', 'vs4', 'vs5', 'vs6'];
const SIFU_SAW_MAX = 4095;
const UART_BAUDS = [1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600];
const UART_PARITY = { none: 'нет', even: 'чётность (even)', odd: 'нечётность (odd)' };
const FIFO_DEPTHS = [8, 16, 32];
const FLASH_MB = [1, 2, 4, 8, 16];
const BOOT_REGION = 0x10000;   //Область образа программы во флеш: 64 кБайт (как в socgen.py)
const MEM_KB = [8, 16, 32];
const IRQ_ROUTES = { plic: 'PLIC (по умолчанию)', local: 'локальная линия LI', none: 'не подключено' };
//Place_Option Gowin EDA (build.placeOption; пусто - как записано в hw/impl/riscv_process_config.json)
const PLACE_OPTIONS = [['', 'Place: как в проекте'], ['0', 'Place 0 - быстрее компиляция'], ['1', 'Place 1 - трассируемость'], ['2', 'Place 2 - тайминги']];
//Loading Rate (build.loadingRate, МГц): частота чтения битового потока из флеш при AUTO BOOT и MSPI.
//GW1N-9 и GW2A-18: 250 МГц / N (SUG100, табл. 4-3); пусто - как в impl/riscv_process_config.json платы (по умолчанию 2.5 МГц)
const LOADING_RATES = ['2.500', '5.435', '5.682', '5.952', '6.250', '6.579', '6.944', '7.353', '7.812', '8.333', '8.929', '9.615',
  '10.417', '11.364', '12.500', '13.889', '15.625', '17.857', '20.833', '25.000', '31.250', '41.667', '62.500'];
const LOADING_OPTIONS = [['', 'Загрузка: как в проекте'], ...LOADING_RATES.map(r => [r, `Загрузка ${+r} МГц` + (r === '2.500' ? ' (по умолчанию)' : '')])];
const FIXED_REGIONS = [
  { name: 'IMEM',  slot: 0x00, note: 'память команд' },
  { name: 'CLINT', slot: 0x02, note: 'mtime, msip' },
  { name: 'PLIC',  slot: 0x0C, note: 'прерывания периферии' },
  { name: 'DMEM',  slot: 0x10, note: 'память данных' },
  { name: 'SIM',   slot: 0x1F, note: 'tohost симулятора' },
];
const AUTO_FIRST = 0x11, AUTO_LAST = 0x1E;

const NET_RE = /^[A-Za-z_][A-Za-z0-9_$]*(\[(\d+)\])?$/;
const NAME_RE = /^[A-Za-z_][A-Za-z0-9_]{0,23}$/;
const SV_KEYWORDS = new Set(['input', 'output', 'inout', 'wire', 'logic', 'reg', 'module', 'endmodule', 'assign',
  'always', 'begin', 'end', 'if', 'else', 'case', 'for', 'generate', 'parameter', 'localparam', 'int', 'bit']);
//Имена, занятые в top.sv независимо от состава периферии (как RESERVED_NETS в socgen.py)
const RESERVED_NETS = new Set(['tck_pad_i', 'tms_pad_i', 'tdi_pad_i', 'tdo_pad_o',
  'clk_per', 'rst_per', 'bus_per_Write', 'bus_per_Read', 'bus_per_Addr', 'bus_per_WData', 'bus_per_RData', 'irq_local', 'irq_src',
  'sRead', 'top', 'cpu', 'permux', 'memmux', 'gpio_top', 'stim_top', 'tm1638_top', 'uart_top',
  'spiflash_top', 'sifu_top', 'boot_hold', 'boot_Write', 'boot_Addr', 'boot_WData',
  'CORE_TYPE', 'M_EXT', 'DIV_BPC', 'RF_TYPE', 'IMEM_TYPE', 'BSRAM_IMEM_SIZE', 'SYNTH_IMEM_SIZE', 'IMEM_INIT_FILE',
  'DMEM_TYPE', 'BSRAM_DMEM_SIZE', 'SYNTH_DMEM_SIZE', 'DMEM_INIT_FILE', 'DEBUG_EN', 'PLIC_SOURCES',
  'FCLKIN', 'PLL_DEVICE', 'XTAL_KHZ', 'PLL_IDIV_SEL', 'PLL_FBDIV_SEL', 'PLL_ODIV_SEL', 'WIN_MASK', 'CLK_BASE_MHZ', 'CLK_DMEM_MHZ']);
//Имена устройств, занятые в прошивке (как RESERVED_C в socgen.py)
const RESERVED_C = new Set(['CLINT', 'PLIC', 'SOC', 'SYSCLK_HZ', 'MTIME_HZ', 'LI', 'IRQ', 'NULL', 'MODE', 'OUT', 'IN']);

// ============================================================================================
// Модель
// ============================================================================================
let model = null;
let dirty = false;
let zoom = 0;             //0 - по размеру окна
let sel = null;           //Выбранный блок: { kind: 'clock' | 'core' | 'inst', name }
let svgW = 0, svgH = 0;   //Размер текущей схемы (viewBox)

const host = (cmd, arg) => (typeof window.gwsocHost === 'function')
  ? window.gwsocHost(cmd, arg === undefined ? null : arg) : undefined;
const inHost = () => typeof window.gwsocHost === 'function';

const hex8 = v => '0x' + (v >>> 0).toString(16).toUpperCase().padStart(8, '0');
const hexSlot = s => hex8(s * 0x01000000).replace(/^0x(....)/, '0x$1_');
const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const fmt = x => (Math.round(x * 1000) / 1000).toString().replace('.', ',');

//Формат 1 ("blocks": фиксированные блоки с enabled) -> формат 2 ("periph": список экземпляров), как migrate в socgen.py
function migrate(m) {
  if (Array.isArray(m.periph)) return m;
  const periph = [];
  for (const t of Object.keys(TYPES)) {
    const b = (m.blocks || {})[t];
    if (!b || !b.enabled) continue;
    const inst = { type: t, name: TYPES[t].title };
    for (const k of Object.keys(b)) if (k !== 'enabled') inst[k] = b[k];
    periph.push(inst);
  }
  delete m.blocks;
  m.periph = periph;
  m.version = 2;
  return m;
}

function normalize(m) {
  migrate(m);
  m.core = Object.assign({ coreType: 'pipeline', mExt: true, divBpc: 2, rfType: 'lut', debug: true, plicSources: 8 }, m.core);
  m.core.imem = Object.assign({ type: 'bsram', kb: 8, synthWords: 256, init: 'mem_init/i.mem' }, m.core.imem);
  m.core.dmem = Object.assign({ type: 'bsram', kb: 8, synthWords: 256, init: 'mem_init/d.mem' }, m.core.dmem);
  m.banks = m.banks || {};
  m.clock = m.clock || { xtalMHz: 27, xtalPin: null, pll: {} };
  m.clock.pll = Object.assign({ mode: 'auto', targetMHz: 27, idiv: 0, fbdiv: 0, odiv: 32 }, m.clock.pll);
  m.reset = m.reset || { pin: null };
  //Ключи экземпляра в файле: тип, имя, адрес, затем настройки
  m.periph = m.periph.filter(i => TYPES[i.type]).map(i => {
    const full = Object.assign(TYPES[i.type].defaults(), { base: 'auto' }, i);
    const o = { type: full.type, name: full.name, base: full.base };
    for (const k of Object.keys(full)) if (!(k in o)) o[k] = full[k];
    if (o.type === 'spiflash') delete o.boot;   //Загрузка программы теперь следует из fpgaConfig (режим MSPI)
    return o;
  });
  m.ioDefaults = Object.assign({ ioType: 'LVCMOS18', pull: 'UP', drive: '8', vccio: '1.8' }, m.ioDefaults);
  m.pins = m.pins || {};
  m.build = Object.assign({ toolchain: 'gowin' }, m.build);
  return m;
}

const insts = (m, type) => m.periph.filter(i => !type || i.type === type);
const instByName = name => model.periph.find(i => i.name === name);
const hdl = inst => inst.name.toLowerCase();                 //Имя экземпляра в top.sv и префикс его сигналов шины
const firstOfType = (m, inst) => insts(m, inst.type)[0] === inst;
const instColor = inst => CATS[TYPES[inst.type].cat].color;
const instTitle = inst => inst.name === TYPES[inst.type].title ? inst.name : `${inst.name} (${TYPES[inst.type].title})`;

//Сигналы устройства, которым нужен вывод (как inst_signals в socgen.py)
function instSignals(inst) {
  switch (inst.type) {
    case 'gpio': return inst.lines.map((p, i) => ({ key: 'line' + i, label: 'IO' + i, dir: 'inout' }));
    case 'tm1638': return [{ key: 'dio', label: 'DIO', dir: 'inout' }, { key: 'clk', label: 'CLK', dir: 'output' },
                           { key: 'stb', label: 'STB', dir: 'output' }];
    case 'stim': return inst.out != null ? [{ key: 'out', label: 'PWM', dir: 'output' }] : [];
    case 'uart': return [{ key: 'tx', label: 'TX', dir: 'output' }, { key: 'rx', label: 'RX', dir: 'input' }];
    case 'spiflash': return [{ key: 'sck', label: 'SCK', dir: 'output' }, { key: 'cs', label: 'CS#', dir: 'output' },
                             { key: 'mosi', label: 'MOSI', dir: 'output' }, { key: 'miso', label: 'MISO', dir: 'input' }];
    case 'sifu': return [...SIFU_SYNC.map(k => ({ key: k, label: k.toUpperCase(), dir: 'input' })),
                         ...SIFU_GATES.map(k => ({ key: k, label: k.toUpperCase(), dir: 'output' }))];
  }
  return [];
}
const instPin = (inst, key) => key.startsWith('line') ? inst.lines[Number(key.slice(4))] : inst[key];
//Имя цепи по умолчанию для нового вывода (заглавными: имя цепи - и порт top.sv, и define в Си)
const defNet = (inst, key) => (key.startsWith('line') ? `${inst.name}_IO${key.slice(4)}` : `${inst.name}_${key === 'out' ? 'PWM' : key}`).toUpperCase();

//Все сигналы, которым нужен вывод (система + периферия)
function signals(m) {
  const s = [];
  s.push({ id: 'clk', inst: null, key: 'clk', name: 'Кварц', dir: 'input', pin: m.clock.xtalPin, def: 'CLK' });
  s.push({ id: 'rst', inst: null, key: 'rst', name: 'Сброс (актив. 0)', dir: 'input', pin: m.reset.pin, def: 'RST_N' });
  for (const inst of m.periph)
    for (const g of instSignals(inst))
      s.push({ id: `${inst.name}.${g.key}`, inst, key: g.key, name: `${inst.name} ${g.label}`, dir: g.dir,
               pin: instPin(inst, g.key), def: defNet(inst, g.key) });
  return s;
}
const sigColor = s => s.inst ? instColor(s.inst) : 'var(--c-sys)';

function setSignalPin(m, sig, pin) {
  pin = pinv(pin);
  if (sig.id === 'clk') m.clock.xtalPin = pin;
  else if (sig.id === 'rst') m.reset.pin = pin;
  else if (sig.key.startsWith('line')) sig.inst.lines[Number(sig.key.slice(4))] = pin;
  else sig.inst[sig.key] = pin;
}
const findSig = id => signals(model).find(s => s.id === id);
//Перенос сигнала на другой вывод: имя цепи переходит вместе с сигналом, если у нового вывода его нет
function movePin(sig, pin) {
  const old = sig.pin, oldNet = old != null ? netOf(model, old) : '';
  setSignalPin(model, sig, pin);
  if (pin === '' || pin == null) return;
  const n = pinv(pin);
  if (oldNet && !netOf(model, n) && old !== n) { setNet(model, old, ''); setNet(model, n, oldNet); }
  else ensureNet(model, { pin: n, def: sig.def });
}

const netOf = (m, n) => (m.pins[n] && m.pins[n].net) || '';
function setNet(m, n, net) {
  net = (net || '').trim().toUpperCase();
  const p = m.pins[n] || {};
  if (net) p.net = net; else delete p.net;
  if (Object.keys(p).length) m.pins[n] = p; else delete m.pins[n];
}
//Назначенному выводу без имени цепи даётся имя по умолчанию
function ensureNet(m, sig) {
  if (sig.pin == null || netOf(m, sig.pin)) return;
  const used = new Set(Object.values(m.pins).map(p => p.net).filter(Boolean));
  let net = sig.def, k = 1;
  while (used.has(net)) net = sig.def.replace(/(\[\d+\])?$/, '_' + (k++) + '$1');
  setNet(m, sig.pin, net);
}
//Имя цепи -> имя в Си: LED[3] -> LED3, заглавными (как c_name в socgen.py)
const cName = net => net.replace(/\[(\d+)\]$/, '$1').replace(/\$/g, '_').toUpperCase();

//Все имена, занятые в top.sv при текущем составе периферии
function reservedNets(m) {
  const r = new Set(RESERVED_NETS);
  for (const inst of m.periph) {
    const h = hdl(inst);
    [h, `${h}_Write`, `${h}_Addr`, `${h}_WriteData`, `${h}_ReadData`, `irq_${h}`, `${inst.name.toUpperCase()}_BASE`].forEach(x => r.add(x));
  }
  return r;
}

//Единственный блок типа - без номера: UART0 -> UART. Возвращает список переименований
function unnumberSingles(m) {
  const done = [];
  for (const [type, t] of Object.entries(TYPES)) {
    const same = insts(m, type);
    if (same.length === 1 && new RegExp(`^${t.title}\\d+$`, 'i').test(same[0].name) &&
        !m.periph.some(i => i.name.toLowerCase() === t.title.toLowerCase())) {
      done.push(`${same[0].name} → ${t.title}`);
      same[0].name = t.title;
    }
  }
  return done;
}

//Имя нового экземпляра: имя типа, если свободно, иначе ИМЯ1, ИМЯ2...
function defaultName(m, type) {
  const t = TYPES[type].title, used = new Set(m.periph.map(i => i.name.toLowerCase()));
  if (!insts(m, type).length && !used.has(t.toLowerCase())) return t;
  for (let k = 1; ; k++) if (!used.has((t + k).toLowerCase())) return t + k;
}

// --- Частота шины периферии, UART, прерывания, стандарты выводов (как в socgen.py) ---
function sysclkHz(m) {
  const bsram = m.core.imem.type === 'bsram' || m.core.dmem.type === 'bsram';
  return Math.round(pllOf(m).fout * 1e6 / (m.core.coreType === 'singlecycle' && bsram ? 3 : 1));
}
function uartDiv(m, u) {
  const f = sysclkHz(m), baud = Number(u.baud);
  const div = Math.max(0, Math.round(f / baud) - 1), real = f / (div + 1);
  return { div, real, err: Math.abs(real - baud) / baud * 100 };
}
//СИФУ: делитель тика ГПН, частота пилы, тиков на полупериод 50 Гц, наибольший угол (как sifu_info в socgen.py)
function sifuInfo(m, s) {
  const f = sysclkHz(m), saw = Number(s.sawHz);
  const div = saw > 0 ? Math.max(0, Math.round(f / saw) - 1) : -1, real = div >= 0 ? f / (div + 1) : 0;
  const delay = Number(s.delayTicks), pulse = Number(s.pulseTicks);
  const half = real / 100, alphaMax = SIFU_SAW_MAX - 1 - delay - pulse;
  const deg = ticks => half ? ticks * 180 / half : 0;
  return { div, saw: real, half, delay, pulse, alphaMax, alphaMaxDeg: deg(alphaMax),
           pulseUs: real ? pulse / real * 1e6 : 0, pulseDeg: deg(pulse), delayDeg: deg(delay) };
}
//Прерывания: по умолчанию - источники PLIC 1, 2, ... в порядке списка; irq = 'local' - LI0, LI1...
function irqMap(m) {
  const res = {};
  let nPlic = 0, nLoc = 0;
  for (const inst of m.periph) {
    if (!TYPES[inst.type].irq) continue;
    const route = inst.irq || 'plic';
    if (route === 'plic') res[inst.name] = { route, n: ++nPlic };
    else if (route === 'local') res[inst.name] = { route, n: nLoc++ };
  }
  return res;
}
//Блоки BSRAM: IMEM и DMEM по 2 кБайт на блок, шрифт каждого TM1638 - один блок
//Флеш блока SPIFLASH: частота SCK, объём, область образа программы и свободная область (как flash_info в socgen.py)
function flashInfo(m, f) {
  //Загрузчик программы включён только при хранении во внешней флеш (MSPI), как в socgen.py
  const div = Number(f.div), size = Number(f.sizeMB) * 1048576, fpgaConfig = !!f.fpgaConfig, boot = fpgaConfig;
  const bootAddr = parseBase(f.bootAddr) || 0, user = boot ? bootAddr + BOOT_REGION : (fpgaConfig ? CFG_USER : 0);
  return { div, sck: sysclkHz(m) / (2 * (div + 1)), size, boot, bootAddr, fpgaConfig, user, userSize: Math.max(0, size - user) };
}
const hex6 = v => '0x' + (v >>> 0).toString(16).toUpperCase().padStart(6, '0');
//Регистровый файл на BSRAM (как rf_bsram в socgen.py): только у конвейерного ядра
const rfBsram = m => (m.core.rfType === 'bsram' || m.core.rfType === 'bsram-edge') && m.core.coreType !== 'singlecycle';
function bsramBlocks(m) {
  let used = 0;
  for (const k of ['imem', 'dmem']) if (m.core[k].type === 'bsram') used += Math.floor(Number(m.core[k].kb) / 2);
  return used + insts(m, 'tm1638').length + (rfBsram(m) ? 2 : 0);
}
const irqText = r => !r ? 'не подключено' : r.route === 'plic' ? `PLIC ${r.n}` : `LI${r.n}`;
//Стандарт вывода: свои настройки вывода, иначе банка, иначе общие
function pinAttrs(m, n) {
  const bank = PIN[n] ? String(PIN[n].bank) : '';
  const a = Object.assign({}, m.ioDefaults, m.banks[bank] || {});
  const own = m.pins[n] || {};
  for (const k of ['ioType', 'pull', 'drive', 'vccio']) if (own[k]) a[k] = own[k];
  return a;
}
const bankDefault = (m, n, key) => {
  const bank = PIN[n] ? String(PIN[n].bank) : '';
  return (m.banks[bank] && m.banks[bank][key]) || m.ioDefaults[key];
};

// --- Адреса периферии ---
function parseBase(v) {
  if (v === 'auto' || v == null || v === '') return null;
  const x = typeof v === 'number' ? v : parseInt(String(v).replace(/_/g, ''), 16);
  return Number.isFinite(x) ? x : NaN;
}
function addressMap(m) {
  const rows = FIXED_REGIONS.map(r => ({ name: r.name, slot: r.slot, color: 'var(--c-sys)', note: r.note, fixed: true }));
  const taken = new Map(rows.map(r => [r.slot, r.name]));
  const issues = [];
  //Сначала ручные адреса, затем автоматические - чтобы ручной не был отнят автоматическим
  for (const pass of ['manual', 'auto']) {
    for (const inst of m.periph) {
      const base = parseBase(inst.base);
      if ((base === null) !== (pass === 'auto')) continue;
      const row = { name: inst.name, inst, color: instColor(inst), note: TYPES[inst.type].title, auto: base === null };
      if (base === null) {
        let s = firstOfType(m, inst) ? TYPES[inst.type].slot : AUTO_FIRST;
        if (taken.has(s)) { s = AUTO_FIRST; while (s <= AUTO_LAST && taken.has(s)) s++; }
        if (s > AUTO_LAST) { issues.push({ lvl: 'err', text: `${inst.name}: нет свободного окна адресов`, inst: inst.name }); continue; }
        row.slot = s;
      } else if (Number.isNaN(base) || base < 0 || base > 0xFFFFFFFF || (base & 0x00FFFFFF) !== 0) {
        issues.push({ lvl: 'err', text: `${inst.name}: адрес должен быть кратен 0x0100_0000 (окно 16 МБайт)`, inst: inst.name });
        row.slot = null;
      } else {
        row.slot = base >>> 24;
        if (taken.has(row.slot)) issues.push({ lvl: 'err', text: `${inst.name}: адрес ${hexSlot(row.slot)} уже занят (${taken.get(row.slot)})`, inst: inst.name });
      }
      if (row.slot != null) taken.set(row.slot, inst.name);
      rows.push(row);
    }
  }
  rows.sort((a, b) => (a.slot ?? 999) - (b.slot ?? 999));
  return { rows, issues, baseOf: name => { const r = rows.find(x => x.inst && x.inst.name === name); return r ? r.slot : null; } };
}

// --- rPLL ---
function pllEval(fin, idiv, fbdiv, odiv) {
  const pfd = fin / (idiv + 1), fout = fin * (fbdiv + 1) / (idiv + 1), vco = fout * odiv;
  const errs = [];
  if (!(fin >= PLL.inMin && fin <= PLL.inMax)) errs.push(`частота кварца вне ${PLL.inMin}..${PLL.inMax} МГц`);
  if (!(pfd >= PLL.pfdMin && pfd <= PLL.pfdMax)) errs.push(`PFD ${fmt(pfd)} МГц вне ${PLL.pfdMin}..${PLL.pfdMax}`);
  if (!(vco >= PLL.vcoMin && vco <= PLL.vcoMax)) errs.push(`VCO ${fmt(vco)} МГц вне ${PLL.vcoMin}..${PLL.vcoMax}`);
  if (!(fout >= PLL.outMin && fout <= PLL.outMax)) errs.push(`CLKOUT ${fmt(fout)} МГц вне ${PLL.outMin}..${PLL.outMax}`);
  return { pfd, fout, vco, errs };
}
//Подбор: минимальная ошибка частоты, затем наименьшие делители, затем наибольшая VCO
function pllSolve(fin, target) {
  let best = null;
  for (let idiv = 0; idiv < 64; idiv++) {
    const pfd = fin / (idiv + 1);
    if (pfd < PLL.pfdMin || pfd > PLL.pfdMax) continue;
    for (let fbdiv = 0; fbdiv < 64; fbdiv++) {
      const fout = fin * (fbdiv + 1) / (idiv + 1);
      if (fout < PLL.outMin || fout > PLL.outMax) continue;
      let odiv = null;
      for (const o of ODIV_SET) { const v = fout * o; if (v >= PLL.vcoMin && v <= PLL.vcoMax) odiv = o; }
      if (odiv === null) continue;
      const key = [Math.abs(fout - target), idiv + fbdiv, -fout * odiv];
      if (!best || key[0] < best.key[0] - 1e-9 || (Math.abs(key[0] - best.key[0]) <= 1e-9 &&
          (key[1] < best.key[1] || (key[1] === best.key[1] && key[2] < best.key[2]))))
        best = { idiv, fbdiv, odiv, key };
    }
  }
  return best;
}
function applyPllAuto(m) {
  const p = m.clock.pll;
  if (p.mode !== 'auto') return;
  const r = pllSolve(Number(m.clock.xtalMHz), Number(p.targetMHz));
  if (r) Object.assign(p, { idiv: r.idiv, fbdiv: r.fbdiv, odiv: r.odiv });
}
const pllOf = m => pllEval(Number(m.clock.xtalMHz), m.clock.pll.idiv, m.clock.pll.fbdiv, m.clock.pll.odiv);
const clockCapable = n => { const c = PIN[n] && PIN[n].cfg || ''; return /GCLK|PLL\d?_T_IN/i.test(c); };

// --- Проверка ---
function validate(m) {
  const out = [];
  //Имена устройств
  const seen = new Map();
  for (const inst of m.periph) {
    const n = inst.name || '';
    if (!NAME_RE.test(n)) { out.push({ lvl: 'err', text: `Имя «${n}»: латиница, цифры и _, не с цифры, до 24 символов`, inst: n }); continue; }
    if (seen.has(n.toLowerCase())) out.push({ lvl: 'err', text: `Имя устройства «${n}» повторяется`, inst: n });
    seen.set(n.toLowerCase(), n);
    if (RESERVED_C.has(n.toUpperCase()) || RESERVED_NETS.has(n.toLowerCase()) || SV_KEYWORDS.has(n.toLowerCase()))
      out.push({ lvl: 'err', text: `Имя устройства «${n}» занято в прошивке или в top.sv`, inst: n });
    const own = Object.keys(TYPES).find(t => TYPES[t].title === n);
    if (own && (own !== inst.type || !firstOfType(m, inst)))
      out.push({ lvl: 'err', text: `Имя «${n}» - имя типа ${n}: его может носить только первый блок этого типа`, inst: n });
  }

  const sigs = signals(m);
  const byPin = new Map();
  for (const s of sigs) {
    const instName = s.inst ? s.inst.name : (s.id === 'clk' || s.id === 'rst' ? 'clock' : null);
    if (s.pin == null) { out.push({ lvl: 'err', text: `${s.name}: вывод не назначен`, inst: instName }); continue; }
    if (!PIN[s.pin] || PIN[s.pin].type !== 'io') { out.push({ lvl: 'err', text: `${s.name}: вывод ${s.pin} не является I/O`, pin: s.pin }); continue; }
    if (m.core.debug && JTAG_PINS[s.pin]) out.push({ lvl: 'err', text: `${s.name}: вывод ${s.pin} занят JTAG (${JTAG_PINS[s.pin]})`, pin: s.pin });
    if (!byPin.has(s.pin)) byPin.set(s.pin, []);
    byPin.get(s.pin).push(s);
  }
  for (const [pin, list] of byPin)
    if (list.length > 1) out.push({ lvl: 'err', text: `Вывод ${pin}: ${list.map(s => s.name).join(', ')} - конфликт`, pin, conflict: true });

  //Имена цепей назначенных выводов: допустимость, уникальность, непрерывность шин
  const reserved = reservedNets(m);
  const nets = new Map(), buses = new Map();
  for (const [pin] of byPin) {
    const net = netOf(m, pin);
    if (!net) { out.push({ lvl: 'err', text: `Вывод ${pin}: нет имени цепи`, pin }); continue; }
    const mm = NET_RE.exec(net);
    const baseName = mm ? net.replace(/\[\d+\]$/, '') : net;
    if (mm && reserved.has(baseName)) { out.push({ lvl: 'err', text: `Вывод ${pin}: имя «${baseName}» уже занято в top.sv - выберите другое`, pin }); continue; }
    if (!mm || SV_KEYWORDS.has(baseName)) { out.push({ lvl: 'err', text: `Вывод ${pin}: имя «${net}» недопустимо для порта SystemVerilog`, pin }); continue; }
    if (nets.has(net)) out.push({ lvl: 'err', text: `Имя «${net}» у выводов ${nets.get(net)} и ${pin}`, pin });
    if (net !== net.toUpperCase()) out.push({ lvl: 'warn', text: `Имя цепи «${net}» пишут заглавными (${net.toUpperCase()}): это и define в Си - переименуйте`, pin });
    nets.set(net, pin);
    if (!buses.has(baseName)) buses.set(baseName, { idx: [], scalar: false });
    if (mm[2] !== undefined) buses.get(baseName).idx.push(Number(mm[2])); else buses.get(baseName).scalar = true;
  }
  for (const [name, b] of buses) {
    if (b.scalar && b.idx.length) out.push({ lvl: 'err', text: `«${name}» используется и как шина, и как одиночный сигнал` });
    if (b.idx.length) {
      const max = Math.max(...b.idx), miss = [];
      for (let i = 0; i <= max; i++) if (!b.idx.includes(i)) miss.push(i);
      if (miss.length) out.push({ lvl: 'err', text: `Шина «${name}[${max}:0]»: нет разрядов ${miss.join(', ')}` });
    }
  }
  //Имена выводов GPIO в Си (soc.h): <имя>_Pin, <имя>_Port
  const cn = new Map();
  for (const s of sigs) {
    if (!s.inst || s.inst.type !== 'gpio' || s.pin == null) continue;
    const net = netOf(m, s.pin);
    if (!net || !NET_RE.test(net)) continue;
    const c = cName(net);
    if (cn.has(c) && cn.get(c) !== net) out.push({ lvl: 'err', text: `Цепи «${cn.get(c)}» и «${net}» дают в Си одно имя ${c}_PIN`, pin: s.pin });
    cn.set(c, net);
  }

  if (m.clock.xtalPin != null && PIN[m.clock.xtalPin] && !clockCapable(m.clock.xtalPin))
    out.push({ lvl: 'warn', text: `Кварц на выводе ${m.clock.xtalPin} без GCLK/PLL_IN: такт пойдёт по обычной трассировке`, pin: m.clock.xtalPin });
  const pll = pllOf(m);
  pll.errs.forEach(e => out.push({ lvl: 'err', text: 'rPLL: ' + e, inst: 'clock' }));

  //Банки: одно напряжение VCCIO на банк (иначе Gowin EDA остановит размещение)
  const bankV = new Map();
  for (const pin of byPin.keys()) {
    const p = PIN[pin]; if (!p || p.bank == null) continue;
    const v = pinAttrs(m, pin).vccio;
    if (!bankV.has(p.bank)) bankV.set(p.bank, new Map());
    const vs = bankV.get(p.bank);
    if (!vs.has(v)) vs.set(v, []);
    vs.get(v).push(pin);
  }
  for (const [bank, vs] of bankV)
    if (vs.size > 1) out.push({ lvl: 'err', text: `Банк ${bank}: разные BANK_VCCIO - ` +
      [...vs].map(([v, ps]) => `${v} В у выводов ${ps.sort((a, b) => a - b).join(', ')}`).join('; ') });

  //Ядро и прерывания
  const c = m.core;
  if (![1, 2, 4].includes(Number(c.divBpc))) out.push({ lvl: 'err', text: 'Ядро: бит частного за такт - 1, 2 или 4', inst: 'core' });
  for (const k of ['imem', 'dmem'])
    if (c[k].type === 'bsram' && !MEM_KB.includes(Number(c[k].kb))) out.push({ lvl: 'err', text: `Ядро: ${k.toUpperCase()} в BSRAM - 8, 16 или 32 кБайт`, inst: 'core' });
  const nsrc = Number(c.plicSources);
  if (!(nsrc >= 1 && nsrc <= 31)) out.push({ lvl: 'err', text: 'Ядро: источников PLIC 1..31', inst: 'core' });
  const irqs = Object.values(irqMap(m));
  const usedPlic = irqs.filter(r => r.route === 'plic').map(r => r.n);
  if (usedPlic.length && Math.max(...usedPlic) > nsrc)
    out.push({ lvl: 'err', text: `PLIC: устройствам нужно ${Math.max(...usedPlic)} источников, а в ядре ${nsrc} - увеличьте число источников PLIC`, inst: 'core' });
  if (irqs.filter(r => r.route === 'local').length > 16) out.push({ lvl: 'err', text: 'Локальных линий прерываний всего 16' });
  const nbs = bsramBlocks(m);
  if (nbs > BSRAM_TOTAL) out.push({ lvl: 'err', text: `BSRAM: нужно ${nbs} блоков, в ПЛИС ${BSRAM_TOTAL} - уменьшите IMEM/DMEM`, inst: 'core' });
  if (!c.mExt) out.push({ lvl: 'warn', text: 'Ядро без расширения M: в настройках проекта Eclipse замените -march=rv32im_zicsr на rv32i_zicsr', inst: 'core' });

  //Устройства
  for (const inst of m.periph) {
    if (inst.type === 'gpio') {
      if (!inst.lines.length) out.push({ lvl: 'err', text: `${inst.name}: нет ни одной линии - добавьте линию (+)`, inst: inst.name });
      if (inst.lines.length > 32) out.push({ lvl: 'err', text: `${inst.name}: не больше 32 линий`, inst: inst.name });
    }
    if (inst.type === 'spiflash') {
      const fi = flashInfo(m, inst);
      if (!FLASH_MB.includes(Number(inst.sizeMB))) out.push({ lvl: 'err', text: `${inst.name}: объём флеш 1, 2, 4, 8 или 16 МБайт`, inst: inst.name });
      if (!(fi.div >= 0 && fi.div <= 255)) out.push({ lvl: 'err', text: `${inst.name}: делитель SCK 0..255`, inst: inst.name });
      if (fi.boot) {
        const ba = parseBase(inst.bootAddr);
        if (Number.isNaN(ba) || (ba || 0) % BOOT_REGION) out.push({ lvl: 'err', text: `${inst.name}: адрес образа программы кратен 0x10000 (64 кБайт)`, inst: inst.name });
        else if (fi.bootAddr + BOOT_REGION > fi.size) out.push({ lvl: 'err', text: `${inst.name}: адрес образа ${hex6(fi.bootAddr)} вне флеш (${inst.sizeMB} МБайт)`, inst: inst.name });
        else if (fi.bootAddr < CFG_REGION) out.push({ lvl: 'err', text: `${inst.name}: флеш хранит конфигурацию ПЛИС (с адреса 0) - образ программы не ниже ${hex6(CFG_REGION)}`, inst: inst.name });
      }
    }
    if (inst.type === 'sifu' && !pll.errs.length) {
      const si = sifuInfo(m, inst);
      if (!(si.div >= 0 && si.div <= 0xFFFF)) out.push({ lvl: 'err', text: `${inst.name}: частоту пилы ${inst.sawHz} Гц при частоте ${sysclkHz(m)} Гц не получить (DIV 0..65535)`, inst: inst.name });
      if (!(si.delay >= 0 && si.delay <= SIFU_SAW_MAX && si.pulse >= 0 && si.pulse <= SIFU_SAW_MAX))
        out.push({ lvl: 'err', text: `${inst.name}: сдвиг DELAY и длительность импульса - 0..4095 тиков`, inst: inst.name });
      else if (si.alphaMax < 0) out.push({ lvl: 'err', text: `${inst.name}: DELAY + длительность импульса больше пилы (4094 тика) - импульсов не будет`, inst: inst.name });
      else if (si.half && si.alphaMaxDeg < 120)
        out.push({ lvl: 'warn', text: `${inst.name}: угол управления - только до ${si.alphaMaxDeg.toFixed(1)} эл. град. (нужно 120): уменьшите частоту пилы, DELAY или длительность импульса`, inst: inst.name });
      if (si.half >= 8192) out.push({ lvl: 'err', text: `${inst.name}: полупериод 50 Гц - ${Math.round(si.half)} тиков, больше 8191: модуль будет считать, что синхронизации нет - уменьшите частоту пилы`, inst: inst.name });
    }
    if (inst.type === 'uart' && !pll.errs.length) {
      const u = uartDiv(m, inst);
      if (u.div < 7 || u.div > 0xFFFF)
        out.push({ lvl: 'err', text: `${inst.name}: скорость ${inst.baud} при частоте ${sysclkHz(m)} Гц не получить (div ${u.div}, нужно 7..65535)`, inst: inst.name });
      else if (u.err > 2) out.push({ lvl: 'err', text: `${inst.name}: ошибка скорости ${u.err.toFixed(2)} % (фактически ${Math.round(u.real)} бит/с) - больше 2 %`, inst: inst.name });
      else if (u.err > 1) out.push({ lvl: 'warn', text: `${inst.name}: ошибка скорости ${u.err.toFixed(2)} % (фактически ${Math.round(u.real)} бит/с)`, inst: inst.name });
    }
  }

  const cfgs = insts(m, 'spiflash').filter(f => f.fpgaConfig).map(f => f.name);
  if (cfgs.length > 1) out.push({ lvl: 'err', text: `Конфигурацию ПЛИС может хранить только одна флеш (выводы MSPI): ${cfgs.join(', ')}`, inst: cfgs[1] });
  if (m.build.toolchain === 'apicula' && m.core.debug)
    if (!DEV.apicula.jtag) out.push({ lvl: 'warn', text: `apicula: отладчик JTAG в этой сборке будет выключен (GW_JTAG для ${DEV.family} не поддерживается)` });
  if (m.build.toolchain === 'apicula' && DEV.family.startsWith('GW2A'))
    out.push({ lvl: 'warn', text: 'apicula и GW2A-18: отладчик работает, но память BSRAM (IMEM, DMEM) на плате не работает - для программы собирайте в Gowin EDA' });
  if (m.build.toolchain === 'apicula' && !pll.errs.length && pll.fout > 31.5)
    out.push({ lvl: 'warn', text: `apicula: ${fmt(pll.fout)} МГц - открытый маршрут держит около 31 МГц, Gowin EDA - 45 МГц` });
  out.push(...addressMap(m).issues);
  return { issues: out, byPin };
}

// ============================================================================================
// SVG
// ============================================================================================
const SVGNS = 'http://www.w3.org/2000/svg';
function el(tag, attrs, parent, text) {
  const e = document.createElementNS(SVGNS, tag);
  for (const k in attrs) e.setAttribute(k, attrs[k]);
  if (text !== undefined) e.textContent = text;
  if (parent) parent.appendChild(e);
  return e;
}
const BANK_COLOR = b => `var(--bank${b})`;

//Схема: слева микросхема с выводами, справа структура (процессор, шины, периферия и её выводы)
//Размеры корпуса: QFN - выводы по четырём сторонам (номер внутри, имя цепи снаружи), BGA - сетка шариков
let G = null;
function layoutChip() {
  if (DEV.pkgType === 'ARRAY') {
    G = { array: true, cell: 44, marg: 16, o: 30, head: 34 };
    G.body = Math.max(DEV.cols, DEV.rows.length) * G.cell + 2 * G.marg;
    G.top = G.o + G.head;                       //Верх корпуса: над ним - название и номера столбцов
    G.size = G.body + G.o + G.top;
  } else {
    G = { pitch: 22, pad: 16, marg: 22, label: 116 };
    G.body = DEV.perSide * G.pitch + 2 * G.marg;
    G.o = G.label + G.pad + 8;
    G.top = G.o;
    G.size = G.body + 2 * G.o;
  }
}
const SG = { sysX: 112, sysW: 214, busX: 380, clkX: 398, perX: 420, perW: 196, pinX: 654, top: 20, gap: 14, row: 20, w: 850 };
const structX = () => G.size + 20;  //Структура - правее микросхемы
let hover = null;                 //Блок под указателем: подсветка его выводов на микросхеме

function render() {
  const v = validate(model);
  const svg = document.getElementById('chip');
  svg.textContent = '';
  drawChip(el('g', { class: 'chip-part' }, svg), v);
  const sh = drawStruct(el('g', { class: 'struct-part', transform: `translate(${structX()} 0)` }, svg), v);
  svgW = structX() + SG.w;
  svgH = Math.max(G.size, sh);
  svg.setAttribute('viewBox', `0 0 ${svgW} ${svgH}`);
  applyZoom();
  applyHighlight();
  renderSettings(v);
  renderIssues(v);
  renderAddressMap();
  renderLegend();
  renderIoTable(v);
  renderResources();
  document.getElementById('placeOpt').value = model.build.placeOption ?? '';
  document.getElementById('placeOpt').disabled = model.build.toolchain !== 'gowin';
  document.getElementById('loadRate').value = model.build.loadingRate ?? '';
  document.getElementById('loadRate').disabled = model.build.toolchain !== 'gowin';
}

//Подсветка выводов блока под указателем (или выбранного): остальные выводы приглушаются
function applyHighlight() {
  const svg = document.getElementById('chip');
  const name = hover || (sel ? (sel.kind === 'inst' ? sel.name : sel.kind === 'clock' ? 'sys' : null) : null);
  svg.classList.toggle('hl', !!name);
  svg.querySelectorAll('.pin').forEach(g => g.classList.toggle('on', !!name && g.classList.contains('b-' + name)));
  svg.querySelectorAll('.blk[data-hl]').forEach(g => g.classList.toggle('hover', g.dataset.hl === hover));
}
function hoverOn(g, name) {
  g.dataset.hl = name;
  g.addEventListener('mouseenter', () => { hover = name; applyHighlight(); });
  g.addEventListener('mouseleave', () => { hover = null; applyHighlight(); });
}

// --- Микросхема: номера выводов внутри корпуса, имена цепей снаружи ---
function pinGeom(n) {
  if (G.array) {
    const mm = /^([A-Z]+)(\d+)$/.exec(String(n));
    const r = DEV.rows.indexOf(mm[1]), c = Number(mm[2]) - 1;
    return { side: 'A', x: G.o + G.marg + c * G.cell + G.cell / 2, y: G.top + G.marg + r * G.cell + G.cell / 2 };
  }
  const N = DEV.perSide, o = G.o, B = G.body;
  const side = Math.floor((n - 1) / N), k = (n - 1) % N;
  const c = G.marg + G.pitch * k + G.pitch / 2;
  switch (side) {
    case 0: return { side: 'L', x: o, y: o + c };
    case 1: return { side: 'B', x: o + c, y: o + B };
    case 2: return { side: 'R', x: o + B, y: o + B - c };
    default: return { side: 'T', x: o + B - c, y: o };
  }
}

function drawChip(svg, v) {
  const sigByPin = new Map();
  signals(model).forEach(s => { if (s.pin != null) { if (!sigByPin.has(s.pin)) sigByPin.set(s.pin, []); sigByPin.get(s.pin).push(s); } });
  const conflictPins = new Set(v.issues.filter(i => i.conflict).map(i => i.pin));
  const body = el('rect', { class: 'body-rect', x: G.o, y: G.top, width: G.body, height: G.body, rx: 10 }, svg);
  el('title', {}, body, 'Двойной щелчок - показать все выводы');
  body.addEventListener('dblclick', () => { hover = null; if (sel) select(null); else applyHighlight(); });
  if (G.array) {
    //BGA: название над корпусом, буквы рядов слева, номера столбцов сверху, метка A1
    el('text', { class: 'chip-title', x: G.o + G.body / 2, y: G.o - 4 }, svg, `${DEV.title} · вид сверху · ${DEV.pins.length} шариков`);
    DEV.rows.forEach((r, i) => el('text', { class: 'chip-axis', x: G.o - 10, y: G.top + G.marg + i * G.cell + G.cell / 2, 'dominant-baseline': 'central' }, svg, r));
    for (let c = 0; c < DEV.cols; c++) el('text', { class: 'chip-axis', x: G.o + G.marg + c * G.cell + G.cell / 2, y: G.top - 8 }, svg, String(c + 1));
    el('path', { class: 'pin1', d: `M${G.o} ${G.top + 18} V${G.top + 10} Q${G.o} ${G.top} ${G.o + 10} ${G.top} H${G.o + 18} Z` }, svg);
  } else {
    el('circle', { class: 'pin1', cx: G.o + 14, cy: G.o + 14, r: 5 }, svg);
    el('text', { class: 'chip-title', x: G.o + G.body / 2, y: G.o + G.body / 2 - 6 }, svg, DEV.title);
    el('text', { class: 'chip-sub', x: G.o + G.body / 2, y: G.o + G.body / 2 + 14 }, svg, `вид сверху · ${DEV.pins.length} выводов`);
  }
  for (const p of DEV.pins) drawPin(svg, p, sigByPin.get(p.n) || [], conflictPins.has(p.n));
}

//Шарик BGA: кружок цвета банка, внутри - имя шарика и имя цепи (коротко), кольцо цвета блока - вывод занят
function drawBall(gp, p, g, sigs, conflict, net, jtag) {
  const R = 18;
  const fill = p.type === 'gnd' ? 'var(--gnd)' : p.type === 'pwr' ? 'var(--pwr)' : BANK_COLOR(p.bank);
  if (p.type === 'io') {
    const mk = el('circle', { class: 'mark ring', cx: g.x, cy: g.y, r: R + 2.5 }, gp);
    if (sigs.length && !conflict) mk.style.stroke = sigColor(sigs[0]);
    else if (jtag && !sigs.length) mk.style.stroke = 'var(--c-jtag)';
  }
  el('circle', { class: 'cell', cx: g.x, cy: g.y, r: R, fill }, gp);
  el('text', { class: 'num', x: g.x, y: g.y - (p.type === 'io' ? 6 : 0), 'text-anchor': 'middle', 'dominant-baseline': 'central' }, gp,
     p.type === 'io' ? String(p.n) : (p.type === 'gnd' ? '⏚' : 'V'));
  let label = net || (jtag && p.type === 'io' ? jtag : '');
  const lab = el('text', { class: 'label ball-label', x: g.x, y: g.y + 7, 'text-anchor': 'middle', 'dominant-baseline': 'central' }, gp,
                 label.length > 7 ? label.slice(0, 6) + '…' : label);
  const hitEl = el('rect', { class: 'hit', x: g.x - G.cell / 2, y: g.y - G.cell / 2, width: G.cell, height: G.cell }, gp);
  return { lab, hitEl };
}

function drawPin(svg, p, sigs, conflict) {
  const g = pinGeom(p.n);
  const net = netOf(model, p.n);
  const jtag = model.core.debug && JTAG_PINS[p.n];
  const cls = ['pin'];
  if (p.type !== 'io') cls.push('power');
  else if (jtag && !sigs.length) cls.push('jtag');
  sigs.forEach(s => cls.push('b-' + (s.inst ? s.inst.name : 'sys')));
  if (sigs.length) cls.push('used');
  if (net) cls.push('labeled');
  if (conflict) cls.push('conflict');
  const gp = el('g', { class: cls.join(' '), 'data-pin': p.n }, svg);
  if (G.array) {
    const { lab, hitEl } = drawBall(gp, p, g, sigs, conflict, net, jtag);
    pinEvents(gp, p, sigs, net, lab, hitEl);
    return;
  }

  //Ячейка вывода снаружи корпуса (цвет - банк), кружок в ней (цвет - группа блока, если вывод занят)
  const C = 16, out = G.pad + 2;
  let cx, cy, numA, labA;
  if (g.side === 'L') { cx = g.x - out / 2; cy = g.y; numA = { x: g.x + 5, y: g.y, a: 'start' }; labA = { x: g.x - out - 6, y: g.y, a: 'end' }; }
  if (g.side === 'R') { cx = g.x + out / 2; cy = g.y; numA = { x: g.x - 5, y: g.y, a: 'end' }; labA = { x: g.x + out + 6, y: g.y, a: 'start' }; }
  if (g.side === 'B') { cx = g.x; cy = g.y + out / 2; numA = { x: g.x, y: g.y - 5, a: 'start', rot: true }; labA = { x: g.x, y: g.y + out + 6, a: 'end', rot: true }; }
  if (g.side === 'T') { cx = g.x; cy = g.y - out / 2; numA = { x: g.x, y: g.y + 5, a: 'end', rot: true }; labA = { x: g.x, y: g.y - out - 6, a: 'start', rot: true }; }

  const cellFill = p.type === 'gnd' ? 'var(--gnd)' : p.type === 'pwr' ? 'var(--pwr)' : BANK_COLOR(p.bank);
  el('rect', { class: 'cell', x: cx - C / 2, y: cy - C / 2, width: C, height: C, rx: 2, fill: cellFill }, gp);
  if (p.type === 'io') {
    const mk = el('circle', { class: 'mark', cx, cy, r: 5 }, gp);
    if (sigs.length && !conflict) mk.style.fill = sigColor(sigs[0]);
    if (jtag && !sigs.length) mk.style.fill = 'var(--c-jtag)';
  } else {
    el('text', { class: 'sym', x: cx, y: cy, 'dominant-baseline': 'central' }, gp, p.type === 'gnd' ? '⏚' : 'V');
  }
  const txt = (a, cl, s) => {
    const t = el('text', { class: cl, x: a.x, y: a.y, 'text-anchor': a.a, 'dominant-baseline': 'central' }, gp, s);
    if (a.rot) t.setAttribute('transform', `rotate(-90 ${a.x} ${a.y})`);
    return t;
  };
  txt(numA, 'num', String(p.n));
  let label = net, free = false;
  if (!label) {
    if (p.type !== 'io') label = p.name;
    else if (jtag) label = 'JTAG ' + jtag;
    else { label = p.name; free = true; }
  }
  const lab = txt(labA, 'label' + (free ? ' free' : ''), label);

  //Невидимая область щелчка: ячейка + номер внутри корпуса
  const span = out + 22;
  const hit = g.side === 'L' ? { x: g.x - out, y: g.y - G.pitch / 2, width: span, height: G.pitch }
            : g.side === 'R' ? { x: g.x + out - span, y: g.y - G.pitch / 2, width: span, height: G.pitch }
            : g.side === 'B' ? { x: g.x - G.pitch / 2, y: g.y + out - span, width: G.pitch, height: span }
            :                  { x: g.x - G.pitch / 2, y: g.y - out, width: G.pitch, height: span };
  const hitEl = el('rect', Object.assign({ class: 'hit' }, hit), gp);
  pinEvents(gp, p, sigs, net, lab, hitEl);
}
//Подсказка и действия вывода микросхемы: двойной щелчок - диалог, щелчок - блок, перетаскивание, имя цепи
function pinEvents(gp, p, sigs, net, lab, hitEl) {
  const info = [`Вывод ${p.n} · ${p.name}`];
  if (p.bank != null) info.push(`банк ${p.bank}`);
  if (p.cfg) info.push(p.cfg);
  if (p.lvds) info.push('True LVDS');
  el('title', {}, gp, info.join(' · ') + (sigs.length ? '\n' + sigs.map(s => s.name).join(', ') : '') + (net ? `\nцепь: ${net}` : ''));
  if (p.type === 'io') {
    hitEl.addEventListener('dblclick', () => pinDialog(p.n));
    hitEl.addEventListener('click', () => {
      if (dragJustEnded) return;
      const s = sigs[0]; if (s && s.inst) select({ kind: 'inst', name: s.inst.name });
    });
    if (sigs.length || net) hitEl.addEventListener('pointerdown', e => startPinDrag(e, p.n));
    lab.addEventListener('dblclick', ev => { ev.stopPropagation(); inlineNetEdit(p.n, lab); });
  }
}
//Перетаскивание вывода: сигналы, имя цепи и стандарт I/O переходят на другой вывод (с занятым - обмен)
let drag = null, dragJustEnded = false;
function svgPoint(e) {
  const svg = document.getElementById('chip'), pt = svg.createSVGPoint();
  pt.x = e.clientX; pt.y = e.clientY;
  return pt.matrixTransform(svg.getScreenCTM().inverse());
}
function pinUnder(e) {
  const t = document.elementFromPoint(e.clientX, e.clientY);
  const g = t && t.closest && t.closest('#chip .pin');
  return g ? pinv(g.dataset.pin) : null;
}
const canDrop = n => PIN[n] && PIN[n].type === 'io' && !(model.core.debug && JTAG_PINS[n]);
function startPinDrag(e, from) {
  if (e.button !== 0) return;
  drag = { from, x: e.clientX, y: e.clientY, on: false, line: null, label: null, over: null };
  document.addEventListener('pointermove', dragMove);
  document.addEventListener('pointerup', dragEnd, { once: true });
}
function dragMove(e) {
  if (!drag) return;
  if (!drag.on) {
    if (Math.hypot(e.clientX - drag.x, e.clientY - drag.y) < 6) return;
    drag.on = true;
    document.body.classList.add('dragging');
    const svg = document.getElementById('chip'), g = pinGeom(drag.from);
    drag.line = el('line', { class: 'drag-line', x1: g.x, y1: g.y, x2: g.x, y2: g.y }, svg);
    drag.label = el('text', { class: 'drag-label' }, svg, netOf(model, drag.from) || ('вывод ' + drag.from));
  }
  const pt = svgPoint(e);
  drag.line.setAttribute('x2', pt.x); drag.line.setAttribute('y2', pt.y);
  drag.label.setAttribute('x', pt.x + 10); drag.label.setAttribute('y', pt.y - 8);
  const n = pinUnder(e);
  if (n !== drag.over) {
    document.querySelectorAll('#chip .pin.drop, #chip .pin.drop-bad').forEach(x => x.classList.remove('drop', 'drop-bad'));
    drag.over = n;
    const g = n != null && n !== drag.from && document.querySelector(`#chip .pin[data-pin="${n}"]`);
    if (g) g.classList.add(canDrop(n) ? 'drop' : 'drop-bad');
  }
}
function dragEnd(e) {
  document.removeEventListener('pointermove', dragMove);
  const d = drag; drag = null;
  if (!d || !d.on) return;
  document.body.classList.remove('dragging');
  d.line.remove(); d.label.remove();
  dragJustEnded = true; setTimeout(() => { dragJustEnded = false; }, 0);
  const to = pinUnder(e);
  if (to == null || to === d.from) { render(); return; }
  if (!canDrop(to)) { setStatus(`Вывод ${to} занят ${PIN[to] && PIN[to].type === 'io' ? 'JTAG' : 'питанием'} - перенос невозможен`, 'err'); render(); return; }
  swapPins(d.from, to);
}
function swapPins(a, b) {
  const all = signals(model), sa = all.filter(s => s.pin === a), sb = all.filter(s => s.pin === b);
  sa.forEach(s => setSignalPin(model, s, b));
  sb.forEach(s => setSignalPin(model, s, a));
  const pa = model.pins[a], pb = model.pins[b];
  delete model.pins[a]; delete model.pins[b];
  if (pa) model.pins[b] = pa;
  if (pb) model.pins[a] = pb;
  const what = (pa && pa.net) || sa.map(s => s.name).join(', ') || ('вывод ' + a);
  setStatus(sb.length || pb ? `Выводы ${a} и ${b} обменялись` : `${what}: вывод ${a} → ${b}`, 'ok');
  changed();
}

const memTxt = mm => mm ? (mm.type === 'bsram' ? `${mm.kb} КБ` : `${mm.synthWords * 4} Б`) : '?';

// --- Структура: процессор, шины bus_per и clk_per, периферия с внешними выводами ---
function drawStruct(svg, v) {
  const m = model, pll = pllOf(m), irqs = irqMap(m), core = m.core;
  const badPins = new Set(v.issues.filter(i => i.lvl === 'err' && i.pin != null).map(i => i.pin));
  const errInst = new Set(v.issues.filter(i => i.lvl === 'err' && i.inst).map(i => i.inst));
  const gBus = el('g', { class: 'buses' }, svg);       //Шины рисуются под блоками
  const fper = pll.errs.length ? '—' : fmt(sysclkHz(m) / 1e6) + ' МГц';

  // --- Такт и сброс ---
  const ck = { x: SG.sysX, y: SG.top, w: SG.sysW, h: 66 };
  const ckG = blockBox(svg, ck, 'PLL', 'var(--c-sys)', isSel({ kind: 'clock' }), errInst.has('clock'), () => select({ kind: 'clock' }), 'sys');
  el('text', { class: 'blk-ru', x: ck.x + 10, y: ck.y + 40 }, ckG, 'Такт и сброс');
  el('text', { class: 'blk-text', x: ck.x + 10, y: ck.y + 56 }, ckG, `rPLL ${pll.errs.length ? 'ошибка' : fmt(pll.fout) + ' МГц'} · кварц ${fmt(Number(m.clock.xtalMHz))} МГц`);
  leftPin(svg, ck.x, ck.y + 36, findSig('clk'), badPins);
  leftPin(svg, ck.x, ck.y + 54, findSig('rst'), badPins);

  // --- Процессор ---
  const sub = [
    ['CORE', `ядро RV32I${core.mExt ? 'M' : ''}, ${core.coreType === 'pipeline' ? 'конвейер' : 'однотактное'}`],
    ['IMEM', `память команд ${memTxt(core.imem)}`],
    ['DMEM', `память данных ${memTxt(core.dmem)}`],
    ['CLINT', 'машинный таймер'],
    ['PLIC', `прерывания, ${core.plicSources} ист.`],
    ['DEBUG', core.debug ? 'отладчик JTAG' : 'отладчик выключен'],
    ['BUS', 'шина bus_per'],
  ];
  const cpu = { x: SG.sysX, y: ck.y + ck.h + 34, w: SG.sysW, h: 30 + sub.length * 24 + 6 };
  const cpuG = blockBox(svg, cpu, 'CPU', 'var(--c-sys)', isSel({ kind: 'core' }), errInst.has('core'), () => select({ kind: 'core' }), null);
  sub.forEach(([t, d], i) => {
    const y = cpu.y + 30 + i * 24;
    el('rect', { class: 'sub', x: cpu.x + 8, y, width: cpu.w - 16, height: 20, rx: 4 }, cpuG);
    el('text', { class: 'sub-t', x: cpu.x + 15, y: y + 14 }, cpuG, t);
    el('text', { class: 'sub-d', x: cpu.x + cpu.w - 14, y: y + 14, 'text-anchor': 'end' }, cpuG, d);
  });
  if (core.debug) {
    const yd = cpu.y + 30 + 5 * 24 + 10;
    Object.entries(JTAG_PINS).forEach(([n, t], i) =>
      leftPin(svg, cpu.x, yd - 24 + i * 16, { id: 'jtag', pin: pinv(n), def: t, fixed: true }, new Set()));
  }
  el('path', { class: 'clk-line', d: `M${ck.x + ck.w / 2} ${ck.y + ck.h} V${cpu.y}` }, gBus);
  el('text', { class: 'bus-label clk', x: ck.x + ck.w / 2 + 6, y: ck.y + ck.h + 20 }, gBus, 'clk_core');

  // --- Периферия ---
  let y = SG.top;
  const per = m.periph.map(inst => {
    const rows = instRows(inst);
    const box = { x: SG.perX, y, w: SG.perW, h: 24 + 20 + Math.max(1, rows.length) * SG.row + 4 };
    y += box.h + SG.gap;
    return { inst, rows, box };
  });
  const addBox = { x: SG.perX, y, w: SG.perW, h: 34 };

  //Шина данных bus_per: из процессора к стволу и ветви к каждому устройству
  const busY = cpu.y + 30 + 6 * 24 + 10;
  const brY = b => b.y + 34;
  el('path', { class: 'bus-line', d: `M${cpu.x + cpu.w} ${busY} H${SG.busX}` }, gBus);
  if (per.length) {
    const ys = per.map(p => brY(p.box));
    el('path', { class: 'bus-line', d: `M${SG.busX} ${Math.min(busY, ...ys)} V${Math.max(busY, ...ys)}` }, gBus);
    per.forEach(p => el('path', { class: 'bus-line', d: `M${SG.busX} ${brY(p.box)} H${p.box.x}` }, gBus));
  }
  el('text', { class: 'bus-label', x: cpu.x + cpu.w + 4, y: busY - 6 }, gBus, 'bus_per');

  //Шина тактирования clk_per
  const clkY = ck.y + 22;
  const clkBot = per.length ? Math.max(...per.map(p => p.box.y + 12)) : clkY;
  el('path', { class: 'clk-line', d: `M${ck.x + ck.w} ${clkY} H${SG.clkX} V${clkBot}` }, gBus);
  per.forEach(p => el('path', { class: 'clk-line', d: `M${SG.clkX} ${p.box.y + 12} H${p.box.x}` }, gBus));
  const cl = el('text', { class: 'bus-label clk', x: ck.x + ck.w + 4, y: clkY - 5 }, gBus, 'clk_per');
  el('title', {}, cl, `Такт шины периферии clk_per: ${fper}`);

  per.forEach(p => drawPeriph(svg, p, irqs, badPins, errInst.has(p.inst.name)));

  const add = el('g', { class: 'add-block' }, svg);
  el('rect', { x: addBox.x, y: addBox.y, width: addBox.w, height: addBox.h, rx: 8 }, add);
  el('text', { x: addBox.x + addBox.w / 2, y: addBox.y + 22, 'text-anchor': 'middle' }, add, per.length ? '+ Добавить блок' : '+ Добавить первый блок');
  add.addEventListener('click', () => openLibrary());
  return Math.max(cpu.y + cpu.h, addBox.y + addBox.h) + SG.top;
}

//Блок схемы: рамка, шапка цвета группы с коротким латинским именем
function blockBox(svg, b, title, color, selected, bad, onClick, hlName) {
  const g = el('g', { class: 'blk' + (selected ? ' selected' : '') + (bad ? ' bad' : '') }, svg);
  el('rect', { class: 'blk-body', x: b.x, y: b.y, width: b.w, height: b.h, rx: 7, style: `stroke:${color}` }, g);
  el('path', { class: 'blk-head', d: `M${b.x} ${b.y + 22} V${b.y + 7} Q${b.x} ${b.y} ${b.x + 7} ${b.y} H${b.x + b.w - 7} Q${b.x + b.w} ${b.y} ${b.x + b.w} ${b.y + 7} V${b.y + 22} Z`, style: `fill:${color}` }, g);
  el('text', { class: 'blk-title', x: b.x + 9, y: b.y + 16 }, g, title);
  if (onClick) g.addEventListener('click', onClick);
  if (hlName) hoverOn(g, hlName);
  return g;
}

//Вывод слева от системного блока: номер в ячейке цвета банка (щелчок - выбор вывода) и имя цепи (щелчок - имя)
function leftPin(svg, x, y, sig, bad) {
  const pin = sig.pin;
  const g = el('g', { class: 'xpin' + (pin == null || bad.has(pin) ? ' missing' : '') + (sig.fixed ? ' small' : '') }, svg);
  el('path', { class: 'stub', d: `M${x - 22} ${y} H${x}` }, g);
  const p = PIN[pin];
  const cell = el('rect', { class: 'pcell', x: x - 54, y: y - 7.5, width: 32, height: 15, rx: 3, fill: p ? BANK_COLOR(p.bank) : 'var(--surface)' }, g);
  el('text', { class: 'pnum', x: x - 38, y: y + 4, 'text-anchor': 'middle' }, g, pin == null ? '+' : String(pin));
  const name = el('text', { class: 'pnet', x: x - 60, y: y + 4, 'text-anchor': 'end' }, g, (pin != null && netOf(model, pin)) || sig.def);
  if (p) el('title', {}, g, `Вывод ${pin} · ${p.name} · банк ${p.bank}`);
  if (sig.fixed) return;
  cell.classList.add('click');
  cell.addEventListener('click', () => pickPinInline(cell, sig));
  if (pin != null) { name.classList.add('click'); name.addEventListener('click', () => inlineNetEdit(pin, name)); }
}

//Строки выводов устройства на схеме: назначенные и «+» для добавления
function instRows(inst) {
  const rows = instSignals(inst).map(g => ({ kind: 'sig', key: g.key, label: g.label, pin: instPin(inst, g.key) }));
  if (inst.type === 'gpio' && inst.lines.length < 32) rows.push({ kind: 'add', key: 'newline', label: 'добавить линию' });
  if (inst.type === 'stim' && inst.out == null) rows.push({ kind: 'add', key: 'out', label: 'вывести ШИМ' });
  return rows;
}

function drawPeriph(svg, p, irqs, badPins, bad) {
  const { inst, rows, box } = p;
  const g = blockBox(svg, box, inst.name, instColor(inst), isSel({ kind: 'inst', name: inst.name }), bad,
                     () => select({ kind: 'inst', name: inst.name }), inst.name);
  el('text', { class: 'blk-ru', x: box.x + 9, y: box.y + 38 }, g, TYPES[inst.type].ru);
  if (irqs[inst.name]) el('text', { class: 'blk-irq', x: box.x + box.w - 9, y: box.y + 38, 'text-anchor': 'end' }, g, 'IRQ ' + irqText(irqs[inst.name]));
  if (inst.type === 'spiflash' && inst.fpgaConfig) el('text', { class: 'blk-irq', x: box.x + box.w - 9, y: box.y + 38, 'text-anchor': 'end' }, g, 'BOOT');
  const y0 = box.y + 44;
  rows.forEach((r, i) => {
    const y = y0 + i * SG.row + 10;
    const rg = el('g', { class: 'prow' + (r.kind === 'add' ? ' add' : '') }, svg);
    if (r.kind === 'sig') {
      el('text', { class: 'sig-l', x: box.x + box.w - 9, y: y + 4, 'text-anchor': 'end' }, g, r.label);
      rg.classList.toggle('missing', r.pin == null || badPins.has(r.pin));
      el('path', { class: 'stub', d: `M${box.x + box.w} ${y} H${SG.pinX - 16}` }, rg);
      const pp = PIN[r.pin];
      const cell = el('rect', { class: 'pcell click', x: SG.pinX - 16, y: y - 7.5, width: 32, height: 15, rx: 3, fill: pp ? BANK_COLOR(pp.bank) : 'var(--surface)' }, rg);
      el('text', { class: 'pnum', x: SG.pinX, y: y + 4, 'text-anchor': 'middle' }, rg, r.pin == null ? '+' : String(r.pin));
      const net = r.pin != null ? netOf(model, r.pin) : '';
      const sig = findSig(`${inst.name}.${r.key}`);
      cell.addEventListener('click', () => pickPinInline(cell, sig));
      const nt = el('text', { class: 'pnet' + (r.pin != null ? ' click' : ''), x: SG.pinX + 22, y: y + 4 }, rg, r.pin == null ? 'выбрать вывод' : (net || '—'));
      if (r.pin != null) nt.addEventListener('click', () => inlineNetEdit(r.pin, nt));
      if (net && inst.type === 'gpio' && NET_RE.test(net))
        el('text', { class: 'pcname', x: SG.pinX + 30 + net.length * 7.2, y: y + 4 }, rg, `${cName(net)}_PIN`);
      if (pp) el('title', {}, rg, `Вывод ${r.pin} · ${pp.name} · банк ${pp.bank}${net ? '\nцепь: ' + net : ''}\nщелчок по номеру - другой вывод, по имени - переименовать`);
    } else {
      el('path', { class: 'stub dashed', d: `M${box.x + box.w} ${y} H${SG.pinX - 9}` }, rg);
      el('circle', { class: 'plus-c', cx: SG.pinX, cy: y, r: 8 }, rg);
      el('text', { class: 'plus-t', x: SG.pinX, y: y + 4, 'text-anchor': 'middle' }, rg, '+');
      el('text', { class: 'pnet add', x: SG.pinX + 22, y: y + 4 }, rg, r.label);
      rg.addEventListener('click', () => {
        if (r.key === 'newline') pinPicker({ id: `${inst.name}.newline`, inst, key: 'newline', name: `${inst.name} IO${inst.lines.length}`, dir: 'inout', def: defNet(inst, 'line' + inst.lines.length) });
        else pinPicker({ id: `${inst.name}.${r.key}`, inst, key: r.key, name: `${inst.name} ${r.key.toUpperCase()}`, dir: 'output', def: defNet(inst, r.key) });
      });
    }
  });
}

//Выбор вывода прямо на схеме: список поверх ячейки
function pickPinInline(anchor, sig) {
  const rc = anchor.getBoundingClientRect();
  const s = document.createElement('select');
  s.className = 'inline-edit';
  s.innerHTML = pinOptions(sig.pin ?? null, sig.id, true);
  s.style.left = Math.max(4, rc.left - 2) + 'px';
  s.style.top = (rc.top - 3) + 'px';
  document.body.appendChild(s);
  s.focus();
  try { s.showPicker(); } catch (e) { /* открыть список нельзя - он уже в фокусе */ }
  let done = false;
  const finish = ok => {
    if (done) return; done = true;
    const val = s.value;
    s.remove();
    if (!ok || val === String(sig.pin ?? '')) return;
    movePin(sig, val);
    changed();
  };
  s.addEventListener('change', () => finish(true));
  s.addEventListener('blur', () => finish(false));
  s.addEventListener('keydown', e => { if (e.key === 'Escape') finish(false); if (e.key === 'Enter') finish(true); });
}

// --- Легенда, проверка, карта адресов, таблица выводов ---
function renderLegend() {
  const items = [];
  const banks = [...new Set(DEV.pins.filter(p => p.bank != null).map(p => p.bank))].sort();
  banks.forEach(b => items.push(`<span><i style="background:${BANK_COLOR(b)}"></i>банк ${b}</span>`));
  items.push(`<span><i style="background:var(--pwr)"></i>питание</span>`, `<span><i style="background:var(--gnd)"></i>земля</span>`);
  items.push(`<span><i class="round" style="background:var(--c-sys)"></i>системное</span>`);
  Object.values(CATS).forEach(c => items.push(`<span><i class="round" style="background:${c.color}"></i>${c.title}</span>`));
  items.push(`<span><i class="line"></i>шина bus_per</span>`, `<span><i class="line clk"></i>тактирование</span>`);
  document.getElementById('legend').innerHTML = items.join('');
}

function renderIssues(v) {
  const ul = document.getElementById('issues');
  const iss = v.issues;
  const nErr = iss.filter(i => i.lvl === 'err').length, nWarn = iss.length - nErr;
  const badge = document.getElementById('issueCount');
  badge.textContent = iss.length ? String(iss.length) : '✓';
  badge.className = 'badge' + (nErr ? ' err' : nWarn ? ' warn' : '');
  ul.innerHTML = iss.length ? '' : '<li class="ok">Ошибок нет, можно собирать</li>';
  iss.forEach(i => {
    const li = document.createElement('li');
    li.className = i.lvl;
    li.textContent = i.text;
    if (i.pin != null) { li.dataset.pin = i.pin; li.addEventListener('click', () => flashPin(i.pin)); }
    else if (i.inst) {
      li.dataset.pin = '';
      li.addEventListener('click', () => select(i.inst === 'clock' ? { kind: 'clock' } : i.inst === 'core' ? { kind: 'core' } : { kind: 'inst', name: i.inst }));
    }
    ul.appendChild(li);
  });
}

function renderAddressMap() {
  const am = addressMap(model);
  const t = document.getElementById('amap');
  t.innerHTML = am.rows.map(r => `<tr${r.inst ? ` data-inst="${esc(r.name)}" class="click${isSel({ kind: 'inst', name: r.name }) ? ' sel' : ''}"` : ''}>
      <td class="addr">${r.slot == null ? '—' : hexSlot(r.slot)}</td>
      <td><span class="sw" style="background:${r.color}"></span>${esc(r.name)}${r.fixed ? '' : (r.auto ? ' <span class="muted">авто</span>' : '')}</td>
      <td class="muted">${esc(r.note)}</td></tr>`).join('');
}

//Нижняя таблица - как «I/O Constraints» во FloorPlanner
function renderIoTable(v) {
  const sigs = signals(model).filter(s => s.pin != null).sort((a, b) => pinCmp(a.pin, b.pin));
  const d = model.ioDefaults;
  const sel_ = (pin, key, list, cur, def) => `<select data-pin="${pin}" data-key="${key}">` +
    `<option value="">${def}*</option>` + list.map(x => `<option${x === cur ? ' selected' : ''}>${x}</option>`).join('') + '</select>';
  const bad = new Set(v.issues.filter(i => i.lvl === 'err' && i.pin != null).map(i => i.pin));
  const dirRu = { input: 'вход', output: 'выход', inout: 'вход/выход' };
  const rows = sigs.map(s => {
    const p = PIN[s.pin] || {}, a = model.pins[s.pin] || {};
    return `<tr data-pin="${s.pin}" class="${bad.has(s.pin) ? 'bad' : ''}">
      <td class="mono">${esc(netOf(model, s.pin) || '—')}</td>
      <td><span class="dot" style="background:${sigColor(s)}"></span>${esc(s.name)}</td>
      <td>${dirRu[s.dir]}</td>
      <td class="mono">${s.pin}</td><td class="mono">${esc(p.name || '?')}</td><td>${p.bank ?? ''}</td>
      <td>${sel_(s.pin, 'ioType', IO_TYPES, a.ioType, bankDefault(model, s.pin, 'ioType'))}</td>
      <td>${s.dir === 'input' ? '<span class="muted">—</span>' : sel_(s.pin, 'drive', DRIVES, a.drive, d.drive)}</td>
      <td>${sel_(s.pin, 'pull', PULLS, a.pull, d.pull)}</td>
      <td>${sel_(s.pin, 'vccio', VCCIOS, a.vccio, bankDefault(model, s.pin, 'vccio'))}</td></tr>`;
  }).join('');
  document.getElementById('iotab').innerHTML = `<tr><th>Порт (цепь)</th><th>Сигнал</th><th>Направление</th><th>Вывод</th>
    <th>Площадка</th><th>Банк</th><th>IO_TYPE</th><th>DRIVE</th><th>PULL_MODE</th><th>BANK_VCCIO</th></tr>` + rows;
  document.getElementById('ioCount').textContent = `· ${sigs.length} · * - значение по умолчанию`;
  document.querySelectorAll('#iotab select').forEach(se => se.addEventListener('change', () => {
    const n = pinv(se.dataset.pin), np = model.pins[n] || {};
    if (se.value) np[se.dataset.key] = se.value; else delete np[se.dataset.key];
    model.pins[n] = np;
    changed();
  }));
  document.querySelectorAll('#iotab tr[data-pin]').forEach(tr => {
    tr.addEventListener('click', e => { if (e.target.tagName !== 'SELECT') flashPin(pinv(tr.dataset.pin)); });
    tr.addEventListener('dblclick', e => { if (e.target.tagName !== 'SELECT') pinDialog(pinv(tr.dataset.pin)); });
  });
}

function flashPin(n) {
  const g = document.querySelector(`#chip .pin[data-pin="${n}"]`);
  if (!g) return;
  g.classList.remove('flash'); void g.getBoundingClientRect(); g.classList.add('flash');
  g.scrollIntoView({ block: 'center', inline: 'center', behavior: 'smooth' });
}

// --- Ресурсы ПЛИС (правый верхний угол): занято / всего ---
//Логика, регистры, DSP и Fmax - по последней сборке (impl/socgen/resources.json платы); BSRAM, выводы, PLL - по конфигурации
let lastRes = null;
const ICONS = {
  lut: '<rect x="1.5" y="1.5" width="5.5" height="5.5" rx="1"/><rect x="9" y="1.5" width="5.5" height="5.5" rx="1"/><rect x="1.5" y="9" width="5.5" height="5.5" rx="1"/><rect x="9" y="9" width="5.5" height="5.5" rx="1"/>',
  reg: '<rect x="2.5" y="1.5" width="11" height="13" rx="1.5"/><path d="M2.5 9.5 5.5 11.5 2.5 13.5"/><path d="M6 5h4M8 3v4"/>',
  bsram: '<rect x="2" y="2" width="12" height="3.2" rx=".8"/><rect x="2" y="6.4" width="12" height="3.2" rx=".8"/><rect x="2" y="10.8" width="12" height="3.2" rx=".8"/>',
  dsp: '<rect x="1.5" y="1.5" width="13" height="13" rx="2"/><path d="M5 5l6 6M11 5l-6 6"/>',
  io: '<rect x="3" y="2" width="10" height="7" rx="1.2"/><path d="M5.5 9v5M8 9v5M10.5 9v5"/>',
  pll: '<path d="M1 8c1.5-5 3.5-5 5 0s3.5 5 5 0 2.5-3 4-3"/>',
  fmax: '<circle cx="8" cy="8" r="6.5"/><path d="M8 4v4l3 2"/>',
};
function renderResources() {
  const box = document.getElementById('res');
  const r = (lastRes && lastRes.items) || {};
  const when = lastRes ? `по сборке ${lastRes.time} (${lastRes.toolchain === 'apicula' ? 'apicula' : 'Gowin EDA'})` : '';
  const ioUsed = signals(model).filter(s => s.pin != null).length + (model.core.debug ? 4 : 0);
  const items = [
    { k: 'lut', name: 'Логические ячейки (LUT4, ALU, ROM16)', v: r.lut, src: when },
    { k: 'reg', name: 'Регистры (триггеры)', v: r.reg, src: when },
    { k: 'bsram', name: 'Блоки памяти BSRAM (2 кБайт каждый): IMEM, DMEM, шрифты TM1638', v: [bsramBlocks(model), BSRAM_TOTAL], src: 'по конфигурации' },
    { k: 'dsp', name: 'Блоки DSP (умножители MULT18X18)', v: r.dsp, src: when },
    { k: 'io', name: 'Выводы I/O (с выводами JTAG отладчика)', v: [ioUsed, DEV.resources.io], src: 'по конфигурации' },
    { k: 'pll', name: 'Блоки rPLL', v: [1, DEV.resources.pll], src: 'по конфигурации' },
  ];
  let h = items.map(it => {
    const has = Array.isArray(it.v) && it.v[1] > 0;
    const used = has ? it.v[0] : 0, total = has ? it.v[1] : 0, free = total - used, pct = has ? used / total : 0;
    const cls = !has ? 'na' : pct > 1 ? 'bad' : pct > 0.9 ? 'bad' : pct > 0.75 ? 'warn' : '';
    const tip = has ? `${it.name}\nзанято ${used} из ${total} (${Math.round(pct * 100)} %, свободно ${free})\n${it.src}`
                    : `${it.name}\nпоявится после сборки`;
    return `<span class="res-item ${cls}" title="${esc(tip)}"><svg viewBox="0 0 16 16">${ICONS[it.k]}</svg>` +
      `<b>${has ? `${used}/${total}` : '—'}</b><i style="width:${Math.min(100, Math.round(pct * 100))}%"></i></span>`;
  }).join('');
  const fmax = lastRes && lastRes.fmax ? lastRes.fmax.clk_core : null;
  if (fmax != null) {
    const need = pllOf(model).fout, bad = fmax < need;
    h += `<span class="res-item ${bad ? 'bad' : ''}" title="${esc(`Fmax ядра clk_core ${fmax.toFixed(1)} МГц при рабочих ${fmt(need)} МГц\n${when}`)}">` +
      `<svg viewBox="0 0 16 16">${ICONS.fmax}</svg><b>${fmax.toFixed(1)}</b></span>`;
  }
  box.innerHTML = h;
}

// --- Ход сборки (строки @@PROGRESS генератора передаёт плагин) ---
let building = false, buildT0 = 0, buildTimer = 0, progPct = 0, progText = '';
const mmss = t => `${Math.floor(t / 60)}:${String(t % 60).padStart(2, '0')}`;
function drawProgress() {
  const p = document.getElementById('prog');
  p.querySelector('.prog-bar').style.width = Math.max(0, Math.min(100, progPct)) + '%';
  p.querySelector('span').textContent = `${Math.round(progPct)} % · ${progText} · ${mmss(Math.round((Date.now() - buildT0) / 1000))}`;
}
//Режим сборки: кнопка «Собрать» неактивна, вместо ресурсов ПЛИС - шкала хода и время сборки
function setBuilding(on) {
  building = on;
  const b = document.getElementById('build');
  b.disabled = on;
  b.classList.toggle('busy', on);
  document.getElementById('prog').hidden = !on;
  document.getElementById('res').hidden = on;
  clearInterval(buildTimer);
  if (on) { buildT0 = Date.now(); progPct = 0; progText = 'Подготовка'; drawProgress(); buildTimer = setInterval(drawProgress, 1000); }
}
function showProgress(pct, text) {
  if (pct < 0) { setBuilding(false); return; }
  if (!building) setBuilding(true);
  progPct = pct; progText = text;
  drawProgress();
}

// --- Масштаб ---
function applyZoom() {
  const svg = document.getElementById('chip'), c = document.getElementById('canvas');
  if (!svgW) return;
  const s = zoom || Math.max(0.35, Math.min(1.2, (c.clientWidth - 16) / svgW));
  svg.setAttribute('width', Math.round(svgW * s));
  svg.setAttribute('height', Math.round(svgH * s));
}
function currentScale() { return document.getElementById('chip').getBoundingClientRect().width / svgW; }

// ============================================================================================
// Редактирование
// ============================================================================================
function changed() {
  dirty = true;
  host('dirty');
  //Фокус ввода переживает перерисовку панели настроек: элемент находится по имени
  const a = document.activeElement, name = a && a.name && a.closest && a.closest('#settings') ? a.name : null;
  render();
  if (name) { const e = document.querySelector(`#settings [name="${CSS.escape(name)}"]`); if (e) e.focus(); }
}
const isSel = s => !!sel && sel.kind === s.kind && (s.kind !== 'inst' || sel.name === s.name);
function select(s) { sel = s; render(); document.querySelector('.side').scrollTop = 0; }

function inlineNetEdit(n, labEl) {
  const rc = labEl.getBoundingClientRect();
  const inp = document.createElement('input');
  inp.className = 'inline-edit net';
  inp.value = netOf(model, n);
  inp.placeholder = 'ИМЯ_ЦЕПИ';
  inp.style.left = Math.max(4, rc.left - 4) + 'px';
  inp.style.top = (rc.top + rc.height / 2 - 11) + 'px';
  document.body.appendChild(inp);
  inp.focus(); inp.select();
  let done = false;
  const finish = ok => {
    if (done) return; done = true;
    if (ok && inp.value.trim() !== netOf(model, n)) { setNet(model, n, inp.value); changed(); }
    inp.remove();
  };
  inp.addEventListener('keydown', e => { if (e.key === 'Enter') finish(true); if (e.key === 'Escape') finish(false); });
  inp.addEventListener('blur', () => finish(true));
}

// --- Общий диалог ---
let dlgApply = null;
function openDialog(title, color, bodyHtml, onApply, onOpen) {
  const d = document.getElementById('dlg');
  document.getElementById('dlgTitle').innerHTML = (color ? `<span class="dot" style="display:inline-block;width:12px;height:12px;border-radius:3px;background:${color}"></span>` : '') + esc(title);
  document.getElementById('dlgBody').innerHTML = bodyHtml;
  document.getElementById('dlgOk').style.display = onApply ? '' : 'none';
  dlgApply = onApply;
  d.returnValue = '';
  if (onOpen) onOpen(document.getElementById('dlgBody'));
  d.showModal();
}
//Enter в поле диалога - «Применить» (первая кнопка формы - «Отмена»)
document.getElementById('dlgForm').addEventListener('keydown', e => {
  if (e.key === 'Enter' && e.target.tagName === 'INPUT' && dlgApply) { e.preventDefault(); document.getElementById('dlg').close('ok'); }
});
document.getElementById('dlg').addEventListener('close', () => {
  const d = document.getElementById('dlg');
  if (d.returnValue === 'ok' && dlgApply) { dlgApply(document.getElementById('dlgBody')); changed(); }
  dlgApply = null;
});

//Список выводов для выбора: занятые подписаны, выводы JTAG при отладчике недоступны
function pinOptions(selected, forSigId, freeFirst) {
  const owner = new Map();
  signals(model).forEach(s => { if (s.pin != null && s.id !== forSigId) owner.set(s.pin, s.name); });
  const list = freeFirst ? [...IO_PINS].sort((a, b) => (owner.has(a) - owner.has(b)) || pinCmp(a, b)) : IO_PINS;
  let h = `<option value="">— не подключён —</option>`;
  for (const n of list) {
    const p = PIN[n];
    const jt = model.core.debug && JTAG_PINS[n];
    const who = owner.get(n), net = netOf(model, n);
    const lbl = `${n} · ${p.name} · банк ${p.bank}${p.cfg ? ' · ' + p.cfg : ''}${jt ? ' (JTAG)' : ''}${who ? '  ← ' + who : net ? '  «' + net + '»' : ''}`;
    h += `<option value="${n}"${n === selected ? ' selected' : ''}${jt ? ' disabled' : ''}>${esc(lbl)}</option>`;
  }
  return h;
}

//Назначение вывода сигналу или новой линии GPIO: вывод и имя цепи
function pinPicker(sig) {
  openDialog(`${sig.name}: вывод`, sig.inst ? instColor(sig.inst) : 'var(--c-sys)', `
    <div class="form-grid">
      <label>Вывод</label><select name="pin">${pinOptions(sig.pin ?? null, sig.id, true)}</select>
      <label>Имя цепи</label><input type="text" class="mono net" name="net" placeholder="${esc(sig.def)}">
    </div>
    <p class="note">Свободные выводы - в начале списка. Имя цепи (заглавными) - имя порта в top.sv и riscv.cst${sig.inst && sig.inst.type === 'gpio' ?
      ' и define в Си: цепь LED3 - LED3_PIN, LED3_PORT в soc.h' : ''}.</p>`,
    body => {
      const pin = body.querySelector('[name=pin]').value;
      if (pin === '') return;
      const n = pinv(pin), net = body.querySelector('[name=net]').value.trim();
      if (sig.key === 'newline') { sig.inst.lines.push(n); }
      else setSignalPin(model, sig, n);
      if (net) setNet(model, n, net); else ensureNet(model, { pin: n, def: sig.def });
    },
    body => {
      const s = body.querySelector('[name=pin]'), net = body.querySelector('[name=net]');
      s.addEventListener('change', () => { net.value = s.value ? netOf(model, pinv(s.value)) : ''; });
    });
}

// --- Диалог вывода ---
function pinDialog(n) {
  const p = PIN[n];
  const sigs = signals(model);
  const cur = sigs.filter(s => s.pin === n);
  const pa = model.pins[n] || {};
  const opt = (list, v, def) => `<option value=""${!v ? ' selected' : ''}>по умолчанию (${def})</option>` +
    list.map(x => `<option${x === v ? ' selected' : ''}>${x}</option>`).join('');
  const sigOpts = `<option value="">— не назначен —</option>` + sigs.map(s =>
    `<option value="${esc(s.id)}"${cur.length && cur[0].id === s.id ? ' selected' : ''}>${esc(s.name)}${s.pin != null && s.pin !== n ? ' (сейчас ' + s.pin + ')' : ''}</option>`).join('');
  const info = [`<span>${p.name}</span>`, `<span>банк ${p.bank}</span>`];
  if (p.cfg) info.push(`<span>${esc(p.cfg)}</span>`);
  if (p.diff) info.push(`<span>${p.diff === 'P' ? 'плюс' : 'минус'} пары с ${p.pair}</span>`);
  if (p.lvds) info.push('<span>True LVDS</span>');
  const d = { ioType: bankDefault(model, n, 'ioType'), pull: bankDefault(model, n, 'pull'),
              drive: bankDefault(model, n, 'drive'), vccio: bankDefault(model, n, 'vccio') };
  const gpioSig = cur.find(s => s.inst && s.inst.type === 'gpio');
  openDialog(`Вывод ${n}`, cur.length ? sigColor(cur[0]) : null, `
    <div class="pininfo">${info.join('')}</div>
    <div class="form-grid">
      <label>Сигнал</label><select name="sig">${sigOpts}</select>
      <label>Имя цепи</label><input type="text" class="mono net" name="net" value="${esc(netOf(model, n))}" placeholder="ИМЯ_ЦЕПИ">
      <label>IO_TYPE</label><select name="ioType">${opt(IO_TYPES, pa.ioType, d.ioType)}</select>
      <label>PULL_MODE</label><select name="pull">${opt(PULLS, pa.pull, d.pull)}</select>
      <label>DRIVE, мА</label><select name="drive">${opt(DRIVES, pa.drive, d.drive)}</select>
      <label>BANK_VCCIO, В</label><select name="vccio">${opt(VCCIOS, pa.vccio, d.vccio)}</select>
    </div>
    ${cur.length > 1 ? `<p class="note" style="color:var(--error)">На вывод назначено несколько сигналов: ${cur.map(s => esc(s.name)).join(', ')}</p>` : ''}
    ${gpioSig && netOf(model, n) ? `<p class="note">В Си (soc.h): <code>${esc(cName(netOf(model, n)))}_PIN</code>, <code>${esc(cName(netOf(model, n)))}_PORT</code> -
      например <code>GPIO_WRITE(${esc(cName(netOf(model, n)))}, GPIO_PIN_SET)</code>.</p>` : ''}
    <p class="note">Имя цепи без сигнала - просто подпись, в riscv.cst она не попадает.</p>`,
    body => {
      const q = name => body.querySelector(`[name=${name}]`);
      const sigId = q('sig').value;
      //Снять с вывода прежние сигналы, кроме выбранного
      cur.forEach(s => { if (s.id !== sigId) setSignalPin(model, s, null); });
      const s = sigs.find(x => x.id === sigId);
      if (s) setSignalPin(model, s, n);
      setNet(model, n, q('net').value);
      if (s) ensureNet(model, Object.assign({}, s, { pin: n }));
      //Пустые линии GPIO (вывод снят) удаляются
      for (const inst of insts(model, 'gpio')) inst.lines = inst.lines.filter(x => x != null);
      const np = model.pins[n] || {};
      for (const k of ['ioType', 'pull', 'drive', 'vccio']) { const v = q(k).value; if (v) np[k] = v; else delete np[k]; }
      if (Object.keys(np).length) model.pins[n] = np; else delete model.pins[n];
    });
}

function ioDefaultsDialog() {
  const d = model.ioDefaults;
  const KEYS = [['ioType', IO_TYPES], ['pull', PULLS], ['drive', DRIVES], ['vccio', VCCIOS]];
  const banks = [...new Set(DEV.pins.filter(p => p.type === 'io').map(p => String(p.bank)))].sort();
  const sel_ = (name, list, v, inherit) => `<select name="${name}">` +
    (inherit ? `<option value=""${!v ? ' selected' : ''}>общие</option>` : '') +
    list.map(x => `<option${x === v ? ' selected' : ''}>${x}</option>`).join('') + `</select>`;
  const row = (title, pre, src, inherit, color) => `<tr><td>${color ? `<span class="dot" style="display:inline-block;width:10px;height:10px;border-radius:2px;background:${color}"></span> ` : ''}${title}</td>` +
    KEYS.map(([k, list]) => `<td>${sel_(pre + k, list, src[k], inherit)}</td>`).join('') + '</tr>';
  openDialog('Стандарты I/O по умолчанию', null, `
    <table class="sig-table"><tr><th></th><th>IO_TYPE</th><th>PULL_MODE</th><th>DRIVE, мА</th><th>BANK_VCCIO, В</th></tr>
      ${row('Общие', 'd_', d, false, null)}
      ${banks.map(bk => row('Банк ' + bk, `b${bk}_`, model.banks[bk] || {}, true, BANK_COLOR(bk))).join('')}
    </table>
    <p class="note">Порядок: собственные настройки вывода → настройки банка → общие. Напряжение VCCIO банка задаёт
    плата (Tang Nano 9K: банки 0–2 - 3,3 В, банк 3 - 1,8 В; Tang Primer 20K: банки 0–3 и 7 - 3,3 В, 4–6 - 1,5 В под DDR3):
    IO_TYPE выводов банка должен ему соответствовать,
    иначе Gowin EDA остановит размещение. DRIVE пишется только для выходов.</p>`,
    body => {
      for (const [k] of KEYS) d[k] = body.querySelector(`[name=d_${k}]`).value;
      for (const bk of banks) {
        const bset = {};
        for (const [k] of KEYS) { const v = body.querySelector(`[name=b${bk}_${k}]`).value; if (v) bset[k] = v; }
        if (Object.keys(bset).length) model.banks[bk] = bset; else delete model.banks[bk];
      }
    });
}

// ============================================================================================
// Панель настроек справа
// ============================================================================================
const opts = (list, v) => list.map(([val, txt]) => `<option value="${esc(val)}"${String(val) === String(v) ? ' selected' : ''}>${esc(txt)}</option>`).join('');

function renderSettings(v) {
  const box = document.getElementById('settings');
  if (sel && sel.kind === 'inst' && !instByName(sel.name)) sel = null;
  if (!sel) { box.innerHTML = hintsHtml(); return; }
  if (sel.kind === 'clock') { box.innerHTML = clockForm(); wireClockForm(box); return; }
  if (sel.kind === 'core') { box.innerHTML = coreForm(); wireCoreForm(box); return; }
  const inst = instByName(sel.name);
  box.innerHTML = instForm(inst, v);
  wireInstForm(box, inst);
}

function panelHead(title, sub, color) {
  return `<div class="pane-head"><span class="dot" style="background:${color}"></span><div><b>${esc(title)}</b>` +
    `<div class="muted">${esc(sub)}</div></div><button type="button" class="close" data-act="close" title="Закрыть - к карте адресов">✕</button></div>`;
}

function hintsHtml() {
  return `<h2>Подсказки</h2>
    <ul class="hints">
      <li>Щелчок по блоку на схеме открывает здесь его настройки; наведение подсвечивает его выводы на микросхеме.</li>
      <li>«+ Добавить блок» - периферия из библиотеки, сколько нужно; второй блок типа: UART0, UART1.</li>
      <li>На схеме: щелчок по номеру вывода - выбрать другой вывод, по имени цепи - переименовать; «+» - добавить вывод.</li>
      <li>Двойной щелчок по выводу микросхемы - сигнал и стандарт I/O; по корпусу - снова видны все выводы.</li>
      <li>Вывод микросхемы можно перетащить на другой: сигнал, имя цепи и стандарт I/O переходят на него (с занятым выводом - обмен).</li>
      <li>Имя цепи - имя порта ПЛИС и define в Си, заглавными: <code>LED3</code> → <code>LED3_PIN</code>, <code>LED3_PORT</code>.</li>
    </ul>`;
}

//Строки «сигнал - вывод - имя цепи» в панели (изменения применяются сразу)
function pinRowsHtml(inst, rows, removable) {
  if (!rows.length) return '';
  return `<table class="sig-table"><tr><th style="width:52px">Порт</th><th>Вывод</th><th style="width:124px">Имя цепи</th>${removable ? '<th></th>' : ''}</tr>` +
    rows.map(r => {
      const pin = instPin(inst, r.key);
      const net = pin != null ? netOf(model, pin) : '';
      return `<tr><td>${esc(r.label)}</td>
        <td><select name="pin_${r.key}" data-key="${r.key}">${pinOptions(pin ?? null, `${inst.name}.${r.key}`, false)}</select></td>
        <td><input type="text" class="mono net" name="net_${r.key}" data-key="${r.key}" value="${esc(net)}" ${pin == null ? 'disabled' : ''}
             placeholder="${esc(defNet(inst, r.key))}"></td>
        ${removable ? `<td><button type="button" class="mini" data-act="delline" data-key="${r.key}" title="Удалить линию">✕</button></td>` : ''}</tr>`;
    }).join('') + '</table>';
}

function instForm(inst, v) {
  const t = TYPES[inst.type], am = addressMap(model), irqs = irqMap(model);
  const auto = parseBase(inst.base) === null;
  const nameErr = v.issues.find(i => i.inst === inst.name && /^Имя/.test(i.text));
  let h = panelHead(inst.name, `${t.title} · ${CATS[t.cat].title}`, instColor(inst));
  h += `<div class="form-grid pane">
    <label>Имя</label><input type="text" class="mono${nameErr ? ' bad' : ''}" name="name" value="${esc(inst.name)}" title="Имя в прошивке (указатель ${esc(inst.name)}, ${esc(inst.name)}_BASE) и в top.sv (${esc(hdl(inst))})">
    <label>Адрес регистров</label><div><select name="baseMode">${opts([['auto', 'авто'], ['manual', 'вручную']], auto ? 'auto' : 'manual')}</select>
      <input type="text" class="mono" name="base" style="width:116px" value="${auto ? (am.baseOf(inst.name) == null ? '' : hexSlot(am.baseOf(inst.name))) : esc(inst.base)}" ${auto ? 'disabled' : ''}></div>`;
  if (t.irq) h += `<label>Прерывание</label><div><select name="irq">${opts(Object.entries(IRQ_ROUTES), inst.irq || 'plic')}</select>
      <span class="muted"> ${irqText(irqs[inst.name])}</span></div>`;
  if (inst.type === 'stim') h += `<label>Разрядность</label><select name="width">${opts([[16, '16 бит'], [32, '32 бита']], inst.width)}</select>`;
  if (inst.type === 'spiflash') {
    const fi = flashInfo(model, inst), pe = pllOf(model).errs.length;
    const divs = []; for (let d = 0; d <= 7; d++) divs.push([d, pe ? `DIV ${d}` : `${fmt(sysclkHz(model) / (2 * (d + 1)) / 1e6)} МГц (DIV ${d})`]);
    if (fi.div > 7) divs.push([fi.div, `DIV ${fi.div}`]);
    h += `<label>Объём флеш</label><select name="sizeMB">${opts(FLASH_MB.map(x => [x, x + ' МБайт']), inst.sizeMB)}</select>
      <label>Частота SCK</label><select name="div">${opts(divs, inst.div)}</select>
      <label>Конфигурация и программа</label><select name="fpgaConfig">${opts([['0', DEV.embeddedFlash ? 'в SRAM или встроенной flash' : 'в SRAM'], ['1', 'в этой флеш, загрузка по MSPI']], fi.fpgaConfig ? '1' : '0')}</select>
      <label>Адрес образа</label><input type="text" class="mono" name="bootAddr" style="width:116px" value="${esc(inst.bootAddr)}" ${fi.boot ? '' : 'disabled'}>
      <div class="full readout">${fi.fpgaConfig ? `ПЛИС: <b>0x000000</b>.. · ` : ''}${fi.boot ? `образ: <b>${hex6(fi.bootAddr)}</b>..${hex6(fi.bootAddr + BOOT_REGION - 1)} · ` : ''}свободно: <b>${hex6(fi.user)}</b>, ${Math.round(fi.userSize / 1024)} кБайт</div>`;
  }
  if (inst.type === 'sifu') {
    const si = sifuInfo(model, inst), pe = pllOf(model).errs.length;
    const bad = si.alphaMax < 0 || si.alphaMaxDeg < 120 || si.half >= 8192;
    h += `<label>Частота пилы, кГц</label><div><input type="number" name="sawKHz" min="50" max="2000" step="any" value="${inst.sawHz / 1000}" style="width:90px"></div>
      <label>Сдвиг DELAY, тиков</label><input type="number" name="delayTicks" min="0" max="4095" value="${inst.delayTicks}" style="width:90px"
        title="DELAY_RC_COMPENSATION: при ALPHA = 0 импульс - в точке естественной коммутации (на стенде - 400 при 500 кГц)">
      <label>Импульс, тиков</label><input type="number" name="pulseTicks" min="1" max="4095" value="${inst.pulseTicks}" style="width:90px">
      <label>Имитатор сети</label><select name="sim" title="Сигналы оптронов NSB внутри блока (CR.SIM) - проверка без силовой части, около 130 ячеек">${opts([['1', 'есть'], ['0', 'нет']], inst.sim === false ? '0' : '1')}</select>
      <div class="full readout">${pe ? '<span class="bad">нет частоты rPLL</span>' :
        `DIV = <b>${si.div}</b> · тик <b>${fmt(si.saw / 1000)} кГц</b> · полупериод 50 Гц - <b>${Math.round(si.half)}</b> тиков<br>
         DELAY ${fmt(si.delayDeg)}°, импульс ${fmt(si.pulseUs)} мкс (${fmt(si.pulseDeg)}°) · угол до <b class="${bad ? 'bad' : 'good'}">${fmt(si.alphaMaxDeg)}°</b> (ALPHA ≤ ${si.alphaMax})`}</div>`;
  }
  if (inst.type === 'uart') {
    const u = uartDiv(model, inst), pe = pllOf(model).errs.length;
    const bad = u.div < 7 || u.div > 0xFFFF || u.err > 2;
    h += `<label>Скорость, бит/с</label><div><input type="number" name="baud" list="uartBauds" min="300" max="3000000" value="${inst.baud}" style="width:110px">
        <datalist id="uartBauds">${UART_BAUDS.map(x => `<option value="${x}">`).join('')}</datalist></div>
      <label>Чётность</label><select name="parity">${opts(Object.entries(UART_PARITY), inst.parity)}</select>
      <label>Стоп-битов</label><select name="stop">${opts([[1, '1'], [2, '2']], inst.stop)}</select>
      <label>Глубина FIFO</label><select name="fifo">${opts(FIFO_DEPTHS.map(x => [x, x + ' байт']), inst.fifo)}</select>
      <div class="full readout">${pe ? '<span class="bad">нет частоты rPLL</span>' :
        `DIV = <b>${u.div}</b> · фактически <b class="${bad ? 'bad' : 'good'}">${Math.round(u.real)} бит/с</b> (ошибка ${u.err.toFixed(2)} %)`}</div>`;
  }
  h += `</div><h3 class="pane-sub">Выводы</h3>`;
  const rows = instSignals(inst).map(g => ({ key: g.key, label: g.label }));
  if (inst.type === 'gpio') {
    h += pinRowsHtml(inst, rows, true) +
      `<button type="button" data-act="addline"${inst.lines.length >= 32 ? ' disabled' : ''}>+ Добавить линию</button>
       <p class="note">IO0 - младший разряд регистров MODE, OUT, IN. Имя цепи - define в Си: <code>LED3</code> → <code>LED3_PIN</code>,
       <code>LED3_PORT</code>, <code>GPIO_WRITE(LED3, ...)</code>; шина <code>LED[…]</code> → <code>LED_MSK</code>, <code>LED_POS</code>.</p>`;
  } else if (inst.type === 'stim') {
    h += inst.out == null
      ? `<button type="button" data-act="addout">+ Вывести ШИМ на вывод</button><p class="note">Без вывода таймер работает только на прерывание.</p>`
      : pinRowsHtml(inst, rows, false) + `<button type="button" data-act="delout">Не выводить ШИМ</button>`;
  } else {
    h += pinRowsHtml(inst, rows, false);
  }
  if (inst.type === 'uart') h += `<p class="note">Скорость, чётность и стоп-биты - значения после сброса (параметры uart_top и ${esc(inst.name)}_BAUD...
    в soc.h); прошивка может сменить их регистрами. UART программатора платы: Tang Nano 9K (BL702) - выводы 17 (TX) и 18 (RX),
    Tang Primer 20K (BL616 на Dock) - M11 (TX) и T13 (RX).</p>`;
  if (inst.type === 'tm1638') h += `<p class="note">Знакогенератор занимает 1 блок BSRAM; делители интерфейса считаются от частоты шины.</p>`;
  if (inst.type === 'sifu') h += `<p class="note">Входы AB…AC - выходы платы синхронизации NSB (OUT_AB…OUT_AC, 0 - оптрон открыт). Высокий уровень NSB -
    около 1,8 В (делитель 47k/27k от 5 В): на Tang Nano 9K - банк 3 (1,8 В, выводы 79–86), для банков 3,3 В нужен другой делитель NSB.
    Выходы VS1…VS6 - на драйверы тиристоров в порядке включения: VS1, VS3, VS5 - катодная группа фаз A, B, C; VS4, VS6, VS2 - анодная.
    Частота пилы, DELAY и импульс - значения после сброса (${esc(inst.name)}_DIV_DEFAULT... в soc.h), прошивка меняет их регистрами.</p>`;
  if (inst.type === 'spiflash') h += `<p class="note">Конфигурация и программа хранятся одним из способов. <b>SRAM</b> («riscv FPGA SRAM»)
    ${DEV.embeddedFlash ? 'и <b>встроенная flash</b> («riscv FPGA Flash», MODE1 = MODE0 = 0) - программа в битовом потоке' :
      `- битовый поток и программа (у ${esc(DEV.series)} встроенной flash нет)`}, флеш - только для данных программы.
    <b>Эта флеш, загрузка по MSPI</b> (Tang Nano 9K - MODE1 = 1, подтяжка вывода 87 к 1.8 В; Tang Primer 20K - всегда) - битовый поток с адреса 0
    (${esc(DEV.series)}: до ${hex6(CFG_REGION)}), программа - образом с адреса образа; после сброса загрузчик копирует её в IMEM/DMEM.
    Пишет «riscv SPI-FLASH». Свободная область - ${esc(inst.name)}_USER_ADDR в soc.h. Выводы MSPI: Tang Nano 9K (P25Q32U) - 59 SCLK, 60 CS#,
    61 MOSI, 62 MISO; Tang Primer 20K - L10, M9, R10, P10. Генератор сам включает в Gowin EDA «MSPI как обычные I/O».</p>`;
  h += `<div class="pane-actions"><button type="button" data-act="readme">Описание модуля</button>
        <button type="button" class="danger" data-act="remove">Удалить блок</button></div>`;
  return h;
}

function wireInstForm(box, inst) {
  const q = name => box.querySelector(`[name="${name}"]`);
  box.querySelector('[data-act=close]').addEventListener('click', () => select(null));
  q('name').addEventListener('change', e => {
    const nv = e.target.value.trim();
    if (!nv || nv === inst.name) return;
    inst.name = nv; sel = { kind: 'inst', name: nv };
    changed();
  });
  q('baseMode').addEventListener('change', e => {
    if (e.target.value === 'auto') inst.base = 'auto';
    else { const s = addressMap(model).baseOf(inst.name); inst.base = s == null ? '0x15000000' : hex8(s * 0x01000000); }
    changed();
  });
  q('base').addEventListener('change', e => { inst.base = e.target.value.trim().replace(/_/g, ''); changed(); });
  for (const k of ['irq', 'parity']) if (q(k)) q(k).addEventListener('change', e => { inst[k] = e.target.value; changed(); });
  for (const k of ['width', 'stop', 'fifo', 'baud', 'sizeMB', 'div', 'delayTicks', 'pulseTicks']) if (q(k)) q(k).addEventListener('change', e => { inst[k] = Number(e.target.value); changed(); });
  if (q('sim')) q('sim').addEventListener('change', e => { inst.sim = e.target.value === '1'; changed(); });
  if (q('sawKHz')) q('sawKHz').addEventListener('change', e => { inst.sawHz = Math.round(Number(e.target.value) * 1000); changed(); });
  if (q('fpgaConfig')) q('fpgaConfig').addEventListener('change', e => {
    inst.fpgaConfig = e.target.value === '1';
    //Битовый поток с адреса 0: образ программы сдвигается выше него (1 МБайт), если стоял ниже
    if (inst.fpgaConfig && (parseBase(inst.bootAddr) || 0) < CFG_REGION) inst.bootAddr = hex6(Math.max(0x100000, CFG_REGION));
    changed();
  });
  if (q('bootAddr')) q('bootAddr').addEventListener('change', e => { inst.bootAddr = e.target.value.trim().replace(/_/g, ''); changed(); });
  box.querySelectorAll('select[name^=pin_]').forEach(s => s.addEventListener('change', () => {
    const key = s.dataset.key, sig = findSig(`${inst.name}.${key}`) || { id: `${inst.name}.${key}`, inst, key, def: defNet(inst, key) };
    movePin(sig, s.value);
    changed();
  }));
  box.querySelectorAll('input[name^=net_]').forEach(i => i.addEventListener('change', () => {
    const pin = instPin(inst, i.dataset.key);
    if (pin != null) { setNet(model, pin, i.value); changed(); }
  }));
  box.querySelectorAll('[data-act=delline]').forEach(b => b.addEventListener('click', () => {
    inst.lines.splice(Number(b.dataset.key.slice(4)), 1);
    changed();
  }));
  const act = (a, fn) => { const b = box.querySelector(`[data-act=${a}]`); if (b) b.addEventListener('click', fn); };
  act('addline', () => pinPicker({ id: `${inst.name}.newline`, inst, key: 'newline', name: `${inst.name} IO${inst.lines.length}`,
                                   dir: 'inout', def: defNet(inst, 'line' + inst.lines.length) }));
  act('addout', () => pinPicker({ id: `${inst.name}.out`, inst, key: 'out', name: `${inst.name} PWM`, dir: 'output', def: defNet(inst, 'out') }));
  act('delout', () => { inst.out = null; changed(); });
  act('readme', () => openLibrary(inst.type));
  act('remove', () => {
    if (!confirm(`Удалить блок ${inst.name}? Его выводы освободятся, имена цепей останутся подписями.`)) return;
    model.periph.splice(model.periph.indexOf(inst), 1);
    unnumberSingles(model);
    sel = null;
    changed();
  });
}

function clockForm() {
  const c = model.clock, p = c.pll;
  const xtalOpts = IO_PINS.map(n => { const q = PIN[n];
    return `<option value="${n}"${n === c.xtalPin ? ' selected' : ''}>${clockCapable(n) ? '★ ' : ''}${n} · ${q.name}${q.cfg ? ' · ' + q.cfg : ''}</option>`; }).join('');
  const e = pllOf(model), auto = p.mode === 'auto';
  return panelHead('Такт и сброс', 'rPLL · системное', 'var(--c-sys)') + `<div class="form-grid pane">
      <label>Кварц, МГц</label><input type="number" name="xtal" step="any" min="3" max="400" value="${c.xtalMHz}" style="width:100px">
      <label>Вывод кварца</label><select name="xtalPin">${xtalOpts}</select>
      <label>Имя цепи кварца</label><input type="text" class="mono net" name="xtalNet" value="${esc(netOf(model, c.xtalPin))}">
      <label>Расчёт rPLL</label><select name="mode">${opts([['auto', 'по частоте'], ['manual', 'делители вручную']], p.mode)}</select>
      <label>Нужная частота, МГц</label><input type="number" name="target" step="any" value="${p.targetMHz}" style="width:100px" ${auto ? '' : 'disabled'}>
      <label>IDIV · FBDIV · ODIV</label><div>
        <input type="number" name="idiv" min="0" max="63" value="${p.idiv}" style="width:54px" ${auto ? 'disabled' : ''}>
        <input type="number" name="fbdiv" min="0" max="63" value="${p.fbdiv}" style="width:54px" ${auto ? 'disabled' : ''}>
        <select name="odiv" ${auto ? 'disabled' : ''}>${ODIV_SET.map(o => `<option${o === p.odiv ? ' selected' : ''}>${o}</option>`).join('')}</select></div>
      <div class="full readout">CLKOUT = <b class="${e.errs.length ? 'bad' : 'good'}">${fmt(e.fout)} МГц</b> · PFD ${fmt(e.pfd)} · VCO ${fmt(e.vco)} МГц
        ${e.errs.length ? `<br><span class="bad">${e.errs.map(esc).join('<br>')}</span>` : ''}</div>
      <label>Вывод сброса</label><select name="rstPin">${pinOptions(model.reset.pin, 'rst', false)}</select>
      <label>Имя цепи сброса</label><input type="text" class="mono net" name="rstNet" value="${esc(model.reset.pin != null ? netOf(model, model.reset.pin) : '')}">
    </div>
    <p class="note">★ - выводы с глобальным тактом (GCLK) или входом PLL. f<sub>out</sub> = f<sub>кв</sub>·(FBDIV+1)/(IDIV+1);
    PFD ≥ ${PLL.pfdMin} МГц; VCO = f<sub>out</sub>·ODIV = ${PLL.vcoMin}..${PLL.vcoMax} МГц (${esc(DEV.series)}). SYSCLK_HZ в soc.h пересчитывается сам; цель в riscv.sdc держите выше рабочей частоты.</p>`;
}
function wireClockForm(box) {
  const c = model.clock, p = c.pll, q = name => box.querySelector(`[name="${name}"]`);
  box.querySelector('[data-act=close]').addEventListener('click', () => select(null));
  const num = (name, fn) => q(name).addEventListener('change', e => { fn(Number(e.target.value)); applyPllAuto(model); changed(); });
  num('xtal', x => { c.xtalMHz = x; });
  num('target', x => { p.targetMHz = x; });
  num('idiv', x => { p.idiv = x; }); num('fbdiv', x => { p.fbdiv = x; }); num('odiv', x => { p.odiv = x; });
  q('mode').addEventListener('change', e => { p.mode = e.target.value; applyPllAuto(model); changed(); });
  q('xtalPin').addEventListener('change', e => { c.xtalPin = pinv(e.target.value); ensureNet(model, { pin: c.xtalPin, def: 'clk' }); changed(); });
  q('xtalNet').addEventListener('change', e => { setNet(model, c.xtalPin, e.target.value); changed(); });
  q('rstPin').addEventListener('change', e => { model.reset.pin = pinv(e.target.value);
    if (model.reset.pin != null) ensureNet(model, { pin: model.reset.pin, def: 'rst_n' }); changed(); });
  q('rstNet').addEventListener('change', e => { if (model.reset.pin != null) { setNet(model, model.reset.pin, e.target.value); changed(); } });
}

function coreForm() {
  const c = model.core;
  const nbs = bsramBlocks(model), pll = pllOf(model);
  const need = Math.max(0, ...Object.values(irqMap(model)).filter(r => r.route === 'plic').map(r => r.n));
  const mem = (k, t) => `<label>${t}</label><div><select name="${k}Type">${opts([['bsram', 'BSRAM'], ['synth', 'синтезированная']], c[k].type)}</select>
      ${c[k].type === 'bsram' ? `<select name="${k}Kb">${opts(MEM_KB.map(v => [v, v + ' кБайт']), c[k].kb)}</select>`
        : `<input type="number" name="${k}Words" min="16" max="4096" value="${c[k].synthWords}" style="width:70px"> слов`}</div>`;
  return panelHead('Процессор cpu.sv', 'ядро, память, CLINT, PLIC, отладчик · системное', 'var(--c-sys)') + `<div class="form-grid pane">
      <label>Тип ядра</label><select name="coreType">${opts([['pipeline', 'конвейерное (5 стадий)'], ['singlecycle', 'однотактное']], c.coreType)}</select>
      <label>Расширение M</label><div><label class="chk"><input type="checkbox" name="mExt"${c.mExt ? ' checked' : ''}> mul/div</label>
        <select name="divBpc" ${c.mExt ? '' : 'disabled'}>${opts([[1, '1 бит'], [2, '2 бита'], [4, '4 бита']], c.divBpc)}</select> <span class="muted">за такт</span></div>
      <label>Регистровый файл</label><select name="rfType" ${c.coreType === 'singlecycle' ? 'disabled' : ''}>${opts([['lut', 'LUT (распределённая память)'], ['bsram', 'BSRAM, чтение по спаду (2 блока SDPB)'], ['bsram-edge', 'BSRAM, чтение на фронте D→E (сравнение)']], c.rfType)}</select>
      ${mem('imem', 'IMEM')}
      ${mem('dmem', 'DMEM')}
      <label>Отладчик JTAG</label><label class="chk"><input type="checkbox" name="debug"${c.debug ? ' checked' : ''}> ${esc(jtagText())}</label>
      <label>Источников PLIC</label><div><input type="number" name="plicSources" min="1" max="31" value="${c.plicSources}" style="width:64px">
        <span class="muted"> нужно ${need}</span></div>
      <div class="full readout">Шина периферии: <b>${pll.errs.length ? '—' : fmt(sysclkHz(model) / 1e6) + ' МГц'}</b> ·
        BSRAM: <b class="${nbs > BSRAM_TOTAL ? 'bad' : 'good'}">${nbs} из ${BSRAM_TOTAL}</b></div>
    </div>
    <p class="note">Параметры попадают в параметры cpu в top.sv и в soc.h. Однотактное ядро с BSRAM делит частоту rPLL на 3.
    Регистровый файл на BSRAM (только конвейер): 2 блока SDPB вместо ~230 LUT распределённой памяти. Чтение по спаду в середине стадии D (RF_TYPE = 2) - для GW2A-18 рекомендуется; на GW1NR-9 45 МГц только при Place 1/2. Чтение на фронте D→E (RF_TYPE = 1) - для сравнения.
    Размер IMEM/DMEM ограничивает и компоновщик (GW1NR9.lds, общий для плат).</p>`;
}
function wireCoreForm(box) {
  const c = model.core, q = name => box.querySelector(`[name="${name}"]`);
  box.querySelector('[data-act=close]').addEventListener('click', () => select(null));
  const on = (name, fn) => { const e = q(name); if (e) e.addEventListener('change', ev => { fn(ev.target); changed(); }); };
  on('coreType', e => { c.coreType = e.value; });
  on('mExt', e => { c.mExt = e.checked; });
  on('divBpc', e => { c.divBpc = Number(e.value); });
  on('rfType', e => { c.rfType = e.value; });
  on('debug', e => { c.debug = e.checked; });
  on('plicSources', e => { c.plicSources = Math.max(1, Math.min(31, Number(e.value) || 8)); });
  for (const k of ['imem', 'dmem']) {
    on(k + 'Type', e => { c[k].type = e.value; });
    on(k + 'Kb', e => { c[k].kb = Number(e.value); });
    on(k + 'Words', e => { c[k].synthWords = Math.max(16, Math.min(4096, Number(e.value) || 256)); });
  }
}

// ============================================================================================
// Библиотека периферии и описание модуля (README.md устройства)
// ============================================================================================
function openLibrary(type) {
  const d = document.getElementById('lib');
  if (typeof type === 'string') showReadme(type); else showLibraryList();
  if (!d.open) d.showModal();
}
function showLibraryList() {
  const body = document.getElementById('libBody');
  document.getElementById('libTitle').textContent = 'Библиотека периферии';
  body.innerHTML = Object.entries(CATS).map(([ck, c]) => {
    const list = Object.entries(TYPES).filter(([, t]) => t.cat === ck);
    if (!list.length) return '';
    return `<h4><span class="dot" style="background:${c.color}"></span>${c.title}</h4>` + list.map(([k, t]) => {
      const n = insts(model, k).length;
      return `<div class="lib-card" style="border-left-color:${c.color}"><div class="lib-main"><b>${t.title}</b>
        ${n ? `<span class="muted"> · в проекте: ${n}</span>` : ''}<div>${esc(t.about)}</div></div>
        <div class="lib-btns"><button type="button" data-readme="${k}">Описание</button>
        <button type="button" class="primary" data-add="${k}">Добавить</button></div></div>`;
    }).join('');
  }).join('') + `<p class="note">Устройства лежат в hw/src/periph/&lt;тип&gt;/ (модуль, тест, README.md). Как сделать своё -
    hw/src/periph/README.md; чтобы оно появилось здесь, его добавляют в генератор socgen.py и в app.js (TYPES).</p>`;
  body.querySelectorAll('[data-readme]').forEach(b => b.addEventListener('click', () => showReadme(b.dataset.readme)));
  body.querySelectorAll('[data-add]').forEach(b => b.addEventListener('click', () => addInstance(b.dataset.add)));
}
//Выводы блока по умолчанию - выводы конфигурации кристалла (у SPIFLASH - MSPI: MCLK, MCS_N, MO, MI), если свободны
function defaultCfgPins(m, inst) {
  const cp = TYPES[inst.type].cfgPins || {};
  const busy = new Set(signals(m).filter(x => x.pin != null).map(x => x.pin));
  for (const [k, f] of Object.entries(cp)) {
    const n = pinWithCfg(f);
    if (inst[k] == null && n != null && !busy.has(n) && !(m.core.debug && JTAG_PINS[n])) {
      inst[k] = n; ensureNet(m, { pin: n, def: defNet(inst, k) });
    }
  }
}
function addInstance(type) {
  const same = insts(model, type), t = TYPES[type].title;
  if (same.length === 1 && same[0].name === t && !model.periph.some(i => i.name.toLowerCase() === (t + '0').toLowerCase())) {
    same[0].name = t + '0';
    if (sel && sel.kind === 'inst' && sel.name === t) sel.name = t + '0';
  }
  const inst = Object.assign(TYPES[type].defaults(), { type, name: defaultName(model, type), base: 'auto' });
  //Порядок ключей в файле: тип, имя, адрес, настройки
  const ordered = { type, name: inst.name, base: 'auto' };
  for (const k of Object.keys(inst)) if (!(k in ordered)) ordered[k] = inst[k];
  model.periph.push(ordered);
  //Выводы по умолчанию (SPIFLASH - выводы MSPI флеш конфигурации) - только свободные
  defaultCfgPins(model, ordered);
  document.getElementById('lib').close();
  sel = { kind: 'inst', name: ordered.name };
  changed();
  setStatus(`Добавлен ${ordered.name}: назначьте выводы (+ на схеме или справа)`, '');
}

const readmeWait = {};
function loadReadme(type) {
  if (inHost()) return new Promise(res => { readmeWait[type] = res; host('readme', type); });
  const cfg = new URLSearchParams(location.search).get('cfg') || '';
  const src = (model.paths && model.paths.src) || `${(model.paths && model.paths.hw) || '../hw'}/src`;
  const url = new URL(`${src}/periph/${type}/README.md`, new URL(cfg, location.href));
  return fetch(url).then(r => r.ok ? r.text() : Promise.reject(new Error(r.status))).catch(e => `Описание не найдено (${url.pathname}): ${e.message}`);
}
function showReadme(type) {
  const t = TYPES[type];
  document.getElementById('libTitle').textContent = `${t.title} - описание модуля`;
  const body = document.getElementById('libBody');
  body.innerHTML = `<div class="lib-nav"><button type="button" data-back>← К библиотеке</button>
    <button type="button" class="primary" data-add="${type}">Добавить ${t.title}</button></div><div class="md">Загрузка…</div>`;
  body.querySelector('[data-back]').addEventListener('click', showLibraryList);
  body.querySelector('[data-add]').addEventListener('click', () => addInstance(type));
  loadReadme(type).then(text => { const md = body.querySelector('.md'); if (md) md.innerHTML = mdToHtml(text); });
}

//Небольшой разбор Markdown для описаний модулей: заголовки, списки, таблицы, код, выделение
function mdToHtml(src) {
  const inline = s => esc(s)
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>')
    .replace(/(^|[\s(])\*([^*\s][^*]*)\*/g, '$1<i>$2</i>')
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<span class="lnk" title="$2">$1</span>');
  const lines = src.replace(/\r/g, '').split('\n');
  let html = '', i = 0;
  while (i < lines.length) {
    const l = lines[i];
    if (/^```/.test(l)) {
      const code = []; i++;
      while (i < lines.length && !/^```/.test(lines[i])) code.push(lines[i++]);
      i++; html += `<pre>${esc(code.join('\n'))}</pre>`; continue;
    }
    if (/^#{1,6}\s/.test(l)) { const n = l.match(/^#+/)[0].length; html += `<h${Math.min(6, n + 2)}>${inline(l.replace(/^#+\s*/, ''))}</h${Math.min(6, n + 2)}>`; i++; continue; }
    if (/^(=+|-+)\s*$/.test(l) && i > 0) { i++; continue; }
    if (i + 1 < lines.length && /^(=+)\s*$/.test(lines[i + 1]) && l.trim()) { html += `<h3>${inline(l)}</h3>`; i += 2; continue; }
    if (/^\s*\|/.test(l)) {
      const rows = [];
      while (i < lines.length && /^\s*\|/.test(lines[i])) rows.push(lines[i++]);
      const cells = r => r.trim().replace(/^\||\|$/g, '').split('|').map(c => c.trim());
      html += '<table>' + rows.filter(r => !/^\s*\|[\s:|-]+\|\s*$/.test(r)).map((r, k) =>
        `<tr>${cells(r).map(c => k === 0 ? `<th>${inline(c)}</th>` : `<td>${inline(c)}</td>`).join('')}</tr>`).join('') + '</table>';
      continue;
    }
    if (/^\s*([-*]|\d+\.)\s/.test(l)) {
      const ordered = /^\s*\d+\./.test(l), items = [];
      while (i < lines.length && (/^\s*([-*]|\d+\.)\s/.test(lines[i]) || (/^\s{2,}\S/.test(lines[i]) && items.length))) {
        if (/^\s*([-*]|\d+\.)\s/.test(lines[i]) && !/^\s{3,}/.test(lines[i])) items.push(lines[i].replace(/^\s*([-*]|\d+\.)\s/, ''));
        else items[items.length - 1] += ' ' + lines[i].trim();
        i++;
      }
      html += `<${ordered ? 'ol' : 'ul'}>${items.map(x => `<li>${inline(x)}</li>`).join('')}</${ordered ? 'ol' : 'ul'}>`;
      continue;
    }
    if (!l.trim()) { i++; continue; }
    const para = [];
    while (i < lines.length && lines[i].trim() && !/^(#|```|\s*\||\s*([-*]|\d+\.)\s)/.test(lines[i])) para.push(lines[i++]);
    html += `<p>${inline(para.join(' '))}</p>`;
  }
  return html;
}

// ============================================================================================
// Сохранение и связь с Eclipse
// ============================================================================================
//JSON в читаемом виде: короткие объекты и массивы чисел - в одну строку
function toJson(v, ind = '') {
  const inner = ind + '  ';
  if (Array.isArray(v)) {
    if (v.every(x => x === null || typeof x !== 'object')) return '[' + v.map(x => JSON.stringify(x)).join(', ') + ']';
    return '[\n' + v.map(x => inner + toJson(x, inner)).join(',\n') + '\n' + ind + ']';
  }
  if (v && typeof v === 'object') {
    const keys = Object.keys(v);
    if (!keys.length) return '{}';
    const flat = keys.every(k => v[k] === null || typeof v[k] !== 'object' || (Array.isArray(v[k]) && v[k].every(x => typeof x !== 'object' || x === null)));
    const one = '{ ' + keys.map(k => JSON.stringify(k) + ': ' + toJson(v[k])).join(', ') + ' }';
    if (flat && one.length + ind.length < 116) return one;
    return '{\n' + keys.map(k => inner + JSON.stringify(k) + ': ' + toJson(v[k], inner)).join(',\n') + '\n' + ind + '}';
  }
  return JSON.stringify(v);
}
function pinsSorted(p) {
  const o = {};
  Object.keys(p).sort((a, b) => pinCmp(pinv(a), pinv(b))).forEach(k => { o[k] = p[k]; });
  return o;
}
//Порядок разделов в файле
function ordered(m) {
  const keys = ['format', 'version', 'board', 'device', 'paths', 'core', 'clock', 'reset', 'periph', 'ioDefaults', 'banks', 'pins', 'build'];
  const o = {};
  for (const k of keys) if (k in m) o[k] = m[k];
  for (const k of Object.keys(m)) if (!(k in o)) o[k] = m[k];
  return o;
}

function setStatus(text, kind) {
  const s = document.getElementById('status');
  s.textContent = text; s.className = 'bar-status' + (kind ? ' ' + kind : ''); s.title = text;
}

window.gwsoc = {
  load(text) {
    try {
      model = normalize(JSON.parse(text));
      setDevice(model.device || DEFAULT_DEVICE);
      applyPllAuto(model);
      dirty = false;
      const ren = unnumberSingles(model);
      if (sel && sel.kind === 'inst' && !instByName(sel.name)) sel = null;
      document.getElementById('devname').textContent = (model.board && model.board.title) || '';
      document.getElementById('device').value = DEV.part;
      document.getElementById('toolchain').value = model.build.toolchain;
      render();
      setStatus('', '');
      if (ren.length) { dirty = true; host('dirty'); setStatus(`Единственный блок типа - без номера: ${ren.join(', ')}. Сохраните файл`, ''); }
    } catch (e) { setStatus('Ошибка чтения файла .gwsoc: ' + e.message, 'err'); }
  },
  getJson() {
    model.pins = pinsSorted(model.pins);
    model.version = 2;
    if (model.build.placeOption === '') delete model.build.placeOption;
    if (model.build.loadingRate === '') delete model.build.loadingRate;
    return toJson(ordered(model)) + '\n';
  },
  saved() { dirty = false; setStatus('Сохранено', 'ok'); },
  status(text, kind) { setStatus(text, kind); },
  readme(type, text) { const r = readmeWait[type]; delete readmeWait[type]; if (r) r(text); },
  progress(pct, text) { showProgress(Number(pct), text || ''); },
  buildDone(ok) {
    clearInterval(buildTimer);
    const t = mmss(Math.round((Date.now() - buildT0) / 1000));
    setBuilding(false);
    const s = document.getElementById('status');
    if (s.textContent) s.textContent += ` (${t})`;
  },
  resources(text) { try { lastRes = text ? JSON.parse(text) : null; } catch (e) { lastRes = null; } if (model) renderResources(); },
  hasErrors() { return validate(model).issues.some(i => i.lvl === 'err'); },
};

function doSave() {
  if (!inHost()) { setStatus('Сохранение доступно при запуске из Eclipse', ''); return; }
  host('save', window.gwsoc.getJson());
}
function doBuild() {
  if (building) return;
  const errs = validate(model).issues.filter(i => i.lvl === 'err');
  if (errs.length) { setStatus(`Сборка невозможна: ошибок ${errs.length} (см. «Проверка»)`, 'err'); return; }
  if (!inHost()) { setStatus('Сборка доступна при запуске из Eclipse', ''); return; }
  setStatus('Сборка…', '');
  setBuilding(true);
  host('build', window.gwsoc.getJson());
}

//Смена ПЛИС (кристалл платы): номера выводов у корпусов разные - назначения, которых нет в новом корпусе, снимаются,
//сигналы остаются без выводов (их назначают заново, ошибки в «Проверка» подсказывают, какие). Выводы флеш SPIFLASH -
//на выводы MSPI нового кристалла, если свободны. Проект Gowin (riscv.gprj) и VCC генератор перепишет при сборке
function changeDevice(part) {
  if (!model || part === DEV.part) return;
  const to = DEVICES[part];
  const lost = signals(model).filter(s => s.pin != null && !to.pins.some(p => p.n === s.pin && p.type === 'io'));
  if (lost.length && !confirm(`Сменить ПЛИС на ${to.title} (${to.family})?

У корпуса ${to.package} другие выводы: назначения ` +
      `${lost.length} сигналов будут сняты, их нужно будет назначить заново. Отменить смену можно, не сохраняя файл.`)) {
    document.getElementById('device').value = DEV.part;
    return;
  }
  lost.forEach(s => setSignalPin(model, s, null));
  for (const k of Object.keys(model.pins)) if (!to.pins.some(p => String(p.n) === k)) delete model.pins[k];
  const banks = new Set(to.pins.filter(p => p.bank != null).map(p => String(p.bank)));
  for (const k of Object.keys(model.banks)) if (!banks.has(k)) delete model.banks[k];
  model.device = part;
  setDevice(part);
  insts(model, 'spiflash').forEach(f => defaultCfgPins(model, f));
  sel = null;
  changed();
  setStatus(`ПЛИС: ${DEV.title} (${DEV.family})${lost.length ? ` - снято назначений: ${lost.length}, назначьте выводы заново` : ''}. Сохраните и соберите`, lost.length ? 'err' : 'ok');
}
document.getElementById('device').innerHTML = Object.values(DEVICES).map(d =>
  `<option value="${esc(d.part)}">${esc(d.title)} · ${esc(d.family)}</option>`).join('');
document.getElementById('device').addEventListener('change', e => changeDevice(e.target.value));
setDevice(DEFAULT_DEVICE);
document.getElementById('save').addEventListener('click', doSave);
document.getElementById('toolchain').addEventListener('change', e => { if (model) { model.build.toolchain = e.target.value; changed(); } });
document.getElementById('placeOpt').addEventListener('change', e => {
  if (!model) return;
  if (e.target.value === '') delete model.build.placeOption; else model.build.placeOption = e.target.value;
  changed();
});
document.getElementById('loadRate').addEventListener('change', e => {
  if (!model) return;
  if (e.target.value === '') delete model.build.loadingRate; else model.build.loadingRate = e.target.value;
  changed();
});
document.getElementById('build').addEventListener('click', doBuild);
document.getElementById('addBlock').addEventListener('click', () => model && openLibrary());
document.getElementById('ioDefaults').addEventListener('click', () => model && ioDefaultsDialog());
document.getElementById('zoomIn').addEventListener('click', () => { zoom = (zoom || currentScale()) * 1.2; applyZoom(); });
document.getElementById('zoomOut').addEventListener('click', () => { zoom = Math.max(0.3, (zoom || currentScale()) / 1.2); applyZoom(); });
document.getElementById('zoomFit').addEventListener('click', () => { zoom = 0; applyZoom(); });
document.getElementById('canvas').addEventListener('wheel', e => {
  if (!e.ctrlKey) return;
  e.preventDefault();
  zoom = Math.max(0.3, Math.min(4, (zoom || currentScale()) * (e.deltaY < 0 ? 1.1 : 1 / 1.1)));
  applyZoom();
}, { passive: false });
document.getElementById('amap').addEventListener('click', e => {
  const tr = e.target.closest('tr[data-inst]');
  if (tr) select({ kind: 'inst', name: tr.dataset.inst });
});
//Enter в поле панели - сохранить (как уход из поля)
document.getElementById('settings').addEventListener('keydown', e => {
  if (e.key === 'Enter' && e.target.tagName === 'INPUT') { e.preventDefault(); e.target.dispatchEvent(new Event('change', { bubbles: true })); }
});
window.addEventListener('resize', () => { if (!zoom) applyZoom(); });
document.addEventListener('keydown', e => {
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's') { e.preventDefault(); doSave(); }
});
document.getElementById('placeOpt').innerHTML = opts(PLACE_OPTIONS, '');
document.getElementById('loadRate').innerHTML = opts(LOADING_OPTIONS, '');

//Запуск: в Eclipse файл передаёт редактор (gwsoc.load), в браузере - параметр ?cfg=<url>
window.addEventListener('DOMContentLoaded', () => {
  if (inHost()) { host('ready'); return; }
  const cfg = new URLSearchParams(location.search).get('cfg');
  //В Eclipse функция gwsocHost может появиться позже DOMContentLoaded - файл тогда передаст редактор
  if (!cfg) { setStatus('Загрузка конфигурации…', ''); return; }
  fetch(cfg).then(r => r.text()).then(t => {
    window.gwsoc.load(t);
    //Ресурсы последней сборки (в Eclipse их передаёт редактор)
    const url = new URL(`${(model.paths && model.paths.hw) || '../hw'}/impl/socgen/resources.json`, new URL(cfg, location.href));
    fetch(url).then(r => r.ok ? r.text() : '').then(x => window.gwsoc.resources(x)).catch(() => {});
  }).catch(e => setStatus('Не удалось загрузить ' + cfg + ': ' + e.message, 'err'));
});
