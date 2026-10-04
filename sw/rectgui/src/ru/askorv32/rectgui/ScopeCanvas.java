package ru.askorv32.rectgui;

import java.util.Locale;

import org.eclipse.swt.SWT;
import org.eclipse.swt.graphics.Color;
import org.eclipse.swt.graphics.GC;
import org.eclipse.swt.graphics.Point;
import org.eclipse.swt.graphics.Rectangle;
import org.eclipse.swt.widgets.Canvas;
import org.eclipse.swt.widgets.Composite;

/**
 * Осциллограмма напряжения и тока: кадр 20 мс (400 точек на канал). Шкала U - слева, I - справа,
 * время - от точки запуска. Вертикальная линия - положение запуска (сколько кадра до него), пунктир
 * поперёк - уровень запуска на шкале канала-источника. Обе линии перетаскиваются мышью; новое значение
 * уходит слушателю, когда кнопку отпустили.
 */
final class ScopeCanvas extends Canvas {
    interface TriggerListener {
        /** level - уровень запуска в единицах канала-источника; pre - точек до запуска */
        void moved(double level, int pre);
    }

    static final int DIV_X = 10, DIV_Y = 8;
    private static final int ML = 64, MR = 64, MT = 22, MB = 24;   //Поля: подписи шкал

    private final Color bg, grid, axis, cU, cI, cTrig, text;
    private RectLink.Frame frame;
    private Cal calU = Cal.RAW, calI = Cal.RAW;
    private int src, edge, pre = 100, n = 400, dt = 50;
    private double level;
    private boolean zero = true, frozen;
    private final double[] rangeU = { 0, 1 }, rangeI = { 0, 1 };
    private int drag;               //0 - нет, 1 - уровень, 2 - положение
    private TriggerListener listener;

    /** Пересчёт кода АЦП в единицы: (код - смещение) * масштаб */
    static final class Cal {
        static final Cal RAW = new Cal(1e6, 0, "код");
        final double scale, offset;
        final String unit;

        Cal(double scaleU, double offsetM, String unit) {
            this.scale = scaleU / 1e6;
            this.offset = offsetM / 1000.0;
            this.unit = unit;
        }

        double phys(int code) {
            return (code - offset) * scale;
        }

        int code(double v) {
            long c = Math.round(v / scale + offset);
            return (int) Math.max(0, Math.min(4095, c));
        }
    }

    ScopeCanvas(Composite parent) {
        super(parent, SWT.DOUBLE_BUFFERED | SWT.NO_BACKGROUND);
        bg = new Color(18, 20, 24);
        grid = new Color(52, 56, 64);
        axis = new Color(96, 102, 112);
        cU = new Color(250, 204, 21);
        cI = new Color(56, 189, 248);
        cTrig = new Color(251, 146, 60);
        text = new Color(200, 204, 210);
        addPaintListener(e -> paint(e.gc));
        addDisposeListener(e -> {
            for (Color c : new Color[] { bg, grid, axis, cU, cI, cTrig, text }) c.dispose();
        });
        addListener(SWT.MouseDown, e -> {
            if (e.button != 1) return;
            drag = hit(e.x, e.y);
        });
        addListener(SWT.MouseMove, e -> {
            if (drag == 0) {
                int h = hit(e.x, e.y);
                setCursor(getDisplay().getSystemCursor(h == 1 ? SWT.CURSOR_SIZENS : h == 2 ? SWT.CURSOR_SIZEWE : SWT.CURSOR_ARROW));
                return;
            }
            Rectangle p = plot();
            if (drag == 1) {
                double[] r = src == 0 ? rangeU : rangeI;
                int y = Math.max(p.y, Math.min(p.y + p.height, e.y));
                level = r[1] - (double) (y - p.y) / p.height * (r[1] - r[0]);
            } else {
                int x = Math.max(p.x, Math.min(p.x + p.width, e.x));
                pre = (int) Math.round((double) (x - p.x) / p.width * (n - 1));
                pre = Math.max(0, Math.min(n - 1, pre));
            }
            redraw();
        });
        addListener(SWT.MouseUp, e -> {
            if (drag != 0 && listener != null) listener.moved(level, pre);
            drag = 0;
        });
    }

    void setTriggerListener(TriggerListener l) {
        listener = l;
    }

    void setCal(Cal u, Cal i) {
        calU = u;
        calI = i;
        redraw();
    }

    void setTrigger(int src, int edge, double level, int pre) {
        this.src = src;
        this.edge = edge;
        this.level = level;
        this.pre = pre;
        redraw();
    }

