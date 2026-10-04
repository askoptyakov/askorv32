package ru.askorv32.rectgui;

import java.util.Locale;
import java.util.Map;
import java.util.prefs.Preferences;

import org.eclipse.swt.SWT;
import org.eclipse.swt.custom.SashForm;
import org.eclipse.swt.custom.ScrolledComposite;
import org.eclipse.swt.graphics.Color;
import org.eclipse.swt.graphics.Font;
import org.eclipse.swt.graphics.FontData;
import org.eclipse.swt.layout.GridData;
import org.eclipse.swt.layout.GridLayout;
import org.eclipse.swt.widgets.Button;
import org.eclipse.swt.widgets.Combo;
import org.eclipse.swt.widgets.Composite;
import org.eclipse.swt.widgets.Display;
import org.eclipse.swt.widgets.Group;
import org.eclipse.swt.widgets.Label;
import org.eclipse.swt.widgets.Spinner;
import org.eclipse.swt.widgets.Text;
import org.eclipse.ui.part.ViewPart;

/**
 * Панель «Пульт выпрямителя»: управление выпрямителем askoRV32 по UART (ветки hw_rect, fw_rect).
 * Режим (имитатор сети / сеть и угол / сеть и ПИ-регулятор), импульсы вкл/выкл, задание и коэффициенты
 * регуляторов, измерения, биты ошибок и осциллограмма U и I (кадр 20 мс раз в секунду, запуск по фронту).
 * Протокол - hw/info/rectifier_gui.md; связь - RectLink, осциллограмма - ScopeCanvas.
 */
public class RectView extends ViewPart {
    public static final String ID = "ru.askorv32.rectgui.view";
    private static final Preferences PREFS = Preferences.userRoot().node("ru/askorv32/rectgui");
    private static final String[] MODES = { "Имитатор сети, угол вручную", "Сеть, угол вручную", "Сеть, ПИ-регулятор (U с ограничением I)" };
    private static final String[] LOCAL = { "импульсы сняты", "DI1 - имитатор, угол", "DI2 - сеть, угол", "DI3 - сеть, ПИ-регулятор", "несколько DI - импульсы сняты" };
    private static final String[][] ERRORS = {     //Бит #S err: подпись, пояснение
        { "Нет сети", "нет напряжения сети на входах синхронизации (или имитатор выключен)" },
        { "Нет синхронизации", "фазы сети не следуют по порядку: обрыв входа платы NSB" },
        { "Была потеря синхронизации", "защёлкнуто до «Сбросить»" },
        { "АЦП U: ошибка кадра", "плата напряжения не отвечает или перезапускалась; защёлкнуто" },
        { "АЦП I: ошибка кадра", "плата тока не отвечает или перезапускалась; защёлкнуто" },
        { "Компаратор платы U", "вход CMP платы напряжения сработал" },
        { "Защита по току (CMP I)", "компаратор мгновенного тока платы тока сработал" },
        { "Несколько DI", "включено несколько входов DI: импульсы сняты (местное управление)" },
    };

    private RectLink link;
    private Display display;
    private Combo portCombo;
    private Button connect, remote, onOff, scopeOn, zero, freeze;
    private final Button[] modeBtn = new Button[3];
    private Label linkState, runState, measU, measI, measA, measF, measReg, frameInfo;
    private final Label[] errLamp = new Label[ERRORS.length];
    private Text uSet, iLim, alpha, kpU, kiU, kpI, kiI, log;
    private Combo trigSrc, trigEdge;
    private Text trigLevel;
    private Spinner trigPos;
    private ScopeCanvas scope;
    private Color green, red, gray, amber;
    private Font bigFont;

    private boolean updating;                   //Поля заполняет программа - не слать команды
    private long lastStatus;
    private Map<String, Integer> st;            //Последнее состояние #S
    private ScopeCanvas.Cal calU = ScopeCanvas.Cal.RAW, calI = ScopeCanvas.Cal.RAW;
    private int scopeN = 400;
    private int amax10 = 1200;
    private boolean haveInfo;                   //Сведения стенда (#I: калибровка каналов) получены
    private int infoTicks;

