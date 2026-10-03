package ru.askorv32.gwsoc;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.eclipse.core.resources.IFile;
import org.eclipse.core.resources.IMarker;
import org.eclipse.core.resources.IProject;
import org.eclipse.core.resources.IResource;
import org.eclipse.core.resources.IncrementalProjectBuilder;
import org.eclipse.core.runtime.CoreException;
import org.eclipse.core.runtime.IProgressMonitor;
import org.eclipse.core.runtime.IStatus;
import org.eclipse.core.runtime.Status;
import org.eclipse.core.runtime.jobs.Job;
import org.eclipse.jface.dialogs.Dialog;
import org.eclipse.jface.dialogs.IDialogConstants;
import org.eclipse.jface.dialogs.MessageDialog;
import org.eclipse.swt.SWT;
import org.eclipse.swt.layout.GridData;
import org.eclipse.swt.layout.GridLayout;
import org.eclipse.swt.widgets.Button;
import org.eclipse.swt.widgets.Composite;
import org.eclipse.swt.widgets.Control;
import org.eclipse.swt.widgets.Display;
import org.eclipse.swt.widgets.Group;
import org.eclipse.swt.widgets.Label;
import org.eclipse.swt.widgets.ProgressBar;
import org.eclipse.swt.widgets.Shell;
import org.eclipse.ui.console.ConsolePlugin;
import org.eclipse.ui.console.IConsole;
import org.eclipse.ui.console.MessageConsole;
import org.eclipse.ui.console.MessageConsoleStream;
import org.eclipse.ui.ide.IDE;

/**
 * Окно «Программатор ПЛИС» - упрощённый аналог Gowin Programmer: запись конфигурации и программы
 * в одно из трёх мест (SRAM, встроенная flash, внешняя SPI-флеш) и очистка встроенной flash и внешней
 * SPI-флеш по отдельности - для одной платы (файл .gwsoc). У ПЛИС без встроенной flash (GW2A-18, Tang Primer 20K)
 * её пункты недоступны. Работу делает sw/fpgaload/fpgaload.py --gwsoc <файл> (openFPGALoader из sdk/openfpgaloader);
 * его вывод - в консоль «askoRV32 - программатор ПЛИС», ход - полосой в окне.
 * Окно немодальное: пока идёт запись, можно работать в Eclipse; закрытие окна запись не прерывает.
 */
public class ProgrammerDialog extends Dialog {
    private static final String CONSOLE_NAME = "askoRV32 - программатор ПЛИС";
    private static final String[][] TARGETS = {     //{ключ fpgaload, подпись, пояснение}
        { "sram", "SRAM ПЛИС", "до выключения питания; при любых выводах MODE" },
        { "flash", "Встроенная flash ПЛИС", "режим AUTO BOOT (MODE1 = 0); программа - в битовом потоке" },
        { "spiflash", "Внешняя SPI-флеш", "режим MSPI (MODE1 = 1); битовый поток с 0x000000, образ программы - с адреса загрузчика" },
    };
    //Полоса openFPGALoader: "<подпись>: [=====>    ] 45.00%"
    private static final Pattern BAR = Pattern.compile("\\s*([^:\\[]+?):\\s*\\[[=> ]*\\]\\s*([0-9.]+)%.*");

    private static ProgrammerDialog instance;
    private static String lastTarget;

    private final IProject project;
    private final IFile cfg;
    private boolean extCfg;         //Блок SPIFLASH хранит конфигурацию ПЛИС (fpgaConfig): ПЛИС собрана для MSPI
    private String bootAddr = "0x100000";
    private boolean embeddedFlash = true;   //У ПЛИС есть встроенная flash конфигурации (GW1NR-9 - да, GW2A-18 - нет)
    private String boardTitle;              //Название платы ("board.title" в .gwsoc)
    private String cfgWrite = "около 3 мин";    //Сколько пишется битовый поток во внешнюю флеш

    private final List<Button> radios = new ArrayList<>();
    private final List<Control> locked = new ArrayList<>();    //Недоступны, пока идёт работа
    private Button build, force, stop;
    private Label state;
    private ProgressBar bar;
    private Job job;
    private volatile Process proc;

    public static void open(Shell parent, IProject project, IFile cfg) {
        if (instance != null && instance.getShell() != null && !instance.getShell().isDisposed()) {
            if (instance.project.equals(project)) {
                instance.getShell().setActive();
                return;
            }
            if (instance.job != null) {
                instance.getShell().setActive();
                MessageDialog.openInformation(instance.getShell(), "Программатор ПЛИС", "Идёт работа с ПЛИС - дождитесь окончания.");
                return;
            }
            instance.close();
        }
        instance = new ProgrammerDialog(parent, project, cfg);
        instance.open();
    }