    void setZero(boolean z) {
        zero = z;
        rescale(true);
        redraw();
    }

    void setFrozen(boolean f) {
        frozen = f;
    }

    void setFrame(RectLink.Frame f) {
        if (frozen) return;
        frame = f;
        n = f.n;
        dt = f.dt;
        rescale(false);
        redraw();
    }

    RectLink.Frame getFrame() {
        return frame;
    }

    private Rectangle plot() {
        Point s = getSize();
        return new Rectangle(ML, MT, Math.max(10, s.x - ML - MR), Math.max(10, s.y - MT - MB));
    }

    private int hit(int x, int y) {
        Rectangle p = plot();
        if (x < p.x - 4 || x > p.x + p.width + 4 || y < p.y - 4 || y > p.y + p.height + 4) return 0;
        if (edge != 2 && Math.abs(y - yOf(level, src == 0 ? rangeU : rangeI, p)) <= 5) return 1;
        if (Math.abs(x - xOf(pre, p)) <= 5) return 2;
        return 0;
    }

    private int xOf(double k, Rectangle p) {
        return p.x + (int) Math.round(k / Math.max(1, n - 1) * p.width);
    }

    private static int yOf(double v, double[] r, Rectangle p) {
        double t = (v - r[0]) / (r[1] - r[0]);
        return p.y + p.height - (int) Math.round(t * p.height);
    }

    /** Шкала: шаг 1-2-5 на DIV_Y клеток. Расширяется сразу, сжимается, если данные заняли меньше трети */
    private void rescale(boolean force) {
        if (frame == null) return;
        fit(rangeU, frame.u, calU, src == 0 && edge != 2 ? level : Double.NaN, force);
        fit(rangeI, frame.c, calI, src == 1 && edge != 2 ? level : Double.NaN, force);
    }

    private void fit(double[] r, int[] codes, Cal cal, double lvl, boolean force) {
        double lo = Double.MAX_VALUE, hi = -Double.MAX_VALUE;
        for (int c : codes) {
            double v = cal.phys(c);
            lo = Math.min(lo, v);
            hi = Math.max(hi, v);
        }
        if (zero) {
            lo = Math.min(lo, 0);
            hi = Math.max(hi, 0);
        }
        double span = hi - lo, min = cal.scale * 8;     //Не мельче 1 кода на клетку
        if (span < min) {
            double mid = (lo + hi) / 2;
            lo = mid - min / 2;
            hi = mid + min / 2;
            span = min;
        }
        boolean inside = lo >= r[0] && hi <= r[1];
        if (!force && inside && span > (r[1] - r[0]) / 3) return;
        double step = nice(span * 1.1 / DIV_Y);
        double a = Math.floor(lo / step) * step;
        while (a + step * DIV_Y < hi) step = nice(step * 1.01);
        a = Math.floor(lo / step) * step;
        if (a + step * DIV_Y < hi) a = hi - step * DIV_Y;
        r[0] = a;
        r[1] = a + step * DIV_Y;
    }

    private static double nice(double x) {
        double e = Math.pow(10, Math.floor(Math.log10(x))), m = x / e;
        return (m <= 1 ? 1 : m <= 2 ? 2 : m <= 5 ? 5 : 10) * e;
    }

    private static String fmt(double v, double step) {
        int d = step >= 1 ? 0 : step >= 0.1 ? 1 : step >= 0.01 ? 2 : 3;
        return String.format(Locale.ROOT, "%." + d + "f", v).replace('.', ',');
    }