    @Override
    public void createPartControl(Composite parent) {
        display = parent.getDisplay();
        green = new Color(22, 163, 74);
        red = new Color(220, 38, 38);
        amber = new Color(217, 119, 6);
        gray = new Color(156, 163, 175);
        FontData fd = parent.getFont().getFontData()[0];
        bigFont = new Font(display, fd.getName(), fd.getHeight() + 3, SWT.BOLD);
        parent.addDisposeListener(e -> {
            for (Color c : new Color[] { green, red, amber, gray }) c.dispose();
            bigFont.dispose();
        });

        parent.setLayout(grid(1, 4, 4));
        createTopBar(parent);
        SashForm vs = new SashForm(parent, SWT.VERTICAL);
        vs.setLayoutData(new GridData(SWT.FILL, SWT.FILL, true, true));
        SashForm hs = new SashForm(vs, SWT.HORIZONTAL);
        createLeft(hs);
        createScope(hs);
        hs.setWeights(28, 72);
        log = new Text(vs, SWT.MULTI | SWT.READ_ONLY | SWT.V_SCROLL | SWT.BORDER);
        vs.setWeights(85, 15);

        link = new RectLink(new RectLink.Listener() {
            @Override
            public void status(Map<String, Integer> s) {
                ui(() -> onStatus(s));
            }

            @Override
            public void info(Map<String, Integer> i, String fw) {
                ui(() -> onInfo(i, fw));
            }

            @Override
            public void frame(RectLink.Frame f) {
                ui(() -> onFrame(f));
            }

            @Override
            public void text(String line) {
                ui(() -> addLog(line));
            }

            @Override
            public void closed(String why) {
                ui(() -> onClosed(why));
            }
        });
        setConnected(false);
        display.timerExec(500, this::watchdog);
    }

    private static GridLayout grid(int cols, int mw, int mh) {
        GridLayout g = new GridLayout(cols, false);
        g.marginWidth = mw;
        g.marginHeight = mh;
        return g;
    }

    private void ui(Runnable r) {
        if (display == null || display.isDisposed()) return;
        display.asyncExec(() -> {
            if (portCombo != null && !portCombo.isDisposed()) r.run();
        });
    }

    // --------------------------------------------------------------------------------------------
    // Разметка
    // --------------------------------------------------------------------------------------------
    private void createTopBar(Composite parent) {
        Composite c = new Composite(parent, SWT.NONE);
        c.setLayout(grid(5, 0, 0));
        c.setLayoutData(new GridData(SWT.FILL, SWT.CENTER, true, false));
        new Label(c, SWT.NONE).setText("Порт:");
        portCombo = new Combo(c, SWT.DROP_DOWN);
        portCombo.setLayoutData(new GridData(90, SWT.DEFAULT));
        Button refresh = new Button(c, SWT.PUSH);
        refresh.setText("Обновить");
        refresh.setToolTipText("Перечитать список COM-портов");
        refresh.addListener(SWT.Selection, e -> fillPorts());
        connect = new Button(c, SWT.PUSH);
        connect.setText("Подключить");
        connect.addListener(SWT.Selection, e -> toggleConnect());
        linkState = new Label(c, SWT.NONE);
        linkState.setLayoutData(new GridData(SWT.FILL, SWT.CENTER, true, false));
        fillPorts();
    }

