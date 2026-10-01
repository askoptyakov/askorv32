package ru.askorv32.gwsoc;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.URI;
import java.net.URISyntaxException;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.eclipse.core.resources.IContainer;
import org.eclipse.core.resources.IFile;
import org.eclipse.core.resources.IResource;
import org.eclipse.core.resources.IResourceChangeEvent;
import org.eclipse.core.resources.IResourceChangeListener;
import org.eclipse.core.resources.IResourceDelta;
import org.eclipse.core.resources.ResourcesPlugin;
import org.eclipse.core.runtime.CoreException;
import org.eclipse.core.runtime.FileLocator;
import org.eclipse.core.runtime.IProgressMonitor;
import org.eclipse.core.runtime.IStatus;
import org.eclipse.core.runtime.Status;
import org.eclipse.core.runtime.jobs.Job;
import org.eclipse.swt.SWT;
import org.eclipse.swt.SWTError;
import org.eclipse.swt.browser.Browser;
import org.eclipse.swt.browser.BrowserFunction;
import org.eclipse.swt.browser.ProgressAdapter;
import org.eclipse.swt.browser.ProgressEvent;
import org.eclipse.swt.widgets.Composite;
import org.eclipse.swt.widgets.Display;
import org.eclipse.ui.IEditorInput;
import org.eclipse.ui.IEditorSite;
import org.eclipse.ui.IFileEditorInput;
import org.eclipse.ui.PartInitException;
import org.eclipse.ui.console.ConsolePlugin;
import org.eclipse.ui.console.IConsole;
import org.eclipse.ui.console.MessageConsole;
import org.eclipse.ui.console.MessageConsoleStream;
import org.eclipse.ui.part.EditorPart;
import org.osgi.framework.Bundle;
import org.osgi.framework.FrameworkUtil;

/**
 * Редактор файла конфигурации ПЛИС (.gwsoc). Внутри - страница web/index.html (изображение
 * микросхемы, блоки, выводы) во встроенном браузере Edge. Страница зовёт редактор функцией
 * gwsocHost(команда, данные): ready, dirty, save, build. Кнопка «Собрать» сохраняет файл и
 * запускает генератор sw/socgen/socgen.py с ключом --build; его вывод идёт в консоль Eclipse.
 */
public class GwsocEditor extends EditorPart {
    public static final String ID = "ru.askorv32.gwsoc.editor";
    private static final String CONSOLE_NAME = "askoRV32 - сборка ПЛИС";

    private Browser browser;
    private IFile file;
    private boolean dirty;
    private boolean ignoreChange;   //Своё сохранение не считается внешним изменением файла
    private Job buildJob;
    private SidePanels panels;   //Свёрнутые на время работы конфигуратора панели справа и снизу

    private final IResourceChangeListener fileListener = event -> {
        if (event.getType() != IResourceChangeEvent.POST_CHANGE || file == null) return;
        IResourceDelta d = event.getDelta() == null ? null : event.getDelta().findMember(file.getFullPath());
        if (d == null || (d.getFlags() & IResourceDelta.CONTENT) == 0 || ignoreChange) return;
        //Файл изменён снаружи (git, другой редактор): без своих правок перечитать
        Display.getDefault().asyncExec(() -> { if (!dirty && browser != null && !browser.isDisposed()) loadIntoPage(); });
    };

    @Override
    public void init(IEditorSite site, IEditorInput input) throws PartInitException {
        if (!(input instanceof IFileEditorInput fi))
            throw new PartInitException("Конфигуратор открывает только файлы .gwsoc из рабочей области Eclipse");
        setSite(site);
        setInput(input);
        file = fi.getFile();
        setPartName(file.getName());
        setTitleToolTip(file.getFullPath().toString());
        ResourcesPlugin.getWorkspace().addResourceChangeListener(fileListener, IResourceChangeEvent.POST_CHANGE);
    }

