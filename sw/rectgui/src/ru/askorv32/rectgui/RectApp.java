package ru.askorv32.rectgui;

import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.prefs.Preferences;

import org.eclipse.swt.SWT;
import org.eclipse.swt.graphics.Image;
import org.eclipse.swt.graphics.Rectangle;
import org.eclipse.swt.layout.FillLayout;
import org.eclipse.swt.widgets.Display;
import org.eclipse.swt.widgets.Shell;

/**
 * Пульт выпрямителя отдельной программой (без Eclipse): окно с панелью RectPanel. Запуск - RectPult.exe
 * из сборки sw/rectgui/build_exe.py. Размер и положение окна запоминаются.
 */
public final class RectApp {
    private static final String TITLE = "Пульт выпрямителя askoRV32";
    private static final Preferences PREFS = Preferences.userRoot().node("ru/askorv32/rectgui/app");

    public static void main(String[] args) {
        Display.setAppName(TITLE);
        Display d = new Display();
        Shell sh = new Shell(d);
        sh.setText(TITLE);
        sh.setLayout(new FillLayout());
        List<Image> icons = new ArrayList<>();
        for (int s : new int[] { 16, 32, 48, 256 }) {
            try (InputStream in = RectApp.class.getResourceAsStream("/icons/app" + s + ".png")) {
                if (in != null) icons.add(new Image(d, in));
            } catch (Exception e) {
                //без значка
            }
        }
        if (!icons.isEmpty()) sh.setImages(icons.toArray(new Image[0]));

        RectPanel panel = new RectPanel();
        panel.createPartControl(sh);

        Rectangle m = d.getPrimaryMonitor().getClientArea();
        int w = Math.min(m.width, PREFS.getInt("w", 1400)), h = Math.min(m.height, PREFS.getInt("h", 880));
        sh.setBounds(PREFS.getInt("x", m.x + (m.width - w) / 2), PREFS.getInt("y", m.y + (m.height - h) / 2), w, h);
        if (PREFS.getBoolean("max", false)) sh.setMaximized(true);
        sh.addListener(SWT.Close, e -> {
            PREFS.putBoolean("max", sh.getMaximized());
            if (!sh.getMaximized()) {
                Rectangle b = sh.getBounds();
                PREFS.putInt("x", b.x);
                PREFS.putInt("y", b.y);
                PREFS.putInt("w", b.width);
                PREFS.putInt("h", b.height);
            }
            panel.disposeAndWait();             //Осциллограмму и управление с ПК - выключить до выхода
        });
        sh.open();
        panel.setFocus();
        while (!sh.isDisposed()) {
            if (!d.readAndDispatch()) d.sleep();
        }
        for (Image i : icons) i.dispose();
        d.dispose();
        System.exit(0);
    }
}