    private void createLeft(Composite parent) {
        ScrolledComposite sc = new ScrolledComposite(parent, SWT.V_SCROLL | SWT.H_SCROLL);
        Composite c = new Composite(sc, SWT.NONE);
        c.setLayout(grid(1, 2, 2));
        sc.setContent(c);
        sc.setExpandHorizontal(true);
        sc.setExpandVertical(true);

        //Управление
        Group g = group(c, "Управление", 1);
        remote = new Button(g, SWT.CHECK);
        remote.setText("Управление с ПК");
        remote.setToolTipText("Режим и импульсы задаёт пульт, входы DI не действуют. Перехват без удара: текущий режим продолжается. "
                + "Пульт отключён или молчит 3 с - управление снова местное (DI)");
        remote.addListener(SWT.Selection, e -> {
            if (!updating) send("@R " + (remote.getSelection() ? 1 : 0));
        });
        for (int k = 0; k < 3; k++) {
            final int m = k + 1;
            modeBtn[k] = new Button(g, SWT.RADIO);
            modeBtn[k].setText(MODES[k]);
            modeBtn[k].addListener(SWT.Selection, e -> {
                if (!updating && modeBtn[m - 1].getSelection()) send("@M " + m);
            });
        }
        modeBtn[0].setToolTipText("Синхронизация от имитатора сети в ПЛИС (50 Гц). Только без силовой части под напряжением!");
        onOff = new Button(g, SWT.PUSH);
        onOff.setFont(bigFont);
        GridData od = new GridData(SWT.FILL, SWT.CENTER, true, false);
        od.heightHint = 40;
        onOff.setLayoutData(od);
        onOff.setText("ВКЛЮЧИТЬ");
        onOff.addListener(SWT.Selection, e -> {
            if (st != null) send("@E " + (st.getOrDefault("on", 0) != 0 ? 0 : 1));
        });
        runState = new Label(g, SWT.WRAP);
        runState.setLayoutData(new GridData(SWT.FILL, SWT.CENTER, true, false));

        //Задание
        g = group(c, "Задание", 3);
        uSet = field(g, "Напряжение", "В", "Задание напряжения (режим ПИ-регулятора)");
        iLim = field(g, "Ограничение тока", "А", "Выше - регулятор тока снижает напряжение");
        alpha = field(g, "Угол α", "град.", "Угол управления в ручных режимах (0..AMAX)");
        Button apply = new Button(g, SWT.PUSH);
        apply.setText("Записать");
        apply.setLayoutData(new GridData(SWT.END, SWT.CENTER, false, false, 3, 1));
        apply.addListener(SWT.Selection, e -> applySet());

        //Коэффициенты
        g = group(c, "ПИ-регуляторы (K за шаг)", 3);
        kpU = field(g, "KP напряжения", "", "Пропорциональный коэффициент PI_U (0..15,99; в стенд - K * 4096)");
        kiU = field(g, "KI напряжения", "", "Интегральный коэффициент PI_U");
        kpI = field(g, "KP тока", "", "Пропорциональный коэффициент PI_I");
        kiI = field(g, "KI тока", "", "Интегральный коэффициент PI_I");
        Button applyK = new Button(g, SWT.PUSH);
        applyK.setText("Записать");
        applyK.setLayoutData(new GridData(SWT.END, SWT.CENTER, false, false, 3, 1));
        applyK.addListener(SWT.Selection, e -> applyGains());

        //Измерения
        g = group(c, "Измерения", 1);
        measU = big(g);
        measI = big(g);
        measA = new Label(g, SWT.NONE);
        measF = new Label(g, SWT.NONE);
        measReg = new Label(g, SWT.WRAP);
        for (Label l : new Label[] { measA, measF, measReg }) l.setLayoutData(new GridData(SWT.FILL, SWT.CENTER, true, false));

        //Ошибки
        g = group(c, "Ошибки", 2);
        for (int k = 0; k < ERRORS.length; k++) {
            errLamp[k] = new Label(g, SWT.NONE);
            errLamp[k].setText("●");
            errLamp[k].setForeground(gray);
            Label t = new Label(g, SWT.NONE);
            t.setText(ERRORS[k][0]);
            t.setToolTipText(ERRORS[k][1]);
            errLamp[k].setToolTipText(ERRORS[k][1]);
        }
        Button clr = new Button(g, SWT.PUSH);
        clr.setText("Сбросить защёлкнутые");
        clr.setLayoutData(new GridData(SWT.BEGINNING, SWT.CENTER, false, false, 2, 1));
        clr.addListener(SWT.Selection, e -> send("@X"));

        sc.setMinSize(c.computeSize(SWT.DEFAULT, SWT.DEFAULT));
    }