    @Override
    public void createPartControl(Composite parent) {
        try {
            browser = new Browser(parent, SWT.EDGE);
        } catch (SWTError e) {
            browser = new Browser(parent, SWT.NONE);   //Нет WebView2 - браузер по умолчанию
        }
        new BrowserFunction(browser, "gwsocHost") {
            @Override
            public Object function(Object[] args) {
                String cmd = args.length > 0 && args[0] != null ? args[0].toString() : "";
                String arg = args.length > 1 && args[1] != null ? args[1].toString() : null;
                //Не вызывать страницу изнутри обработчика её же вызова
                Display.getCurrent().asyncExec(() -> handle(cmd, arg));
                return null;
            }
        };
        //Страница могла загрузиться раньше, чем появилась gwsocHost, - данные отдаются и по окончании загрузки
        browser.addProgressListener(new ProgressAdapter() {
            @Override
            public void completed(ProgressEvent event) { loadIntoPage(); }
        });
        panels = new SidePanels(getSite(), this, browser);
        panels.install();
        try {
            browser.setUrl(pageUrl());
        } catch (IOException e) {
            browser.setText("<p style='font-family:sans-serif'>Не найдена страница конфигуратора: " + e.getMessage() + "</p>");
        }
    }

    private String pageUrl() throws IOException {
        Bundle bundle = FrameworkUtil.getBundle(getClass());
        URL dir = FileLocator.toFileURL(bundle.getEntry("web/"));   //Каталог распаковывается целиком
        try {
            //В пути бывают пробелы (C:/Users/Koptyakov A/...): URI из частей экранирует их
            return Path.of(new URI(dir.getProtocol(), dir.getPath(), null)).resolve("index.html").toUri().toString();
        } catch (URISyntaxException e) {
            throw new IOException(e);
        }
    }

    private void handle(String cmd, String arg) {
        if (browser == null || browser.isDisposed()) return;
        switch (cmd) {
            case "ready" -> loadIntoPage();
            case "dirty" -> setDirty(true);
            case "save" -> { if (arg != null) writeFile(arg); }
            case "build" -> { if (arg != null && writeFile(arg)) runBuild(); }
            case "readme" -> { if (arg != null) sendReadme(arg); }
            default -> { }
        }
    }

    //Описание модуля из библиотеки: hw/src/periph/<тип>/README.md (каталог hw - из paths.hw файла .gwsoc)
    private void sendReadme(String type) {
        String text;
        if (!type.matches("[a-z0-9_]+")) {
            text = "Недопустимое имя типа: " + type;
        } else {
            try (InputStream in = file.getContents(true)) {
                String cfg = new String(in.readAllBytes(), StandardCharsets.UTF_8);
                File hw = new File(file.getLocation().toFile().getParentFile(), jsonPath(cfg, "hw", "../hw"));
                File md = new File(hw, "src/periph/" + type + "/README.md");
                text = md.isFile() ? java.nio.file.Files.readString(md.toPath(), StandardCharsets.UTF_8)
                                   : "Описание не найдено: " + md.getCanonicalPath();
            } catch (IOException | CoreException e) {
                text = "Не удалось прочитать описание: " + e.getMessage();
            }
        }
        browser.execute("window.gwsoc && gwsoc.readme(" + jsString(type) + "," + jsString(text) + ");");
    }

    // --- Файл ---
    private void loadIntoPage() {
        try (InputStream in = file.getContents(true)) {
            String text = new String(in.readAllBytes(), StandardCharsets.UTF_8);
            browser.execute("window.gwsoc && gwsoc.load(" + jsString(text) + ");");
            setDirty(false);
            sendResources(text);
        } catch (IOException | CoreException e) {
            status("Не удалось прочитать " + file.getName() + ": " + e.getMessage(), "err");
        }
    }

