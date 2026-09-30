// Конфигуратор ПЛИС askoRV32 (GW1NR-LV9QN88P): модель .gwsoc, изображение корпуса, диалоги настроек.
// Правила (адреса, rPLL, проверки) продублированы в socgen.py - при изменении править оба места.
'use strict';

// ============================================================================================
// Данные кристалла и постоянные правила
// ============================================================================================
const DEV = window.GWSOC_DEVICE;
const PIN = {};
DEV.pins.forEach(p => { PIN[p.n] = p; });
const IO_PINS = DEV.pins.filter(p => p.type === 'io').map(p => p.n);
const JTAG_PINS = { 5: 'TMS', 6: 'TCK', 7: 'TDI', 8: 'TDO' };   //Заняты примитивом GW_JTAG при включённом отладчике

const ODIV_SET = [2, 4, 8, 16, 32, 48, 64, 80, 96, 112, 128];
const PLL = { inMin: 3, inMax: 400, pfdMin: 3, pfdMax: 400, vcoMin: 400, vcoMax: 1200, outMin: 3.125, outMax: 600 };

const IO_TYPES = ['LVCMOS33', 'LVCMOS25', 'LVCMOS18', 'LVCMOS15', 'LVCMOS12'];
const PULLS = ['UP', 'DOWN', 'NONE', 'KEEPER'];
const DRIVES = ['4', '8', '12', '16', '24'];
const VCCIOS = ['3.3', '2.5', '1.8', '1.5', '1.2'];

//Периферия на шине memmux: окно 16 МБайт (маска 0xFF000000), предпочтительный слот при "auto"
const BLOCKS = {
  gpio:   { title: 'GPIO',   color: 'var(--c-gpio)',   slot: 0x11, about: 'Порты ввода-вывода' },
  tm1638: { title: 'TM1638', color: 'var(--c-tm1638)', slot: 0x12, about: 'Индикатор и кнопки TM1638' },
  stim:   { title: 'STIM',   color: 'var(--c-stim)',   slot: 0x13, about: 'Простой таймер (ШИМ, прерывание LI0 и PLIC 1)' },
};
const FIXED_REGIONS = [
  { name: 'IMEM',  slot: 0x00, color: 'var(--c-core)', note: 'память команд' },
  { name: 'CLINT', slot: 0x02, color: 'var(--c-core)', note: 'mtime, msip' },
  { name: 'PLIC',  slot: 0x0C, color: 'var(--c-core)', note: 'прерывания периферии' },
  { name: 'DMEM',  slot: 0x10, color: 'var(--c-core)', note: 'память данных' },
  { name: 'SIM',   slot: 0x1F, color: 'var(--c-jtag)', note: 'tohost симулятора' },
];
const AUTO_FIRST = 0x11, AUTO_LAST = 0x1E;

const NET_RE = /^[A-Za-z_][A-Za-z0-9_$]*(\[(\d+)\])?$/;
const SV_KEYWORDS = new Set(['input', 'output', 'inout', 'wire', 'logic', 'reg', 'module', 'endmodule', 'assign',
  'always', 'begin', 'end', 'if', 'else', 'case', 'for', 'generate', 'parameter', 'localparam', 'int', 'bit']);
//Имена, уже занятые в top.sv
const RESERVED_NETS = new Set(['tck_pad_i', 'tms_pad_i', 'tdi_pad_i', 'tdo_pad_o', 'clk_dmem', 'rst_sys', 'irq_ext',
  'irq_stim', 'irq_local', 'plic_src']);

// ============================================================================================
// Модель
// ============================================================================================
let model = null;
let dirty = false;
let zoom = 0;             //0 - по размеру окна

const host = (cmd, arg) => (typeof window.gwsocHost === 'function')
  ? window.gwsocHost(cmd, arg === undefined ? null : arg) : undefined;
const inHost = () => typeof window.gwsocHost === 'function';

const hex8 = v => '0x' + (v >>> 0).toString(16).toUpperCase().padStart(8, '0');
const hexSlot = s => hex8(s * 0x01000000).replace(/^0x(....)/, '0x$1_');
const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

function normalize(m) {
  m.core = m.core || {};
  m.clock = m.clock || { xtalMHz: 27, xtalPin: 52, pll: {} };
  m.clock.pll = Object.assign({ mode: 'auto', targetMHz: 27, idiv: 0, fbdiv: 0, odiv: 32 }, m.clock.pll);
  m.reset = m.reset || { pin: null };
  m.blocks = m.blocks || {};
  m.blocks.gpio = Object.assign({ enabled: false, base: 'auto', lines: [] }, m.blocks.gpio);
  m.blocks.tm1638 = Object.assign({ enabled: false, base: 'auto', dio: null, clk: null, stb: null }, m.blocks.tm1638);
  m.blocks.stim = Object.assign({ enabled: false, base: 'auto', width: 16, out: null }, m.blocks.stim);
  m.ioDefaults = Object.assign({ ioType: 'LVCMOS18', pull: 'UP', drive: '8', vccio: '1.8' }, m.ioDefaults);
  m.pins = m.pins || {};
  m.build = Object.assign({ toolchain: 'gowin' }, m.build);
  return m;
}

//Все сигналы, которым нужен вывод (система + включённые блоки)
function signals(m) {
  const s = [];
  s.push({ id: 'clk', block: 'sys', name: 'Кварц', dir: 'input', pin: m.clock.xtalPin, def: 'clk' });
  s.push({ id: 'rst', block: 'sys', name: 'Сброс (актив. 0)', dir: 'input', pin: m.reset.pin, def: 'rst_n' });
  const b = m.blocks;
  if (b.gpio.enabled)
    b.gpio.lines.forEach((p, i) => s.push({ id: 'gpio.' + i, block: 'gpio', name: 'GPIO ' + i, dir: 'inout', pin: p, def: 'gpio' + i }));
  if (b.tm1638.enabled)
    [['dio', 'inout'], ['clk', 'output'], ['stb', 'output']].forEach(([k, d]) =>
      s.push({ id: 'tm1638.' + k, block: 'tm1638', name: 'TM1638 ' + k.toUpperCase(), dir: d, pin: b.tm1638[k], def: 'tm_' + k }));
  if (b.stim.enabled && b.stim.out != null)
    s.push({ id: 'stim.out', block: 'stim', name: 'STIM выход', dir: 'output', pin: b.stim.out, def: 'stim_out' });
  return s;
}

function setSignalPin(m, id, pin) {
  pin = (pin === '' || pin == null) ? null : Number(pin);
  if (id === 'clk') m.clock.xtalPin = pin;
  else if (id === 'rst') m.reset.pin = pin;
  else {
    const [blk, key] = id.split('.');
    if (blk === 'gpio') m.blocks.gpio.lines[Number(key)] = pin;
    else m.blocks[blk][key] = pin;
  }
}