    private void createScope(Composite parent) {
        Composite c = new Composite(parent, SWT.NONE);
        c.setLayout(grid(1, 0, 0));
        scope = new ScopeCanvas(c);
        scope.setLayoutData(new GridData(SWT.FILL, SWT.FILL, true, true));
        Composite b = new Composite(c, SWT.NONE);
        b.setLayout(grid(12, 2, 2));
        b.setLayoutData(new GridData(SWT.FILL, SWT.CENTER, true, false));
        scopeOn = new Button(b, SWT.CHECK);
        scopeOn.setText("Осциллограмма");
        scopeOn.setToolTipText("Кадр 20 мс (400 точек на канал) раз в секунду");
        scopeOn.setSelection(PREFS.getBoolean("scope", true));
        scopeOn.addListener(SWT.Selection, e -> {
            PREFS.putBoolean("scope", scopeOn.getSelection());
            send("@O " + (scopeOn.getSelection() ? 1 : 0));
        });
        new Label(b, SWT.NONE).setText("  Запуск:");
        trigSrc = new Combo(b, SWT.READ_ONLY);
        trigSrc.setItems("по U", "по I");
        trigSrc.select(PREFS.getInt("src", 0));
        trigEdge = new Combo(b, SWT.READ_ONLY);
        trigEdge.setItems("передний фронт ↑", "задний фронт ↓", "без запуска");
        trigEdge.select(PREFS.getInt("edge", 0));
        new Label(b, SWT.NONE).setText("уровень");
        trigLevel = new Text(b, SWT.BORDER | SWT.RIGHT);
        trigLevel.setLayoutData(new GridData(60, SWT.DEFAULT));
        trigLevel.setText(PREFS.get("level", "0"));
        trigLevel.setToolTipText("Уровень запуска в единицах канала (гистерезис - 16 кодов АЦП). Линию можно тащить мышью");
        new Label(b, SWT.NONE).setText("положение, %");
        trigPos = new Spinner(b, SWT.BORDER);
        trigPos.setValues(PREFS.getInt("pos", 25), 0, 99, 0, 5, 10);
        trigPos.setToolTipText("Сколько кадра до точки запуска. Вертикальную линию можно тащить мышью");
        zero = new Button(b, SWT.CHECK);
        zero.setText("ноль на шкале");
        zero.setSelection(PREFS.getBoolean("zero", true));
        freeze = new Button(b, SWT.CHECK);
        freeze.setText("стоп-кадр");
        frameInfo = new Label(b, SWT.NONE);
        frameInfo.setLayoutData(new GridData(SWT.FILL, SWT.CENTER, true, false, 12, 1));
        trigSrc.addListener(SWT.Selection, e -> trigChanged());
        trigEdge.addListener(SWT.Selection, e -> trigChanged());
        trigLevel.addListener(SWT.DefaultSelection, e -> trigChanged());
        trigLevel.addListener(SWT.FocusOut, e -> trigChanged());
        trigPos.addListener(SWT.Selection, e -> trigChanged());
        zero.addListener(SWT.Selection, e -> {
            PREFS.putBoolean("zero", zero.getSelection());
            scope.setZero(zero.getSelection());
        });
        freeze.addListener(SWT.Selection, e -> scope.setFrozen(freeze.getSelection()));
        scope.setZero(zero.getSelection());
        scope.setTriggerListener((level, pre) -> {
            updating = true;
            trigLevel.setText(num(level, 2));
            trigPos.setSelection(Math.min(99, (int) Math.round(pre * 100.0 / scopeN)));
            updating = false;
            trigChanged();
        });
        showTrigger();
    }

    private Group group(Composite parent, String title, int cols) {
        Group g = new Group(parent, SWT.NONE);
        g.setText(title);
        g.setLayout(grid(cols, 6, 4));
        g.setLayoutData(new GridData(SWT.FILL, SWT.TOP, true, false));
        return g;
    }

    private Text field(Composite g, String label, String unit, String tip) {
        Label l = new Label(g, SWT.NONE);
        l.setText(label);
        l.setToolTipText(tip);
        Text t = new Text(g, SWT.BORDER | SWT.RIGHT);
        t.setLayoutData(new GridData(70, SWT.DEFAULT));
        t.setToolTipText(tip);
        t.setData("dirty", Boolean.FALSE);
        t.addListener(SWT.Modify, e -> {
            if (!updating) t.setData("dirty", Boolean.TRUE);
        });
        new Label(g, SWT.NONE).setText(unit);
        return t;
    }