    //Занятые ресурсы последней сборки (генератор пишет hw/impl/socgen/resources.json) - для панели ресурсов
    private void sendResources(String cfgText) {
        String res = "";
        try {
            File f = new File(new File(file.getLocation().toFile().getParentFile(), jsonPath(cfgText, "hw", "../hw")),
                              "impl/socgen/resources.json");
            if (f.isFile()) res = java.nio.file.Files.readString(f.toPath(), StandardCharsets.UTF_8);
        } catch (IOException ignored) { }
        browser.execute("window.gwsoc && gwsoc.resources(" + jsString(res) + ");");
    }

    private void progress(int pct, String text) {
        if (browser != null && !browser.isDisposed())
            browser.execute("window.gwsoc && gwsoc.progress(" + pct + "," + jsString(text) + ");");
    }

    private boolean writeFile(String json) {
        try {
            ignoreChange = true;
            file.setContents(new ByteArrayInputStream(json.getBytes(StandardCharsets.UTF_8)), IResource.KEEP_HISTORY, null);
            setDirty(false);
            browser.execute("gwsoc.saved();");
            return true;
        } catch (CoreException e) {
            status("Ошибка сохранения: " + e.getMessage(), "err");
            return false;
        } finally {
            ignoreChange = false;
        }
    }

    @Override
    public void doSave(IProgressMonitor monitor) {
        Object json = browser.evaluate("return gwsoc.getJson();");
        if (json instanceof String s) writeFile(s);
    }

    @Override
    public void doSaveAs() { }

    @Override
    public boolean isSaveAsAllowed() { return false; }

    @Override
    public boolean isDirty() { return dirty; }

    private void setDirty(boolean d) {
        if (dirty == d) return;
        dirty = d;
        firePropertyChange(PROP_DIRTY);
    }

    @Override
    public void setFocus() { if (browser != null) browser.setFocus(); }

    @Override
    public void dispose() {
        ResourcesPlugin.getWorkspace().removeResourceChangeListener(fileListener);
        if (panels != null) panels.dispose();
        super.dispose();
    }

    // --- Сборка ---
    private void runBuild() {
        if (buildJob != null && buildJob.getState() != Job.NONE) {
            status("Сборка уже идёт", "");
            return;
        }
        File cfg = file.getLocation().toFile();
        String text;
        try (InputStream in = file.getContents(true)) {
            text = new String(in.readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException | CoreException e) {
            status("Ошибка чтения: " + e.getMessage(), "err");
            return;
        }
        File generator = new File(cfg.getParentFile(), jsonPath(text, "generator", "../sw/socgen/socgen.py"));
        File hwDir = new File(cfg.getParentFile(), jsonPath(text, "hw", "../hw"));
        MessageConsole console = console();
        status("Сборка…", "");   //Консоль сама не открывается: ход - полосой в конфигураторе, подробности - в консоли

        buildJob = new Job("Сборка ПЛИС askoRV32") {
            @Override
            protected IStatus run(IProgressMonitor monitor) {
                int code = -1;
                int warnings = 0;
                monitor.beginTask("Сборка ПЛИС askoRV32", 100);
                int done = 0;
                Display.getDefault().asyncExec(() -> progress(0, "Генерация файлов"));
                try (MessageConsoleStream out = console.newMessageStream()) {
                    List<String> cmd = new ArrayList<>(List.of(python(), generator.getCanonicalPath(), cfg.getCanonicalPath(), "--build"));
                    out.println("> " + String.join(" ", cmd));
                    ProcessBuilder pb = new ProcessBuilder(cmd).directory(cfg.getParentFile()).redirectErrorStream(true);
                    Map<String, String> env = pb.environment();
                    env.put("PYTHONIOENCODING", "utf-8");
                    env.put("PYTHONUNBUFFERED", "1");
                    Process p = pb.start();
                    try (BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream(), StandardCharsets.UTF_8))) {
                        String line;
                        while ((line = r.readLine()) != null) {
                            //Ход сборки: строка «@@PROGRESS <проценты> <этап>» - в полосу на странице и в задачу Eclipse
                            Matcher pm = PROGRESS.matcher(line);
                            if (pm.matches()) {
                                int pct = Math.min(100, Integer.parseInt(pm.group(1)));
                                String stage = pm.group(2);
                                if (pct > done) { monitor.worked(pct - done); done = pct; }
                                monitor.subTask(pct + " % · " + stage);
                                Display.getDefault().asyncExec(() -> progress(pct, stage));
                                continue;
                            }
                            out.println(line);
                            if (line.startsWith("Предупреждение")) warnings++;
                            if (monitor.isCanceled()) { p.destroy(); break; }
                        }
                    }
                    code = p.waitFor();
                    out.println("Код завершения: " + code);
                } catch (IOException e) {
                    try (MessageConsoleStream out = console.newMessageStream()) {
                        out.println("Не удалось запустить генератор: " + e.getMessage());
                        out.println("Нужен Python 3 (команда py или переменная окружения GWSOC_PYTHON).");
                    } catch (IOException ignored) { }
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
                refresh(hwDir, monitor);
                monitor.done();
                final int c = code, w = warnings;
                Display.getDefault().asyncExec(() -> {
                    try (InputStream in = file.getContents(true)) {
                        sendResources(new String(in.readAllBytes(), StandardCharsets.UTF_8));
                    } catch (IOException | CoreException ignored) { }
                    if (c == 0) status(w == 0 ? "Сборка завершена" : "Сборка завершена, предупреждений: " + w + " (см. консоль)", "ok");
                    else if (c == 1) status("Ошибки в конфигурации - см. консоль «" + CONSOLE_NAME + "»", "err");
                    else status("Сборка не удалась - см. консоль «" + CONSOLE_NAME + "»", "err");
                    //Конец сборки: кнопка снова активна, вместо шкалы - ресурсы; к статусу добавляется время сборки
                    if (browser != null && !browser.isDisposed()) browser.execute("window.gwsoc && gwsoc.buildDone(" + (c == 0) + ");");
                });
                return Status.OK_STATUS;
            }
        };
        buildJob.setUser(false);
        buildJob.schedule();
    }