const netOf = (m, n) => (m.pins[n] && m.pins[n].net) || '';
function setNet(m, n, net) {
  net = (net || '').trim();
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

// --- Адреса периферии ---
function parseBase(v) {
  if (v === 'auto' || v == null || v === '') return null;
  const x = typeof v === 'number' ? v : parseInt(String(v).replace(/_/g, ''), 16);
  return Number.isFinite(x) ? x : NaN;
}
function addressMap(m) {
  const rows = FIXED_REGIONS.map(r => ({ name: r.name, slot: r.slot, color: r.color, note: r.note, fixed: true, on: true }));
  const taken = new Map(rows.map(r => [r.slot, r.name]));
  const issues = [];
  const order = Object.keys(BLOCKS);
  //Сначала ручные адреса, затем автоматические - чтобы ручной не был отнят автоматическим
  for (const pass of ['manual', 'auto']) {
    for (const k of order) {
      const b = m.blocks[k], meta = BLOCKS[k];
      const base = parseBase(b.base);
      if ((base === null) !== (pass === 'auto')) continue;
      const row = { name: meta.title, key: k, color: meta.color, note: meta.about, on: b.enabled, auto: base === null };
      if (!b.enabled) { row.slot = base === null ? meta.slot : (base >>> 24); rows.push(row); continue; }
      if (base === null) {
        let s = meta.slot;
        if (taken.has(s)) { s = AUTO_FIRST; while (s <= AUTO_LAST && taken.has(s)) s++; }
        if (s > AUTO_LAST) { issues.push({ lvl: 'err', text: `${meta.title}: нет свободного окна адресов` }); continue; }
        row.slot = s;
      } else if (Number.isNaN(base) || base < 0 || base > 0xFFFFFFFF || (base & 0x00FFFFFF) !== 0) {
        issues.push({ lvl: 'err', text: `${meta.title}: адрес должен быть кратен 0x0100_0000 (окно 16 МБайт)` });
        row.slot = null;
      } else {
        row.slot = base >>> 24;
        if (taken.has(row.slot)) issues.push({ lvl: 'err', text: `${meta.title}: адрес ${hexSlot(row.slot)} уже занят (${taken.get(row.slot)})` });
      }
      if (row.slot != null) taken.set(row.slot, meta.title);
      rows.push(row);
    }
  }
  rows.sort((a, b) => (a.slot ?? 999) - (b.slot ?? 999));
  return { rows, issues, baseOf: k => { const r = rows.find(x => x.key === k); return r ? r.slot : null; } };
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
const fmt = x => (Math.round(x * 1000) / 1000).toString().replace('.', ',');
const pllOf = m => pllEval(Number(m.clock.xtalMHz), m.clock.pll.idiv, m.clock.pll.fbdiv, m.clock.pll.odiv);

const clockCapable = n => { const c = PIN[n] && PIN[n].cfg || ''; return /GCLK|PLL_T_IN/.test(c); };

// --- Проверка ---
function validate(m) {
  const out = [];
  const sigs = signals(m);
  const byPin = new Map();
  for (const s of sigs) {
    if (s.pin == null) { out.push({ lvl: 'err', text: `${s.name}: вывод не назначен`, block: s.block }); continue; }
    if (!PIN[s.pin] || PIN[s.pin].type !== 'io') { out.push({ lvl: 'err', text: `${s.name}: вывод ${s.pin} не является I/O`, pin: s.pin }); continue; }
    if (m.core.debug && JTAG_PINS[s.pin]) out.push({ lvl: 'err', text: `${s.name}: вывод ${s.pin} занят JTAG (${JTAG_PINS[s.pin]})`, pin: s.pin });
    if (!byPin.has(s.pin)) byPin.set(s.pin, []);
    byPin.get(s.pin).push(s);
  }
  for (const [pin, list] of byPin)
    if (list.length > 1) out.push({ lvl: 'err', text: `Вывод ${pin}: ${list.map(s => s.name).join(', ')} - конфликт`, pin, conflict: true });

  //Имена цепей назначенных выводов: допустимость, уникальность, непрерывность шин
  const nets = new Map(), buses = new Map();
  for (const [pin, list] of byPin) {
    const net = netOf(m, pin);
    if (!net) { out.push({ lvl: 'err', text: `Вывод ${pin}: нет имени цепи`, pin }); continue; }
    const mm = NET_RE.exec(net);
    const baseName = mm ? net.replace(/\[\d+\]$/, '') : net;
    if (!mm || SV_KEYWORDS.has(baseName) || RESERVED_NETS.has(baseName)) {
      out.push({ lvl: 'err', text: `Вывод ${pin}: имя «${net}» недопустимо для порта SystemVerilog`, pin }); continue;
    }
    if (nets.has(net)) out.push({ lvl: 'err', text: `Имя «${net}» у выводов ${nets.get(net)} и ${pin}`, pin });
    nets.set(net, pin);
    if (!buses.has(baseName)) buses.set(baseName, { idx: [], scalar: false });
    if (mm[2] !== undefined) buses.get(baseName).idx.push(Number(mm[2])); else buses.get(baseName).scalar = true;
  }
  for (const [name, b] of buses) {
    if (b.scalar && b.idx.length) out.push({ lvl: 'err', text: `«${name}» используется и как шина, и как одиночный сигнал` });
    if (b.idx.length) {
      const max = Math.max(...b.idx);
      const miss = [];
      for (let i = 0; i <= max; i++) if (!b.idx.includes(i)) miss.push(i);
      if (miss.length) out.push({ lvl: 'err', text: `Шина «${name}[${max}:0]»: нет разрядов ${miss.join(', ')}` });
    }
  }

  if (m.clock.xtalPin != null && PIN[m.clock.xtalPin] && !clockCapable(m.clock.xtalPin))
    out.push({ lvl: 'warn', text: `Кварц на выводе ${m.clock.xtalPin} без GCLK/PLL_IN: такт пойдёт по обычной трассировке`, pin: m.clock.xtalPin });
  const pll = pllOf(m);
  pll.errs.forEach(e => out.push({ lvl: 'err', text: 'rPLL: ' + e, block: 'sys' }));

  //Банки: одно напряжение VCCIO на банк
  const bankV = new Map();
  for (const pin of byPin.keys()) {
    const p = PIN[pin]; if (!p || p.bank == null) continue;
    const v = (m.pins[pin] && m.pins[pin].vccio) || m.ioDefaults.vccio;
    if (!bankV.has(p.bank)) bankV.set(p.bank, new Set());
    bankV.get(p.bank).add(v);
  }
  for (const [bank, vs] of bankV)
    if (vs.size > 1) out.push({ lvl: 'warn', text: `Банк ${bank}: разные BANK_VCCIO (${[...vs].join(', ')} В)` });

  if (m.build.toolchain === 'apicula' && m.core.debug)
    out.push({ lvl: 'warn', text: 'apicula: отладчик JTAG в этой сборке будет выключен (GW_JTAG для GW1N-9C не поддерживается)' });
  if (m.build.toolchain === 'apicula' && !pll.errs.length && pll.fout > 31.5)
    out.push({ lvl: 'warn', text: `apicula: ${fmt(pll.fout)} МГц - открытый маршрут держит около 31 МГц, Gowin EDA - 45 МГц` });
  if (m.blocks.gpio.enabled && m.blocks.gpio.lines.length === 0) out.push({ lvl: 'err', text: 'GPIO: нет ни одной линии', block: 'gpio' });
  out.push(...addressMap(m).issues);
  return { issues: out, byPin };
}

// ============================================================================================
// Изображение микросхемы
// ============================================================================================
const G = { pitch: 24, pad: 16, marg: 22, label: 132 };
G.body = DEV.perSide * G.pitch + 2 * G.marg;
G.o = G.label + G.pad + 8;
G.size = G.body + 2 * G.o;

const SVGNS = 'http://www.w3.org/2000/svg';
function el(tag, attrs, parent, text) {
  const e = document.createElementNS(SVGNS, tag);
  for (const k in attrs) e.setAttribute(k, attrs[k]);
  if (text !== undefined) e.textContent = text;
  if (parent) parent.appendChild(e);
  return e;
}

//Положение вывода n: сторона, центр, направление наружу
function pinGeom(n) {
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

function render() {
  const svg = document.getElementById('chip');
  svg.textContent = '';
  svg.setAttribute('viewBox', `0 0 ${G.size} ${G.size}`);
  applyZoom();

  const v = validate(model);
  const sigs = signals(model);
  const sigByPin = new Map();
  sigs.forEach(s => { if (s.pin != null) { if (!sigByPin.has(s.pin)) sigByPin.set(s.pin, []); sigByPin.get(s.pin).push(s); } });
  const conflictPins = new Set(v.issues.filter(i => i.conflict).map(i => i.pin));

  el('rect', { class: 'body-rect', x: G.o, y: G.o, width: G.body, height: G.body, rx: 10 }, svg);
  el('circle', { class: 'pin1', cx: G.o + 14, cy: G.o + 14, r: 5 }, svg);
  el('text', { class: 'chip-title', x: G.o + G.body / 2, y: G.o + 52 }, svg, 'GW1NR-LV9QN88P');
  el('text', { class: 'chip-sub', x: G.o + G.body / 2, y: G.o + 68 }, svg, 'askoRV32 · вид сверху');

  for (const p of DEV.pins) drawPin(svg, p, sigByPin.get(p.n) || [], conflictPins.has(p.n));
  drawTiles(svg);
  renderSide(v);
  renderLegend();
  renderIoTable(v);
}

const BANK_COLOR = b => `var(--bank${b})`;

function drawPin(svg, p, sigs, conflict) {
  const g = pinGeom(p.n);
  const net = netOf(model, p.n);
  const jtag = model.core.debug && JTAG_PINS[p.n];
  const cls = ['pin'];
  if (p.type !== 'io') cls.push('power');
  else if (jtag && !sigs.length) cls.push('jtag');
  if (sigs.length) cls.push('used', 'b-' + sigs[0].block);
  if (net) cls.push('labeled');
  if (conflict) cls.push('conflict');
  const gp = el('g', { class: cls.join(' '), 'data-pin': p.n }, svg);

  //Ячейка вывода снаружи корпуса (цвет - банк), кружок в ней (цвет - блок, если вывод занят)
  const C = 18, out = G.pad + 4;
  let cx, cy, numA, labA;
  if (g.side === 'L') { cx = g.x - out / 2; cy = g.y; numA = { x: g.x + 5, y: g.y, a: 'start' }; labA = { x: g.x - out - 6, y: g.y, a: 'end' }; }
  if (g.side === 'R') { cx = g.x + out / 2; cy = g.y; numA = { x: g.x - 5, y: g.y, a: 'end' }; labA = { x: g.x + out + 6, y: g.y, a: 'start' }; }
  if (g.side === 'B') { cx = g.x; cy = g.y + out / 2; numA = { x: g.x, y: g.y - 5, a: 'start', rot: true }; labA = { x: g.x, y: g.y + out + 6, a: 'end', rot: true }; }
  if (g.side === 'T') { cx = g.x; cy = g.y - out / 2; numA = { x: g.x, y: g.y + 5, a: 'end', rot: true }; labA = { x: g.x, y: g.y - out - 6, a: 'start', rot: true }; }

  const cellFill = p.type === 'gnd' ? 'var(--gnd)' : p.type === 'pwr' ? 'var(--pwr)' : BANK_COLOR(p.bank);
  el('rect', { class: 'cell', x: cx - C / 2, y: cy - C / 2, width: C, height: C, rx: 2, fill: cellFill }, gp);
  if (p.type === 'io') {
    const mk = el('circle', { class: 'mark', cx, cy, r: 5.5 }, gp);
    if (sigs.length && !conflict) mk.style.fill = blockColor(sigs[0].block);
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
  const span = out + 24;
  const hit = g.side === 'L' ? { x: g.x - out, y: g.y - G.pitch / 2, width: span, height: G.pitch }
            : g.side === 'R' ? { x: g.x + out - span, y: g.y - G.pitch / 2, width: span, height: G.pitch }
            : g.side === 'B' ? { x: g.x - G.pitch / 2, y: g.y + out - span, width: G.pitch, height: span }
            :                  { x: g.x - G.pitch / 2, y: g.y - out, width: G.pitch, height: span };
  const hitEl = el('rect', Object.assign({ class: 'hit' }, hit), gp);

  const info = [`Вывод ${p.n} · ${p.name}`];
  if (p.bank != null) info.push(`банк ${p.bank}`);
  if (p.cfg) info.push(p.cfg);
  if (p.lvds) info.push('True LVDS');
  const tip = info.join(' · ') + (sigs.length ? '\n' + sigs.map(s => s.name).join(', ') : '') + (net ? `\nцепь: ${net}` : '');
  el('title', {}, gp, tip);

  if (p.type === 'io') {
    hitEl.addEventListener('dblclick', () => pinDialog(p.n));
    lab.addEventListener('dblclick', ev => { ev.stopPropagation(); inlineNetEdit(p.n, lab); });
  }
}

function renderLegend() {
  const banks = [...new Set(DEV.pins.filter(p => p.bank != null).map(p => p.bank))].sort();
  const items = banks.map(b => `<span><i style="background:${BANK_COLOR(b)}"></i>банк ${b}</span>`);
  items.push(`<span><i style="background:var(--pwr)"></i>питание</span>`, `<span><i style="background:var(--gnd)"></i>земля</span>`);
  const used = [['sys', 'такт/сброс'], ['gpio', 'GPIO'], ['tm1638', 'TM1638'], ['stim', 'STIM']];
  used.forEach(([k, t]) => items.push(`<span><i class="round" style="background:${blockColor(k)}"></i>${t}</span>`));
  if (model.core.debug) items.push(`<span><i class="round" style="background:var(--c-jtag)"></i>JTAG</span>`);
  document.getElementById('legend').innerHTML = items.join('');
}

//Нижняя таблица - как «I/O Constraints» во FloorPlanner: одна строка на назначенный вывод
function renderIoTable(v) {
  const sigs = signals(model).filter(s => s.pin != null).sort((a, b) => a.pin - b.pin);
  const d = model.ioDefaults;
  const sel = (pin, key, list, cur, def) => `<select data-pin="${pin}" data-key="${key}">` +
    `<option value="">${def}*</option>` + list.map(x => `<option${x === cur ? ' selected' : ''}>${x}</option>`).join('') + '</select>';
  const bad = new Set(v.issues.filter(i => i.lvl === 'err' && i.pin != null).map(i => i.pin));
  const dirRu = { input: 'вход', output: 'выход', inout: 'вход/выход' };
  const rows = sigs.map(s => {
    const p = PIN[s.pin] || {}, a = model.pins[s.pin] || {};
    return `<tr data-pin="${s.pin}" class="${bad.has(s.pin) ? 'bad' : ''}">
      <td class="mono">${esc(netOf(model, s.pin) || '—')}</td>
      <td><span class="dot" style="background:${blockColor(s.block)}"></span>${esc(s.name)}</td>
      <td>${dirRu[s.dir]}</td>
      <td class="mono">${s.pin}</td><td class="mono">${esc(p.name || '?')}</td><td>${p.bank ?? ''}</td>
      <td>${sel(s.pin, 'ioType', IO_TYPES, a.ioType, d.ioType)}</td>
      <td>${s.dir === 'input' ? '<span class="muted">—</span>' : sel(s.pin, 'drive', DRIVES, a.drive, d.drive)}</td>
      <td>${sel(s.pin, 'pull', PULLS, a.pull, d.pull)}</td>
      <td>${sel(s.pin, 'vccio', VCCIOS, a.vccio, d.vccio)}</td></tr>`;
  }).join('');
  document.getElementById('iotab').innerHTML = `<tr><th>Порт (цепь)</th><th>Сигнал</th><th>Направление</th><th>Вывод</th>
    <th>Площадка</th><th>Банк</th><th>IO_TYPE</th><th>DRIVE</th><th>PULL_MODE</th><th>BANK_VCCIO</th></tr>` + rows;
  document.getElementById('ioCount').textContent = `· ${sigs.length} · * - значение по умолчанию`;
  document.querySelectorAll('#iotab select').forEach(se => se.addEventListener('change', () => {
    const n = Number(se.dataset.pin), np = model.pins[n] || {};
    if (se.value) np[se.dataset.key] = se.value; else delete np[se.dataset.key];
    model.pins[n] = np;
    changed();
  }));
  document.querySelectorAll('#iotab tr[data-pin]').forEach(tr => {
    tr.addEventListener('click', e => { if (e.target.tagName !== 'SELECT') flashPin(Number(tr.dataset.pin)); });
    tr.addEventListener('dblclick', e => { if (e.target.tagName !== 'SELECT') pinDialog(Number(tr.dataset.pin)); });
  });
}

const blockColor = b => ({ sys: 'var(--c-sys)', gpio: 'var(--c-gpio)', tm1638: 'var(--c-tm1638)', stim: 'var(--c-stim)' }[b]);

// --- Блоки внутри кристалла ---
function tileDefs() {
  const m = model, b = m.blocks, am = addressMap(m), pll = pllOf(m);
  const baseTxt = k => { const s = am.baseOf(k); return s == null ? '<span class="bad">—</span>' : `<span class="v">${hexSlot(s)}</span>`; };
  const pinsOf = arr => arr.filter(x => x != null);
  const core = m.core;
  return [
    { key: 'clock', title: 'Такт и сброс', color: 'var(--c-sys)', editable: true, on: true,
      body: `Кварц <span class="v">${fmt(Number(m.clock.xtalMHz))} МГц</span> · вывод <span class="v">${m.clock.xtalPin ?? '—'}</span><br>
             rPLL <span class="v">${pll.errs.length ? '<span class="bad">ошибка</span>' : fmt(pll.fout) + ' МГц'}</span>
             <span class="dim">(${m.clock.pll.mode === 'auto' ? 'авто' : 'вручную'})</span><br>
             <span class="dim">IDIV ${m.clock.pll.idiv} · FBDIV ${m.clock.pll.fbdiv} · ODIV ${m.clock.pll.odiv}</span><br>
             Сброс rst_n · вывод <span class="v">${m.reset.pin ?? '—'}</span>` },
    { key: 'core', title: 'Ядро askoRV32', color: 'var(--c-core)', editable: true, on: true,
      body: `RV32I${core.mExt ? 'M' : ''}_Zicsr · ${core.coreType === 'pipeline' ? 'конвейер' : 'однотактное'}<br>
             IMEM <span class="v">${memTxt(core.imem)}</span> · DMEM <span class="v">${memTxt(core.dmem)}</span><br>
             <span class="dim">Настройки ядра - позже</span>` },
    { key: 'debug', title: 'Отладчик JTAG', color: 'var(--c-jtag)', editable: false, on: !!core.debug,
      body: core.debug ? `GW_JTAG · выводы <span class="v">5–8</span><br><span class="dim">OpenOCD, riscv-debug 0.13</span>` : 'выключен' },
    { key: 'gpio', toggle: true },
    { key: 'tm1638', toggle: true },
    { key: 'stim', toggle: true },
    { key: 'clint', title: 'CLINT', color: 'var(--c-core)', editable: false, on: true,
      body: `<span class="v">0x0200_0000</span><br><span class="dim">mtime = mcycle, msip</span>` },
    { key: 'plic', title: 'PLIC', color: 'var(--c-core)', editable: false, on: true,
      body: `<span class="v">0x0C00_0000</span><br><span class="dim">${core.plicSources ?? 8} источников → MEI</span>` },
    { key: 'mem', title: 'Шина memmux', color: 'var(--c-core)', editable: false, on: true,
      body: `DMEM <span class="v">0x1000_0000</span><br><span class="dim">окно 16 МБайт на блок</span>` },
  ].map(t => {
    if (!t.toggle) return t;
    const k = t.key, blk = b[k], meta = BLOCKS[k];
    let body;
    if (k === 'gpio') body = `Линий <span class="v">${blk.lines.length}</span> · выводы ${pinList(pinsOf(blk.lines))}`;
    if (k === 'tm1638') body = `DIO <span class="v">${blk.dio ?? '—'}</span> · CLK <span class="v">${blk.clk ?? '—'}</span> · STB <span class="v">${blk.stb ?? '—'}</span>`;
    if (k === 'stim') body = `${blk.width} бит · выход ${blk.out == null ? '<span class="dim">не выведен</span>' : `<span class="v">${blk.out}</span>`}<br><span class="dim">IRQ → LI0, PLIC 1</span>`;
    return { key: k, title: meta.title, color: meta.color, editable: true, toggle: true, on: blk.enabled,
             body: `${body}<br>Адрес ${baseTxt(k)}` };
  });
}
const memTxt = mm => mm ? (mm.type === 'bsram' ? `${mm.kb} КБ` : `${mm.synthWords * 4} Б`) : '?';
function pinList(a) {
  if (!a.length) return '<span class="dim">нет</span>';
  const s = a.slice(0, 6).join(', ') + (a.length > 6 ? '…' : '');
  return `<span class="v">${s}</span>`;
}

function drawTiles(svg) {
  const inner = G.body - 2 * (G.marg + 20);
  const x0 = G.o + G.marg + 20, y0 = G.o + G.marg + 70;
  const gap = 12, w = (inner - 2 * gap) / 3, h = (inner - 50 - 2 * gap) / 3;
  tileDefs().forEach((t, i) => {
    const x = x0 + (i % 3) * (w + gap), y = y0 + Math.floor(i / 3) * (h + gap);
    const fo = el('foreignObject', { class: 'tile-fo', x, y, width: w, height: h }, svg);
    const div = document.createElement('div');
    div.className = 'tile' + (t.on ? '' : ' off') + (t.editable && t.on ? ' editable' : '');
    div.dataset.block = t.key;
    div.innerHTML = `<div class="th"><span class="dot" style="background:${t.color}"></span><span class="name">${esc(t.title)}</span>
      ${t.toggle ? `<span class="switch${t.on ? ' on' : ''}" title="${t.on ? 'Выключить' : 'Включить'} блок"></span>` : ''}</div>
      <div class="tb">${t.on || !t.toggle ? t.body : '<span class="dim">выключен</span><br>' + esc(BLOCKS[t.key].about)}</div>`;
    fo.appendChild(div);
    if (t.toggle) div.querySelector('.switch').addEventListener('click', ev => { ev.stopPropagation(); toggleBlock(t.key); });
    div.addEventListener('dblclick', ev => {
      if (ev.target.classList.contains('switch')) return;
      if (!t.on) { setStatus(`Блок ${t.title} выключен - включите его переключателем`, ''); return; }
      if (t.key === 'clock') clockDialog();
      else if (t.key === 'core') coreDialog();
      else if (BLOCKS[t.key]) blockDialog(t.key);
    });
    div.addEventListener('mouseenter', () => highlightBlock(t.key === 'clock' ? 'sys' : t.key, true));
    div.addEventListener('mouseleave', () => highlightBlock(null, false));
  });
}

function highlightBlock(block, on) {
  document.querySelectorAll('#chip .pin').forEach(g => {
    g.classList.toggle('dim', on && !g.classList.contains('b-' + block));
  });
}

function toggleBlock(k) {
  const b = model.blocks[k];
  b.enabled = !b.enabled;
  if (b.enabled) signals(model).filter(s => s.block === k).forEach(s => ensureNet(model, s));
  changed();
}

// --- Правая панель ---
function renderSide(v) {
  const am = addressMap(model);
  const t = document.getElementById('amap');
  t.innerHTML = am.rows.map(r => `<tr class="${r.on ? '' : 'off'}">
      <td class="addr">${r.slot == null ? '—' : hexSlot(r.slot)}</td>
      <td><span class="sw" style="background:${r.color}"></span>${esc(r.name)}${r.fixed ? '' : (r.auto ? ' <span class="muted">авто</span>' : '')}</td>
      <td class="muted">${r.on ? esc(r.note) : 'выключен'}</td></tr>`).join('');

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
    ul.appendChild(li);
  });
}

function flashPin(n) {
  const g = document.querySelector(`#chip .pin[data-pin="${n}"]`);
  if (!g) return;
  g.classList.remove('flash'); void g.getBoundingClientRect(); g.classList.add('flash');
  g.scrollIntoView({ block: 'center', inline: 'center', behavior: 'smooth' });
}

// --- Масштаб ---
function applyZoom() {
  const svg = document.getElementById('chip'), c = document.getElementById('canvas');
  const s = zoom || Math.max(0.4, Math.min((c.clientWidth - 16) / G.size, (c.clientHeight - 16) / G.size));
  svg.setAttribute('width', Math.round(G.size * s));
  svg.setAttribute('height', Math.round(G.size * s));
}
function currentScale() { return document.getElementById('chip').getBoundingClientRect().width / G.size; }

// ============================================================================================
// Редактирование
// ============================================================================================
function changed() {
  dirty = true;
  host('dirty');
  render();
}

function inlineNetEdit(n, labEl) {
  const rc = labEl.getBoundingClientRect();
  const inp = document.createElement('input');
  inp.className = 'inline-edit';
  inp.value = netOf(model, n);
  inp.placeholder = 'имя цепи';
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
  dlgApply = onApply;
  d.returnValue = '';
  if (onOpen) onOpen(document.getElementById('dlgBody'));
  d.showModal();
}
document.getElementById('dlg').addEventListener('close', () => {
  const d = document.getElementById('dlg');
  if (d.returnValue === 'ok' && dlgApply) { dlgApply(document.getElementById('dlgBody')); changed(); }
  dlgApply = null;
});

function pinOptions(selected, forSignal) {
  const owner = new Map();
  signals(model).forEach(s => { if (s.pin != null && s.id !== forSignal) owner.set(s.pin, s.name); });
  let h = `<option value="">— не подключён —</option>`;
  for (const n of IO_PINS) {
    const p = PIN[n];
    const jt = model.core.debug && JTAG_PINS[n];
    const who = owner.get(n);
    const lbl = `${n} · ${p.name} · банк ${p.bank}${p.cfg ? ' · ' + p.cfg : ''}${jt ? ' (JTAG)' : ''}${who ? '  ← ' + who : ''}`;
    h += `<option value="${n}"${n === selected ? ' selected' : ''}${jt ? ' disabled' : ''}>${esc(lbl)}</option>`;
  }
  return h;
}
const netInput = (pin, name) => `<input type="text" class="mono" name="${name}" value="${esc(pin != null ? netOf(model, pin) : '')}" placeholder="имя цепи">`;

function baseField(k) {
  const b = model.blocks[k];
  const auto = parseBase(b.base) === null;
  return `<label>Адрес регистров</label>
    <div><select name="baseMode"><option value="auto"${auto ? ' selected' : ''}>авто</option><option value="manual"${auto ? '' : ' selected'}>вручную</option></select>
    <input type="text" class="mono" name="base" value="${auto ? hexSlot(addressMap(model).baseOf(k) ?? BLOCKS[k].slot) : esc(b.base)}" ${auto ? 'disabled' : ''} style="width:130px"></div>`;
}
function wireBaseField(body) {
  const mode = body.querySelector('[name=baseMode]'), base = body.querySelector('[name=base]');
  mode.addEventListener('change', () => { base.disabled = mode.value === 'auto'; });
}
function readBase(body) {
  const mode = body.querySelector('[name=baseMode]').value;
  return mode === 'auto' ? 'auto' : body.querySelector('[name=base]').value.trim().replace(/_/g, '');
}

//Строки «сигнал - вывод - имя цепи»: применение с учётом имён
function applySignalRows(body, rows) {
  //Сначала снимаются старые назначения, затем ставятся новые (чтобы обмен выводами работал)
  const plan = rows.map(r => ({ id: r.id, def: r.def, pin: body.querySelector(`[name=pin_${r.key}]`).value,
                                 net: body.querySelector(`[name=net_${r.key}]`).value.trim() }));
  plan.forEach(p => setSignalPin(model, p.id, null));
  plan.forEach(p => {
    setSignalPin(model, p.id, p.pin);
    if (p.pin !== '') {
      if (p.net) setNet(model, Number(p.pin), p.net);
      else ensureNet(model, { pin: Number(p.pin), def: p.def });
    }
  });
}
function signalRowsHtml(rows) {
  return `<table class="sig-table"><tr><th style="width:110px">Сигнал</th><th>Вывод</th><th style="width:170px">Имя цепи</th></tr>` +
    rows.map(r => `<tr><td>${esc(r.label)}</td><td><select name="pin_${r.key}">${pinOptions(r.pin, r.id)}</select></td>
                   <td>${netInput(r.pin, 'net_' + r.key)}</td></tr>`).join('') + `</table>`;
}
//Смена вывода в строке подставляет имя цепи нового вывода
function wireSignalRows(body) {
  body.querySelectorAll('select[name^=pin_]').forEach(sel => sel.addEventListener('change', () => {
    const key = sel.name.slice(4), inp = body.querySelector(`[name=net_${key}]`);
    inp.value = sel.value === '' ? '' : netOf(model, Number(sel.value));
  }));
}

// --- Диалог блока ---
function blockDialog(k) {
  const meta = BLOCKS[k], b = model.blocks[k];
  if (k === 'gpio') {
    const rowsFor = count => Array.from({ length: count }, (_, i) =>
      ({ key: String(i), id: 'gpio.' + i, def: 'gpio' + i, label: 'Линия ' + i, pin: b.lines[i] ?? null }));
    const html = cnt => `<div class="form-grid">
        <label>Количество линий</label><div><input type="number" name="count" min="1" max="32" value="${cnt}" style="width:80px">
        <span class="muted"> разрядность регистров GPIO = числу линий</span></div>
        ${baseField(k)}</div>
        <div id="gpioRows">${signalRowsHtml(rowsFor(cnt))}</div>
        <p class="note">Регистры: +0x00 направление (1 - выход), +0x04 выход, +0x08 состояние входов.</p>`;
    openDialog(`GPIO - ${meta.about}`, meta.color, html(b.lines.length), body => {
      const cnt = Number(body.querySelector('[name=count]').value);
      const rows = rowsFor(cnt);
      b.lines = b.lines.slice(0, cnt);
      while (b.lines.length < cnt) b.lines.push(null);
      applySignalRows(body, rows);
      b.base = readBase(body);
    }, body => {
      wireBaseField(body); wireSignalRows(body);
      const cntInp = body.querySelector('[name=count]');
      cntInp.addEventListener('change', () => {
        const cnt = Math.max(1, Math.min(32, Number(cntInp.value) || 1));
        cntInp.value = cnt;
        //Сохранить введённое в уже показанных строках
        const keep = {};
        body.querySelectorAll('select[name^=pin_]').forEach(s => { const key = s.name.slice(4);
          keep[key] = { pin: s.value, net: body.querySelector(`[name=net_${key}]`).value }; });
        body.querySelector('#gpioRows').innerHTML = signalRowsHtml(rowsFor(cnt));
        for (const key in keep) {
          const s = body.querySelector(`[name=pin_${key}]`); if (!s) continue;
          s.value = keep[key].pin; body.querySelector(`[name=net_${key}]`).value = keep[key].net;
        }
        wireSignalRows(body);
      });
    });
  }
  if (k === 'tm1638') {
    const rows = [['dio', 'DIO (данные)'], ['clk', 'CLK (такт)'], ['stb', 'STB (строб)']].map(([key, label]) =>
      ({ key, id: 'tm1638.' + key, def: 'tm_' + key, label, pin: b[key] }));
    openDialog(`TM1638 - ${meta.about}`, meta.color,
      `<div class="form-grid">${baseField(k)}</div>${signalRowsHtml(rows)}
       <p class="note">Делители интерфейса считаются от частоты шины (rPLL).</p>`,
      body => { applySignalRows(body, rows); b.base = readBase(body); },
      body => { wireBaseField(body); wireSignalRows(body); });
  }
  if (k === 'stim') {
    const rows = [{ key: 'out', id: 'stim.out', def: 'stim_out', label: 'Выход ШИМ', pin: b.out }];
    openDialog(`STIM - ${meta.about}`, meta.color,
      `<div class="form-grid">
        <label>Разрядность</label><div><select name="width">${[16, 32].map(w => `<option${w === b.width ? ' selected' : ''}>${w}</option>`).join('')}</select>
          <span class="muted"> предделитель, период, сравнение, счётчик</span></div>
        ${baseField(k)}</div>${signalRowsHtml(rows)}
       <p class="note">«Не подключён» - таймер работает только на прерывание, выход ШИМ не выводится.</p>`,
      body => {
        b.width = Number(body.querySelector('[name=width]').value);
        const pin = body.querySelector('[name=pin_out]').value;
        b.out = pin === '' ? null : Number(pin);
        if (b.out != null) applySignalRows(body, rows);
        b.base = readBase(body);
      },
      body => { wireBaseField(body); wireSignalRows(body); });
  }
}

// --- Диалог тактирования ---
function clockDialog() {
  const c = model.clock, p = c.pll;
  const clkPins = IO_PINS.filter(clockCapable);
  const xtalOpts = IO_PINS.map(n => { const q = PIN[n];
    return `<option value="${n}"${n === c.xtalPin ? ' selected' : ''}>${clockCapable(n) ? '★ ' : ''}${n} · ${q.name}${q.cfg ? ' · ' + q.cfg : ''}</option>`; }).join('');
  const rows = [{ key: 'rst', id: 'rst', def: 'rst_n', label: 'Сброс rst_n', pin: model.reset.pin }];
  openDialog('Тактирование и сброс', 'var(--c-sys)', `
    <div class="form-grid">
      <label>Частота кварца, МГц</label><input type="number" name="xtal" step="any" min="3" max="400" value="${c.xtalMHz}" style="width:110px">
      <label>Вывод кварца</label><select name="xtalPin">${xtalOpts}</select>
      <label>Имя цепи кварца</label>${netInput(c.xtalPin, 'xtalNet')}
      <label>Расчёт rPLL</label><div>
        <label style="color:inherit"><input type="radio" name="mode" value="auto"${p.mode === 'auto' ? ' checked' : ''}> по частоте</label>&nbsp;&nbsp;
        <label style="color:inherit"><input type="radio" name="mode" value="manual"${p.mode !== 'auto' ? ' checked' : ''}> делители вручную</label></div>
      <label>Нужная частота, МГц</label><input type="number" name="target" step="any" value="${p.targetMHz}" style="width:110px">
      <label>IDIV_SEL · FBDIV_SEL · ODIV_SEL</label><div>
        <input type="number" name="idiv" min="0" max="63" value="${p.idiv}" style="width:64px">
        <input type="number" name="fbdiv" min="0" max="63" value="${p.fbdiv}" style="width:64px">
        <select name="odiv">${ODIV_SET.map(o => `<option${o === p.odiv ? ' selected' : ''}>${o}</option>`).join('')}</select></div>
      <div class="full readout" id="pllOut"></div>
    </div>
    ${signalRowsHtml(rows)}
    <p class="note">★ - выводы с глобальным тактом (GCLK) или входом PLL: ${clkPins.join(', ')}.
    f<sub>out</sub> = f<sub>кв</sub>·(FBDIV+1)/(IDIV+1); PFD = f<sub>кв</sub>/(IDIV+1) ≥ 3 МГц; VCO = f<sub>out</sub>·ODIV = 400..1200 МГц.
    При смене частоты обновите период в riscv.sdc и SYSCLK_HZ в прошивке.</p>`,
    body => {
      const q = name => body.querySelector(`[name=${name}]`);
      c.xtalMHz = Number(q('xtal').value);
      p.mode = body.querySelector('[name=mode]:checked').value;
      p.targetMHz = Number(q('target').value);
      p.idiv = Number(q('idiv').value); p.fbdiv = Number(q('fbdiv').value); p.odiv = Number(q('odiv').value);
      applyPllAuto(model);
      c.xtalPin = Number(q('xtalPin').value);
      const net = q('xtalNet').value.trim();
      if (net) setNet(model, c.xtalPin, net); else ensureNet(model, { pin: c.xtalPin, def: 'clk' });
      applySignalRows(body, rows);
    },
    body => {
      wireSignalRows(body);
      const q = name => body.querySelector(`[name=${name}]`);
      q('xtalPin').addEventListener('change', () => { q('xtalNet').value = netOf(model, Number(q('xtalPin').value)); });
      const upd = () => {
        const auto = body.querySelector('[name=mode]:checked').value === 'auto';
        ['idiv', 'fbdiv', 'odiv'].forEach(n => { q(n).disabled = auto; });
        q('target').disabled = !auto;
        const fin = Number(q('xtal').value);
        if (auto) {
          const r = pllSolve(fin, Number(q('target').value));
          if (r) { q('idiv').value = r.idiv; q('fbdiv').value = r.fbdiv; q('odiv').value = r.odiv; }
        }
        const e = pllEval(fin, Number(q('idiv').value), Number(q('fbdiv').value), Number(q('odiv').value));
        body.querySelector('#pllOut').innerHTML =
          `CLKOUT = <b class="${e.errs.length ? 'bad' : 'good'}">${fmt(e.fout)} МГц</b>` +
          (auto ? ` <span class="muted">(нужно ${fmt(Number(q('target').value))}, ошибка ${fmt(Math.abs(e.fout - Number(q('target').value)))} МГц)</span>` : '') +
          `<br>PFD = ${fmt(e.pfd)} МГц · VCO = ${fmt(e.vco)} МГц` +
          (e.errs.length ? `<br><span class="bad">${e.errs.map(esc).join('<br>')}</span>` : '');
      };
      body.querySelectorAll('input, select').forEach(i => { i.addEventListener('input', upd); i.addEventListener('change', upd); });
      upd();
    });
}

// --- Диалог ядра (пока только просмотр) ---
function coreDialog() {
  const c = model.core;
  const row = (k, v) => `<label>${k}</label><div class="mono">${esc(v)}</div>`;
  openDialog('Ядро askoRV32', 'var(--c-core)', `<div class="form-grid">
      ${row('Тип', c.coreType === 'pipeline' ? 'конвейерное (5 стадий)' : 'однотактное')}
      ${row('Расширение M', c.mExt ? `да, деление ${c.divBpc} бит/такт` : 'нет')}
      ${row('IMEM', `${c.imem.type === 'bsram' ? 'BSRAM' : 'синтезированная'}, ${memTxt(c.imem)}`)}
      ${row('DMEM', `${c.dmem.type === 'bsram' ? 'BSRAM' : 'синтезированная'}, ${memTxt(c.dmem)}`)}
      ${row('Отладчик JTAG', c.debug ? 'включён (выводы 5–8)' : 'выключен')}
      ${row('Источники PLIC', String(c.plicSources))}
    </div><p class="note">Параметры ядра хранятся в файле .gwsoc и попадают в top.sv. Их редактирование - следующий шаг.</p>`,
    null);
  document.getElementById('dlgOk').style.display = 'none';
  document.getElementById('dlg').addEventListener('close', () => { document.getElementById('dlgOk').style.display = ''; }, { once: true });
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
    `<option value="${s.id}"${cur.length && cur[0].id === s.id ? ' selected' : ''}>${esc(s.name)}${s.pin != null && s.pin !== n ? ' (сейчас ' + s.pin + ')' : ''}</option>`).join('');
  const info = [`<span>${p.name}</span>`, `<span>банк ${p.bank}</span>`];
  if (p.cfg) info.push(`<span>${esc(p.cfg)}</span>`);
  if (p.diff) info.push(`<span>${p.diff === 'P' ? 'плюс' : 'минус'} пары с ${p.pair}</span>`);
  if (p.lvds) info.push('<span>True LVDS</span>');
  const d = model.ioDefaults;
  openDialog(`Вывод ${n}`, cur.length ? blockColor(cur[0].block) : null, `
    <div class="pininfo">${info.join('')}</div>
    <div class="form-grid">
      <label>Сигнал</label><select name="sig">${sigOpts}</select>
      <label>Имя цепи</label>${netInput(n, 'net')}
      <label>IO_TYPE</label><select name="ioType">${opt(IO_TYPES, pa.ioType, d.ioType)}</select>
      <label>PULL_MODE</label><select name="pull">${opt(PULLS, pa.pull, d.pull)}</select>
      <label>DRIVE, мА</label><select name="drive">${opt(DRIVES, pa.drive, d.drive)}</select>
      <label>BANK_VCCIO, В</label><select name="vccio">${opt(VCCIOS, pa.vccio, d.vccio)}</select>
    </div>
    ${cur.length > 1 ? `<p class="note" style="color:var(--error)">На вывод назначено несколько сигналов: ${cur.map(s => esc(s.name)).join(', ')}</p>` : ''}
    <p class="note">Выключенные блоки в списке сигналов не показаны. Имя цепи без сигнала - просто подпись, в riscv.cst она не попадает.</p>`,
    body => {
      const q = name => body.querySelector(`[name=${name}]`);
      const sig = q('sig').value;
      //Снять с вывода прежние сигналы, кроме выбранного
      cur.forEach(s => { if (s.id !== sig) setSignalPin(model, s.id, null); });
      if (sig) setSignalPin(model, sig, n);
      setNet(model, n, q('net').value);
      if (sig) ensureNet(model, Object.assign({}, sigs.find(s => s.id === sig), { pin: n }));
      const np = model.pins[n] || {};
      for (const k of ['ioType', 'pull', 'drive', 'vccio']) { const v = q(k).value; if (v) np[k] = v; else delete np[k]; }
      if (Object.keys(np).length) model.pins[n] = np; else delete model.pins[n];
    });
}

function ioDefaultsDialog() {
  const d = model.ioDefaults;
  const sel = (name, list, v) => `<select name="${name}">${list.map(x => `<option${x === v ? ' selected' : ''}>${x}</option>`).join('')}</select>`;
  openDialog('Стандарты I/O по умолчанию', null, `<div class="form-grid">
      <label>IO_TYPE</label>${sel('ioType', IO_TYPES, d.ioType)}
      <label>PULL_MODE</label>${sel('pull', PULLS, d.pull)}
      <label>DRIVE, мА</label>${sel('drive', DRIVES, d.drive)}
      <label>BANK_VCCIO, В</label>${sel('vccio', VCCIOS, d.vccio)}
    </div><p class="note">Действуют для выводов без собственных настроек. DRIVE пишется только для выходов.</p>`,
    body => { for (const k of ['ioType', 'pull', 'drive', 'vccio']) d[k] = body.querySelector(`[name=${k}]`).value; });
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
    const flat = keys.every(k => v[k] === null || typeof v[k] !== 'object');
    const one = '{ ' + keys.map(k => JSON.stringify(k) + ': ' + JSON.stringify(v[k])).join(', ') + ' }';
    if (flat && one.length + ind.length < 110) return one;
    return '{\n' + keys.map(k => inner + JSON.stringify(k) + ': ' + toJson(v[k], inner)).join(',\n') + '\n' + ind + '}';
  }
  return JSON.stringify(v);
}
function pinsSorted(p) {
  const o = {};
  Object.keys(p).sort((a, b) => Number(a) - Number(b)).forEach(k => { o[k] = p[k]; });
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
      applyPllAuto(model);
      dirty = false;
      document.getElementById('devname').textContent = model.device || DEV.part;
      document.getElementById('toolchain').value = model.build.toolchain;
      render();
      setStatus('', '');
    } catch (e) { setStatus('Ошибка чтения файла .gwsoc: ' + e.message, 'err'); }
  },
  getJson() {
    model.pins = pinsSorted(model.pins);
    return toJson(model) + '\n';
  },
  saved() { dirty = false; setStatus('Сохранено', 'ok'); },
  status(text, kind) { setStatus(text, kind); },
  hasErrors() { return validate(model).issues.some(i => i.lvl === 'err'); },
};