    private Label big(Composite g) {
        Label l = new Label(g, SWT.NONE);
        l.setFont(bigFont);
        l.setLayoutData(new GridData(SWT.FILL, SWT.CENTER, true, false));
        return l;
    }

    // --------------------------------------------------------------------------------------------
    // Связь
    // --------------------------------------------------------------------------------------------
    private void fillPorts() {
        String cur = portCombo.getText().isEmpty() ? PREFS.get("port", "") : portCombo.getText();
        portCombo.setItems(RectLink.ports());
        portCombo.setText(cur);
    }

    private void toggleConnect() {
        if (link.isOpen()) {
            connect.setEnabled(false);
            new Thread(() -> link.close("@O 0", "@R 0"), "rectgui-close").start();
            return;
        }
        String p = portCombo.getText().trim();
        if (p.isEmpty()) return;
        try {
            link.open(p);
        } catch (Exception ex) {
            addLog("Порт " + p + " не открыт: " + ex.getMessage() + " (занят другой программой - например, терминалом Eclipse?)");
            return;
        }
        PREFS.put("port", p);
        addLog("Подключено: " + p);
        lastStatus = System.currentTimeMillis();
        haveInfo = false;
        infoTicks = 0;
        setConnected(true);
        link.send("@I");
        sendTrigger();
        link.send("@O " + (scopeOn.getSelection() ? 1 : 0));
    }

    private void onClosed(String why) {
        addLog(why == null ? "Отключено" : "Связь прервана: " + why);
        setConnected(false);
    }

    private void setConnected(boolean on) {
        connect.setText(on ? "Отключить" : "Подключить");
        connect.setEnabled(true);
        portCombo.setEnabled(!on);
        if (!on) {
            st = null;
            linkState.setText("нет связи");
            linkState.setForeground(gray);
            for (Label l : errLamp) l.setForeground(gray);
            enableControls(false);
        }
        connect.getParent().layout();
    }

    private void enableControls(boolean on) {
        boolean r = on && st != null && st.getOrDefault("r", 0) != 0;
        remote.setEnabled(on);
        for (Button b : modeBtn) b.setEnabled(r);
        onOff.setEnabled(r);
    }

    private void send(String cmd) {
        if (link != null && link.isOpen()) link.send(cmd);
    }

    /** Раз в 0,5 с: нет ответа стенда больше 2 с - предупреждение; нет сведений (#I) - запросить снова */
    private void watchdog() {
        if (portCombo == null || portCombo.isDisposed()) return;
        if (link.isOpen() && !haveInfo && ++infoTicks % 4 == 0) link.send("@I");
        if (link.isOpen() && System.currentTimeMillis() - lastStatus > 2000) {
            linkState.setText("стенд не отвечает (программа пульта загружена? скорость 115200)");
            linkState.setForeground(red);
            linkState.getParent().layout();
        }
        display.timerExec(500, this::watchdog);
    }

    // --------------------------------------------------------------------------------------------
    // Ответы стенда
    // --------------------------------------------------------------------------------------------
    private void onInfo(Map<String, Integer> i, String fw) {
        haveInfo = true;
        calU = new ScopeCanvas.Cal(i.getOrDefault("vs", 1000000), i.getOrDefault("vo", 0), "В");
        calI = new ScopeCanvas.Cal(i.getOrDefault("cs", 1000000), i.getOrDefault("co", 0), "А");
        scopeN = i.getOrDefault("n", 400);
        amax10 = i.getOrDefault("amax", 1200);
        scope.setCal(calU, calI);
        addLog("Стенд: программа " + fw + (i.getOrDefault("io", 0) != 0 ? ", стенд с входами DI" : ", без входов DI")
                + ", AMAX " + num(amax10 / 10.0, 1) + " град., осциллограмма " + scopeN + " точек через " + i.getOrDefault("dt", 50) + " мкс"
                + (i.containsKey("avg") ? " (точка - среднее " + i.get("avg") + " отсчётов АЦП)" : ""));
        alpha.setToolTipText("Угол управления в ручных режимах (0.." + num(amax10 / 10.0, 1) + " град.)");
        showTrigger();
        sendTrigger();
    }