    private static final Pattern PROGRESS = Pattern.compile("@@PROGRESS (\\d+) (.*)");

    private static String python() {
        String p = System.getenv("GWSOC_PYTHON");
        return p != null && !p.isBlank() ? p : "py";
    }

    //Созданные top.sv, riscv.cst и битовый поток должны сразу появиться в Eclipse, если hw в рабочей области
    private void refresh(File dir, IProgressMonitor monitor) {
        try {
            for (IContainer c : ResourcesPlugin.getWorkspace().getRoot().findContainersForLocationURI(dir.getCanonicalFile().toURI()))
                c.refreshLocal(IResource.DEPTH_INFINITE, monitor);
            file.getParent().refreshLocal(IResource.DEPTH_ONE, monitor);
        } catch (IOException | CoreException ignored) { }
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

    private void status(String text, String kind) {
        if (browser != null && !browser.isDisposed())
            browser.execute("window.gwsoc && gwsoc.status(" + jsString(text) + "," + jsString(kind) + ");");
    }

    //Значение "paths": { "<key>": "..." } без разбора всего JSON
    private static String jsonPath(String json, String key, String def) {
        Matcher m = Pattern.compile("\"" + key + "\"\\s*:\\s*\"([^\"]*)\"").matcher(json);
        return m.find() ? m.group(1) : def;
    }

    private static String jsString(String s) {
        StringBuilder b = new StringBuilder("\"");
        for (char ch : s.toCharArray()) {
            switch (ch) {
                case '"' -> b.append("\\\"");
                case '\\' -> b.append("\\\\");
                case '\n' -> b.append("\\n");
                case '\r' -> b.append("\\r");
                case '\t' -> b.append("\\t");
                case '<' -> b.append("\\u003c");
                case ' ' -> b.append("\\u2028");
                case ' ' -> b.append("\\u2029");
                default -> b.append(ch);
            }
        }
        return b.append('"').toString();
    }
}