    private ProgrammerDialog(Shell parent, IProject project, IFile cfg) {
        super(parent);
        this.project = project;
        this.cfg = cfg;
        setShellStyle((getShellStyle() & ~SWT.APPLICATION_MODAL) | SWT.MODELESS | SWT.RESIZE);
        setBlockOnOpen(false);
        readConfig();
    }

    private void readConfig() {
        try (InputStream in = cfg.getContents(true)) {
            String text = new String(in.readAllBytes(), StandardCharsets.UTF_8);
            extCfg = Pattern.compile("\"fpgaConfig\"\\s*:\\s*true").matcher(text).find();
            Matcher m = Pattern.compile("\"bootAddr\"\\s*:\\s*\"([^\"]*)\"").matcher(text);
            if (m.find()) bootAddr = m.group(1);
            m = Pattern.compile("\"title\"\\s*:\\s*\"([^\"]*)\"").matcher(text);
            if (m.find()) boardTitle = m.group(1);
        } catch (IOException | CoreException ignored) { }
        //Свойства ПЛИС платы (встроенная flash, время записи) - от fpgaload describe: кристаллы описаны в devices.js
        try {
            Process p = new ProcessBuilder(python(), "-u", fpgaloadPath().getAbsolutePath(), "describe", "--gwsoc",
                                           cfg.getLocation().toFile().getAbsolutePath()).redirectErrorStream(true).start();
            String out = new String(p.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
            if (p.waitFor() == 0) {
                embeddedFlash = !out.contains("\"embeddedFlash\": false");
                extCfg = out.contains("\"extCfg\": true");
                Matcher m = Pattern.compile("\"cfgWrite\": \"([^\"]*)\"").matcher(out);
                if (m.find()) cfgWrite = m.group(1);
                m = Pattern.compile("\"title\": \"([^\"]*)\"").matcher(out);
                if (m.find()) boardTitle = m.group(1);
            }
        } catch (IOException e) {
            //Без Python окно всё равно откроется; запуск fpgaload сообщит об ошибке
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    private File fpgaloadPath() {
        File root = cfg.getLocation().toFile().getParentFile();
        File sw = new File(root, jsonGenerator()).getParentFile().getParentFile();
        return new File(sw, "fpgaload/fpgaload.py");
    }

    @Override
    protected void configureShell(Shell shell) {
        super.configureShell(shell);
        shell.setText("Программатор ПЛИС askoRV32 - " + (boardTitle != null ? boardTitle : project.getName()) + " (" + cfg.getName() + ")");
    }

    @Override
    protected Control createDialogArea(Composite parent) {
        Composite area = (Composite) super.createDialogArea(parent);
        ((GridLayout) area.getLayout()).verticalSpacing = 10;

        Label info = new Label(area, SWT.WRAP);
        info.setText(extCfg
            ? "ПЛИС собрана для внешней SPI-флеш (" + cfg.getName() + ": блок SPIFLASH хранит конфигурацию): "
              + "программу после сброса берёт загрузчик из образа с адреса " + bootAddr + "."
            : "ПЛИС собрана для SRAM и встроенной flash (" + cfg.getName() + "): программа вливается в битовый поток.");
        info.setLayoutData(wide(560));

        //Запись
        Group wr = group(area, "Запись конфигурации и программы");
        String sel = lastTarget != null ? lastTarget : extCfg ? "spiflash" : "sram";
        for (String[] t : TARGETS) {
            Button b = new Button(wr, SWT.RADIO);
            b.setText(t[1]);
            b.setData(t[0]);
            b.setFont(bold(b));
            Label d = new Label(wr, SWT.WRAP);
            d.setText(t[2] + note(t[0]));
            GridData gd = wide(520);
            gd.horizontalIndent = 20;
            d.setLayoutData(gd);
            boolean ok = usable(t[0]);
            b.setEnabled(ok);
            d.setEnabled(ok);
            b.setSelection(t[0].equals(sel) && ok);
            b.addListener(SWT.Selection, e -> updateForce());
            radios.add(b);
            locked.add(b);
        }
        if (radios.stream().noneMatch(Button::getSelection)) radios.get(0).setSelection(true);
        build = check(wr, "Собрать программу перед записью", true);
        force = check(wr, "Внешняя флеш: записать битовый поток, даже если он не менялся (" + cfgWrite + ")", false);
        Button prog = button(wr, "Прошить");
        prog.addListener(SWT.Selection, e -> program());
        getShell().setDefaultButton(prog);

        //Очистка
        Group er = group(area, "Очистка");
        ((GridLayout) er.getLayout()).numColumns = 2;
        Button ef = button(er, "Очистить встроенную flash");
        ef.setData("erase-flash");
        ef.setEnabled(embeddedFlash);
        label(er, !embeddedFlash ? "Недоступно: у ПЛИС этой платы нет встроенной flash."
                 : extCfg ? "Стирает встроенную flash ПЛИС. При MSPI ПЛИС после этого снова загружается из внешней флеш."
                          : "Стирает встроенную flash ПЛИС: при AUTO BOOT ПЛИС пуста до следующей записи.");
        ef.addListener(SWT.Selection, e -> eraseFlash());
        Button es = button(er, "Очистить SPI-флеш");
        label(er, "Стирает всю внешнюю флеш: битовый поток, образ программы и рабочие параметры программы.");
        es.addListener(SWT.Selection, e -> eraseSpiflash());

        //Ход работы
        Composite st = new Composite(area, SWT.NONE);
        st.setLayout(new GridLayout(2, false));
        st.setLayoutData(wide(560));
        bar = new ProgressBar(st, SWT.SMOOTH);
        bar.setLayoutData(new GridData(SWT.FILL, SWT.CENTER, true, false));
        stop = new Button(st, SWT.PUSH);
        stop.setText("Остановить");
        stop.setEnabled(false);
        stop.addListener(SWT.Selection, e -> cancel());
        state = new Label(st, SWT.NONE);
        GridData sd = new GridData(SWT.FILL, SWT.CENTER, true, false, 2, 1);
        state.setLayoutData(sd);
        state.setText("Готов. Подробности работы - в консоли «" + CONSOLE_NAME + "».");
        updateForce();
        return area;
    }

    @Override
    protected void createButtonsForButtonBar(Composite parent) {
        createButton(parent, IDialogConstants.CLOSE_ID, "Закрыть", false);
    }

    @Override
    protected void buttonPressed(int id) {
        if (id == IDialogConstants.CLOSE_ID) close();
        else super.buttonPressed(id);
    }

    @Override
    public boolean close() {
        boolean r = super.close();
        if (r && instance == this) instance = null;
        return r;
    }

    // --- Действия ---
    private void program() {
        String t = selected();
        lastTarget = t;
        List<String> args = new ArrayList<>(List.of(t));
        if ("spiflash".equals(t) && force.getSelection()) args.add("--force");
        String name = switch (t) {
            case "sram" -> "Запись в SRAM ПЛИС";
            case "flash" -> "Запись во встроенную flash";
            default -> "Запись во внешнюю SPI-флеш";
        };
        run(name, args, build.getSelection());
    }

    private void eraseFlash() {
        if (!MessageDialog.openConfirm(getShell(), "Очистить встроенную flash",
                "Стереть встроенную flash ПЛИС?\n\n" + (extCfg
                    ? "Сейчас ПЛИС загружается из внешней флеш (MSPI) - после стирания она перезапустится оттуда же."
                    : "Если ПЛИС загружается из встроенной flash (AUTO BOOT), она останется пустой до следующей записи.")))
            return;
        run("Очистка встроенной flash", List.of("erase-flash"), false);
    }

    private void eraseSpiflash() {
        if (!MessageDialog.openConfirm(getShell(), "Очистить SPI-флеш",
                "Стереть всю внешнюю SPI-флеш?\n\nБудут стёрты битовый поток ПЛИС, образ программы и все данные программы "
                + "(рабочие параметры)." + (extCfg
                    ? "\n\nПЛИС загружается из внешней флеш (MSPI): после стирания она не запустится, пока не записать её "
                      + "заново («Внешняя SPI-флеш» → «Прошить», " + cfgWrite + ")."
                    : "")))
            return;
        run("Очистка SPI-флеш", List.of("erase-spiflash"), false);
    }

    private void cancel() {
        Process p = proc;
        if (p != null) {
            p.descendants().forEach(ProcessHandle::destroyForcibly);   //openFPGALoader, mergetool
            p.destroyForcibly();
        }
        if (job != null) job.cancel();
    }

    // --- Запуск fpgaload.py ---
    private void run(String title, List<String> args, boolean buildFirst) {
        if (job != null) return;
        if (buildFirst) IDE.saveAllEditors(new IResource[] { project }, false);
        //Плата - файл .gwsoc: fpgaload берёт из него ПЛИС, битовый поток и каталог сборки программы
        File fpgaload = fpgaloadPath();
        File cwd = project.getLocation().toFile();
        List<String> cmd = new ArrayList<>(List.of(python(), "-u", fpgaload.getAbsolutePath()));
        cmd.addAll(args);
        cmd.addAll(List.of("--gwsoc", cfg.getLocation().toFile().getAbsolutePath()));

        MessageConsole console = console();
        ConsolePlugin.getDefault().getConsoleManager().showConsoleView(console);
        busy(true, title + "…");
        long t0 = System.nanoTime();
        Display display = getShell().getDisplay();
        job = new Job("Программатор ПЛИС: " + title) {
            @Override
            protected IStatus run(IProgressMonitor monitor) {
                int code = -1;
                String fail = null;
                try (MessageConsoleStream out = console.newMessageStream()) {
                    out.println("=== " + title + " ===");
                    if (buildFirst) {
                        ui(display, () -> busy(true, "Сборка программы…"));
                        project.build(IncrementalProjectBuilder.INCREMENTAL_BUILD, monitor);
                        if (project.findMaxProblemSeverity(IMarker.PROBLEM, true, IResource.DEPTH_INFINITE) == IMarker.SEVERITY_ERROR) {
                            out.println("Сборка программы с ошибками - запись отменена (см. Problems и консоль сборки).");
                            fail = "Сборка программы с ошибками";
                        }
                    }
                    if (fail == null && !monitor.isCanceled()) {
                        ui(display, () -> busy(true, title + "…"));
                        out.println("> " + String.join(" ", cmd));
                        ProcessBuilder pb = new ProcessBuilder(cmd).directory(cwd).redirectErrorStream(true);
                        pb.environment().put("PYTHONIOENCODING", "utf-8");
                        proc = pb.start();
                        pump(proc.getInputStream(), out, display);
                        code = proc.waitFor();
                        proc = null;
                        out.println("Код завершения: " + code);
                    }
                } catch (CoreException e) {
                    fail = "Ошибка сборки: " + e.getMessage();
                } catch (IOException e) {
                    fail = "Не удалось запустить " + cmd.get(0) + ": " + e.getMessage() + " (нужен Python 3: py или GWSOC_PYTHON)";
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
                if (fail != null) {
                    try (MessageConsoleStream out = console.newMessageStream()) { out.println(fail); } catch (IOException ignored) { }
                }
                long sec = Math.round((System.nanoTime() - t0) / 1e9);
                String msg = fail != null ? fail
                    : monitor.isCanceled() ? title + ": остановлено"
                    : code == 0 ? title + ": готово за " + time(sec)
                    : title + ": ошибка (код " + code + ") - см. консоль";
                boolean ok = fail == null && code == 0 && !monitor.isCanceled();
                ui(display, () -> {
                    job = null;
                    busy(false, msg);
                    if (ok) bar.setSelection(100);
                });
                return Status.OK_STATUS;
            }
        };
        job.setUser(false);
        job.schedule();
    }

    //Вывод fpgaload: строки - в консоль, полосы openFPGALoader - в полосу окна (в консоль - только итог полосы)
    private void pump(InputStream in, MessageConsoleStream out, Display display) throws IOException {
        ByteArrayOutputStream line = new ByteArrayOutputStream();
        String lastBar = null;
        int c;
        while ((c = in.read()) >= 0) {
            if (c != '\r' && c != '\n') {
                line.write(c);
                continue;
            }
            String s = line.toString(StandardCharsets.UTF_8);
            line.reset();
            if (s.isBlank()) continue;
            Matcher m = BAR.matcher(s);
            if (m.matches()) {
                String label = m.group(1).trim();
                int pct = (int) Math.min(100, Double.parseDouble(m.group(2)));
                ui(display, () -> {
                    if (bar.isDisposed()) return;
                    bar.setSelection(pct);
                    state.setText(label + ": " + pct + " %");
                });
                if (pct >= 100 && !s.equals(lastBar)) out.println(s.trim());
                lastBar = s;
            } else {
                out.println(s);
                String text = s.trim();
                if (!text.isEmpty() && Character.isUpperCase(text.codePointAt(0)) && text.codePointAt(0) > 0x400)
                    ui(display, () -> { if (!state.isDisposed()) state.setText(text); });  //Сообщения fpgaload (по-русски)
            }
        }
    }

    // --- Вспомогательное ---
    private String selected() {
        for (Button b : radios) if (b.getSelection()) return (String) b.getData();
        return "sram";
    }

    private boolean usable(String target) {
        return switch (target) {
            case "flash" -> embeddedFlash && !extCfg;   //Нет встроенной flash; ПЛИС для MSPI в неё не пишется (fpgaload откажет)
            case "erase-flash" -> embeddedFlash;
            case "spiflash" -> extCfg;      //Без загрузчика программа из внешней флеш не возьмётся
            default -> true;
        };
    }

    private String note(String target) {
        if (usable(target)) return "";
        if ("spiflash".equals(target)) return ". Недоступно: в конфигураторе блок SPIFLASH не хранит конфигурацию ПЛИС";
        return !embeddedFlash ? ". Недоступно: у ПЛИС этой платы нет встроенной flash"
                              : ". Недоступно: ПЛИС собрана для внешней SPI-флеш (MSPI)";
    }

    private void updateForce() {
        if (force != null && !force.isDisposed()) force.setEnabled(job == null && "spiflash".equals(selected()));
    }

    private void busy(boolean on, String text) {
        if (state == null || state.isDisposed()) return;
        for (Control c : locked)
            if (!c.isDisposed()) c.setEnabled(!on && (!(c.getData() instanceof String t) || usable(t)));
        stop.setEnabled(on);
        state.setText(text);
        if (on) bar.setSelection(0);
        updateForce();
    }

    private Group group(Composite parent, String title) {
        Group g = new Group(parent, SWT.NONE);
        g.setText(title);
        g.setLayout(new GridLayout(1, false));
        g.setLayoutData(new GridData(SWT.FILL, SWT.TOP, true, false));
        return g;
    }

    private Button check(Composite parent, String text, boolean on) {
        Button b = new Button(parent, SWT.CHECK);
        b.setText(text);
        b.setSelection(on);
        locked.add(b);
        return b;
    }

    private Button button(Composite parent, String text) {
        Button b = new Button(parent, SWT.PUSH);
        b.setText(text);
        GridData gd = new GridData(SWT.FILL, SWT.CENTER, false, false);
        gd.widthHint = 200;
        b.setLayoutData(gd);
        locked.add(b);
        return b;
    }

    private static void label(Composite parent, String text) {
        Label l = new Label(parent, SWT.WRAP);
        l.setText(text);
        l.setLayoutData(wide(330));
    }

    private static GridData wide(int hint) {
        GridData gd = new GridData(SWT.FILL, SWT.CENTER, true, false);
        gd.widthHint = hint;
        return gd;
    }

    private static org.eclipse.swt.graphics.Font bold(Control c) {
        var fd = c.getFont().getFontData();
        for (var d : fd) d.setStyle(SWT.BOLD);
        var f = new org.eclipse.swt.graphics.Font(c.getDisplay(), fd);
        c.addListener(SWT.Dispose, e -> f.dispose());
        return f;
    }

    private static void ui(Display d, Runnable r) {
        if (!d.isDisposed()) d.asyncExec(r);
    }

    private static String time(long sec) {
        return sec < 60 ? sec + " с" : sec / 60 + " мин " + sec % 60 + " с";
    }

    private String jsonGenerator() {
        try (InputStream in = cfg.getContents(true)) {
            Matcher m = Pattern.compile("\"generator\"\\s*:\\s*\"([^\"]*)\"")
                .matcher(new String(in.readAllBytes(), StandardCharsets.UTF_8));
            if (m.find()) return m.group(1);
        } catch (IOException | CoreException ignored) { }
        return "../sw/socgen/socgen.py";
    }

    private static String python() {
        String p = System.getenv("GWSOC_PYTHON");
        return p != null && !p.isBlank() ? p : "py";
    }

    private static MessageConsole console() {
        var mgr = ConsolePlugin.getDefault().getConsoleManager();
        for (IConsole c : mgr.getConsoles())
            if (CONSOLE_NAME.equals(c.getName()) && c instanceof MessageConsole mc) {
                mc.clearConsole();
                return mc;
            }
        MessageConsole mc = new MessageConsole(CONSOLE_NAME, null);
        mgr.addConsoles(new IConsole[] { mc });
        return mc;
    }
}