    private void onStatus(Map<String, Integer> s) {
        st = s;
        lastStatus = System.currentTimeMillis();
        updating = true;
        int r = s.getOrDefault("r", 0), m = s.getOrDefault("m", 0), pm = s.getOrDefault("pm", 0), on = s.getOrDefault("on", 0);
        int en = s.getOrDefault("en", 0), run = s.getOrDefault("run", 0), cc = s.getOrDefault("cc", 0), err = s.getOrDefault("err", 0);
        linkState.setText("связь есть" + (r != 0 ? " - управление с ПК" : " - местное управление: " + LOCAL[Math.min(4, Math.max(0, m))]));
        linkState.setForeground(r != 0 ? green : amber);
        linkState.getParent().layout();
        remote.setSelection(r != 0);
        int sel = r != 0 ? pm : m;
        for (int k = 0; k < 3; k++) modeBtn[k].setSelection(sel == k + 1);
        enableControls(true);
        boolean onNow = r != 0 ? on != 0 : en != 0;
        onOff.setText(onNow ? "ВЫКЛЮЧИТЬ" : "ВКЛЮЧИТЬ");
        onOff.setForeground(onNow ? red : green);
        String rs;
        if (en == 0) rs = "Импульсы сняты";
        else if (run != 0) rs = "Импульсы идут" + (m == 1 ? " (имитатор сети)" : "");
        else rs = "Импульсы разрешены, но " + ((err & 1) != 0 ? "нет сети" : "нет синхронизации");
        runState.setText(rs);
        runState.setForeground(en == 0 ? gray : run != 0 ? green : amber);

        setIfClean(uSet, num(s.getOrDefault("us", 0) / 1000.0, 2));
        setIfClean(iLim, num(s.getOrDefault("il", 0) / 1000.0, 3));
        setIfClean(alpha, num(s.getOrDefault("a", 0) / 10.0, 1));
        setIfClean(kpU, num(s.getOrDefault("kpu", 0) / 4096.0, 4));
        setIfClean(kiU, num(s.getOrDefault("kiu", 0) / 4096.0, 4));
        setIfClean(kpI, num(s.getOrDefault("kpi", 0) / 4096.0, 4));
        setIfClean(kiI, num(s.getOrDefault("kii", 0) / 4096.0, 4));

        measU.setText("U = " + num(s.getOrDefault("u", 0) / 1000.0, 2) + " В");
        measI.setText("I = " + num(s.getOrDefault("i", 0) / 1000.0, 3) + " А");
        measA.setText("Угол (действующий): " + num(s.getOrDefault("ae", 0) / 10.0, 1) + " град.");
        int f = s.getOrDefault("f", 0);
        measF.setText("Сеть: " + (f > 0 ? num(f / 100.0, 2) + " Гц" : "нет") + (s.containsKey("st") ? ", шагов регулятора " + s.get("st") + "/с" : ""));
        String reg = "";
        if (m == 3) reg = run == 0 ? "Регулятор стоит (нет импульсов)" : cc != 0 ? "ОГРАНИЧЕНИЕ ТОКА" : "Стабилизация напряжения";
        if (m == 3 && s.containsKey("ou")) reg += "; выходы PI_U " + s.get("ou") + ", PI_I " + s.get("oi");
        measReg.setText(reg);
        measReg.setForeground(cc != 0 ? amber : measA.getForeground());
        for (int k = 0; k < errLamp.length; k++) errLamp[k].setForeground((err >> k & 1) != 0 ? red : green);
        measU.getParent().getParent().layout(true, true);
        updating = false;
    }

    private void setIfClean(Text t, String v) {
        if (t.isFocusControl() || Boolean.TRUE.equals(t.getData("dirty"))) return;
        if (!t.getText().equals(v)) t.setText(v);
    }