function doSave() {
  if (!inHost()) { setStatus('Сохранение доступно при запуске из Eclipse', ''); return; }
  host('save', window.gwsoc.getJson());
}
function doBuild() {
  const errs = validate(model).issues.filter(i => i.lvl === 'err');
  if (errs.length) { setStatus(`Сборка невозможна: ошибок ${errs.length} (см. «Проверка»)`, 'err'); return; }
  if (!inHost()) { setStatus('Сборка доступна при запуске из Eclipse', ''); return; }
  setStatus('Сборка…', '');
  host('build', window.gwsoc.getJson());
}

document.getElementById('save').addEventListener('click', doSave);
document.getElementById('toolchain').addEventListener('change', e => {
  if (!model) return;
  model.build.toolchain = e.target.value;
  changed();
});
document.getElementById('build').addEventListener('click', doBuild);
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
window.addEventListener('resize', () => { if (!zoom) applyZoom(); });
document.addEventListener('keydown', e => {
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's') { e.preventDefault(); doSave(); }
});

//Запуск: в Eclipse файл передаёт редактор (gwsoc.load), в браузере - параметр ?cfg=<url>
window.addEventListener('DOMContentLoaded', () => {
  if (inHost()) { host('ready'); return; }
  const cfg = new URLSearchParams(location.search).get('cfg');
  //В Eclipse функция gwsocHost может появиться позже DOMContentLoaded - файл тогда передаст редактор
  if (!cfg) { setStatus('Загрузка конфигурации…', ''); return; }
  fetch(cfg).then(r => r.text()).then(t => window.gwsoc.load(t)).catch(e => setStatus('Не удалось загрузить ' + cfg + ': ' + e.message, 'err'));
});