    private void paint(GC gc) {
        Point s = getSize();
        Rectangle p = plot();
        gc.setBackground(bg);
        gc.fillRectangle(0, 0, s.x, s.y);
        gc.setForeground(grid);
        gc.setLineStyle(SWT.LINE_DOT);
        for (int k = 1; k < DIV_X; k++) gc.drawLine(p.x + k * p.width / DIV_X, p.y, p.x + k * p.width / DIV_X, p.y + p.height);
        for (int k = 1; k < DIV_Y; k++) gc.drawLine(p.x, p.y + k * p.height / DIV_Y, p.x + p.width, p.y + k * p.height / DIV_Y);
        gc.setLineStyle(SWT.LINE_SOLID);
        gc.setForeground(axis);
        gc.drawRectangle(p);

        //Шкалы
        double su = (rangeU[1] - rangeU[0]) / DIV_Y, si = (rangeI[1] - rangeI[0]) / DIV_Y;
        int fh = gc.getFontMetrics().getHeight();
        for (int k = 0; k <= DIV_Y; k++) {
            int y = p.y + p.height - k * p.height / DIV_Y - fh / 2;
            gc.setForeground(cU);
            String a = fmt(rangeU[0] + k * su, su);
            gc.drawString(a, p.x - 6 - gc.textExtent(a).x, y, true);
            gc.setForeground(cI);
            gc.drawString(fmt(rangeI[0] + k * si, si), p.x + p.width + 6, y, true);
        }
        gc.setForeground(cU);
        gc.drawString("U, " + calU.unit, 4, 3, true);
        gc.setForeground(cI);
        String iu = "I, " + calI.unit;
        gc.drawString(iu, s.x - 4 - gc.textExtent(iu).x, 3, true);
        gc.setForeground(text);
        double tdiv = (double) (n - 1) * dt / DIV_X / 1000.0;   //мс на клетку
        for (int k = 0; k <= DIV_X; k += 2) {
            double t = (k * (double) (n - 1) / DIV_X - pre) * dt / 1000.0;
            String a = fmt(t, 0.1) + " мс";
            int x = p.x + k * p.width / DIV_X - gc.textExtent(a).x / 2;
            gc.drawString(a, Math.max(0, Math.min(s.x - gc.textExtent(a).x, x)), p.y + p.height + 4, true);
        }
        String hdr = fmt(tdiv, 0.1) + " мс/дел.   U " + fmt(su, su) + " " + calU.unit + "/дел.   I " + fmt(si, si) + " " + calI.unit + "/дел.";
        gc.drawString(hdr, p.x + (p.width - gc.textExtent(hdr).x) / 2, 3, true);

        if (frame == null) {
            String m = "Нет кадра: подключите стенд и включите осциллограмму";
            gc.drawString(m, p.x + (p.width - gc.textExtent(m).x) / 2, p.y + p.height / 2 - fh / 2, true);
        } else {
            gc.setAdvanced(true);
            gc.setAntialias(SWT.ON);
            trace(gc, p, frame.c, calI, rangeI, cI);
            trace(gc, p, frame.u, calU, rangeU, cU);
            gc.setAntialias(SWT.OFF);
        }

        //Запуск: положение (вертикаль) и уровень (пунктир на шкале источника)
        gc.setForeground(cTrig);
        gc.setLineStyle(SWT.LINE_DASH);
        int xt = xOf(pre, p);
        gc.drawLine(xt, p.y, xt, p.y + p.height);
        gc.setBackground(cTrig);
        gc.fillPolygon(new int[] { xt - 5, p.y - 7, xt + 5, p.y - 7, xt, p.y - 1 });
        if (edge != 2) {
            double[] r = src == 0 ? rangeU : rangeI;
            int yt = Math.max(p.y, Math.min(p.y + p.height, yOf(level, r, p)));
            gc.setForeground(src == 0 ? cU : cI);
            gc.drawLine(p.x, yt, p.x + p.width, yt);
            gc.setBackground(src == 0 ? cU : cI);
            int xm = src == 0 ? p.x : p.x + p.width;
            int dx = src == 0 ? -7 : 7;
            gc.fillPolygon(new int[] { xm + dx, yt - 5, xm + dx, yt + 5, xm, yt });
            gc.setForeground(cTrig);
            String e = (edge == 0 ? "↑ " : "↓ ") + fmt(level, (r[1] - r[0]) / DIV_Y / 100) + " " + (src == 0 ? calU.unit : calI.unit);
            gc.drawString(e, xt + 6, Math.max(p.y + 2, Math.min(p.y + p.height - fh - 2, yt - fh - 2)), true);
        }
        gc.setLineStyle(SWT.LINE_SOLID);
        if (frame != null && edge != 2 && frame.trig == 0) {
            gc.setForeground(cTrig);
            String m = "нет запуска - кадр без синхронизации";
            gc.drawString(m, p.x + p.width - gc.textExtent(m).x - 6, p.y + 4, true);
        }
        if (frozen) {
            gc.setForeground(text);
            gc.drawString("СТОП-КАДР", p.x + 6, p.y + 4, true);
        }
    }

    private void trace(GC gc, Rectangle p, int[] codes, Cal cal, double[] r, Color c) {
        int[] pts = new int[codes.length * 2];
        for (int k = 0; k < codes.length; k++) {
            pts[2 * k] = xOf(k, p);
            pts[2 * k + 1] = Math.max(p.y - 2, Math.min(p.y + p.height + 2, yOf(cal.phys(codes[k]), r, p)));
        }
        gc.setForeground(c);
        gc.setLineWidth(1);
        gc.drawPolyline(pts);
    }
}