    private void onFrame(RectLink.Frame f) {
        scope.setFrame(f);
        if (freeze.getSelection()) return;
        double[] u = stats(f.u, calU), c = stats(f.c, calI);
        frameInfo.setText("кадр " + f.seq + (f.edge == 2 ? "" : f.trig != 0 ? ", запуск есть" : ", без запуска")
                + "   U ср. " + num(u[0], 2) + " (" + num(u[1], 2) + ".." + num(u[2], 2) + ") В"
                + "   I ср. " + num(c[0], 3) + " (" + num(c[1], 3) + ".." + num(c[2], 3) + ") А");
        frameInfo.getParent().layout();
    }

    private static double[] stats(int[] codes, ScopeCanvas.Cal cal) {
        double s = 0, lo = Double.MAX_VALUE, hi = -Double.MAX_VALUE;
        for (int c : codes) {
            double v = cal.phys(c);
            s += v;
            lo = Math.min(lo, v);
            hi = Math.max(hi, v);
        }
        return new double[] { s / codes.length, lo, hi };
    }

    private void addLog(String line) {
        if (log == null || log.isDisposed()) return;
        if (log.getLineCount() > 500) log.setText("");
        log.append(line + "\n");
    }

    // --------------------------------------------------------------------------------------------
    // Команды
    // --------------------------------------------------------------------------------------------
    private void applySet() {
        Double u = parse(uSet, 0, 2000), i = parse(iLim, 0, 1000), a = parse(alpha, 0, amax10 / 10.0);
        if (u == null || i == null || a == null) return;
        send("@U " + Math.round(u * 1000));
        send("@L " + Math.round(i * 1000));
        send("@A " + Math.round(a * 10));
        for (Text t : new Text[] { uSet, iLim, alpha }) t.setData("dirty", Boolean.FALSE);
    }

    private void applyGains() {
        Double[] k = { parse(kpU, 0, 15.99), parse(kiU, 0, 15.99), parse(kpI, 0, 15.99), parse(kiI, 0, 15.99) };
        for (Double d : k) if (d == null) return;
        send("@KU " + Math.round(k[0] * 4096) + " " + Math.round(k[1] * 4096));
        send("@KI " + Math.round(k[2] * 4096) + " " + Math.round(k[3] * 4096));
        for (Text t : new Text[] { kpU, kiU, kpI, kiI }) t.setData("dirty", Boolean.FALSE);
    }

    private Double parse(Text t, double lo, double hi) {
        try {
            double v = Double.parseDouble(t.getText().trim().replace(',', '.'));
            if (v >= lo && v <= hi) return v;
        } catch (NumberFormatException e) {
            //ниже
        }
        addLog("Неверное значение «" + t.getText() + "»: нужно число " + num(lo, 0) + ".." + num(hi, 2));
        t.setFocus();
        return null;
    }

    private void trigChanged() {
        if (updating) return;
        PREFS.putInt("src", trigSrc.getSelectionIndex());
        PREFS.putInt("edge", trigEdge.getSelectionIndex());
        PREFS.put("level", trigLevel.getText().trim());
        PREFS.putInt("pos", trigPos.getSelection());
        showTrigger();
        sendTrigger();
    }

    private double level() {
        try {
            return Double.parseDouble(trigLevel.getText().trim().replace(',', '.'));
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    private int pre() {
        return Math.min(scopeN - 1, trigPos.getSelection() * scopeN / 100);
    }

    private void showTrigger() {
        scope.setTrigger(trigSrc.getSelectionIndex(), trigEdge.getSelectionIndex(), level(), pre());
    }

    private void sendTrigger() {
        int src = trigSrc.getSelectionIndex();
        int code = (src == 0 ? calU : calI).code(level());
        send("@T " + src + " " + trigEdge.getSelectionIndex() + " " + code + " " + pre());
    }

    private static String num(double v, int digits) {
        return String.format(Locale.ROOT, "%." + digits + "f", v).replace('.', ',');
    }

    @Override
    public void setFocus() {
        connect.setFocus();
    }

    @Override
    public void dispose() {
        if (link != null && link.isOpen()) {
            RectLink l = link;
            new Thread(() -> l.close("@O 0", "@R 0"), "rectgui-close").start();
        }
        super.dispose();
    }
}
