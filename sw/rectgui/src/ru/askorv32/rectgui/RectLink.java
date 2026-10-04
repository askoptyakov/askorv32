package ru.askorv32.rectgui;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.Charset;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;

import org.eclipse.cdt.serial.SerialPort;

/**
 * Связь с выпрямителем по UART (115200 8-N-1, cp1251) - протокол пульта (hw/info/rectifier_gui.md):
 * команда - строка «@...», ответ на каждую - одна строка «#S», «#I» или «#E»; кадры осциллограммы
 * («#W» и строки «#D») стенд шлёт сам раз в секунду. Команды уходят по одной: следующая - после ответа
 * на предыдущую (или через ACK_MS), так приём стенда (FIFO 16 байт) не переполняется. Очередь пуста -
 * раз в POLL_MS уходит «@S»: состояние и признак, что пульт на связи (стенд без него 3 с возвращает
 * местное управление). Строки без «#» - вывод терминала стенда.
 * Слушатель вызывается из потока приёма.
 */
final class RectLink {
    static final Charset CP1251 = Charset.forName("windows-1251");
    private static final int POLL_MS = 300;
    private static final int ACK_MS = 600;

    interface Listener {
        void status(Map<String, Integer> s);
        void info(Map<String, Integer> i, String fw);
        void frame(Frame f);
        void text(String line);
        void closed(String why);
    }

    /** Кадр осциллограммы: коды АЦП (0..4095) каналов U и I, точка запуска - pre */
    static final class Frame {
        int seq, n, dt, pre, trig, src, edge, lvl, late;
        int[] u, c;
    }

    private final Listener listener;
    private SerialPort port;
    private OutputStream out;
    private volatile boolean running;
    private final LinkedBlockingQueue<String> queue = new LinkedBlockingQueue<>();
    private final Object ackLock = new Object();
    private boolean acked;
    private Frame building;
    private int got;

    RectLink(Listener listener) {
        this.listener = listener;
    }

    static String[] ports() {
        try {
            String[] p = SerialPort.list();
            Arrays.sort(p, (a, b) -> {
                String da = a.replaceAll("\\D", ""), db = b.replaceAll("\\D", "");
                return da.isEmpty() || db.isEmpty() ? a.compareTo(b) : Integer.compare(Integer.parseInt(da), Integer.parseInt(db));
            });
            return p;
        } catch (IOException e) {
            return new String[0];
        }
    }

    void open(String name) throws IOException {
        SerialPort p = new SerialPort(name);
        p.setBaudRateValue(115200);
        p.open();
        port = p;
        out = p.getOutputStream();
        running = true;
        queue.clear();
        Thread rx = new Thread(this::readLoop, "rectgui-rx " + name);
        Thread tx = new Thread(this::writeLoop, "rectgui-tx " + name);
        rx.setDaemon(true);
        tx.setDaemon(true);
        rx.start();
        tx.start();
    }

    boolean isOpen() {
        return running;
    }

    /** Команда в очередь (без «\r») */
    void send(String cmd) {
        if (running) queue.add(cmd);
    }

    /** Отправить последние команды (не дольше 1 с) и закрыть порт. Не в потоке интерфейса */
    void close(String... last) {
        if (!running) return;
        for (String c : last) queue.add(c);
        long end = System.currentTimeMillis() + 1000;
        while (!queue.isEmpty() && System.currentTimeMillis() < end) {
            try {
                Thread.sleep(20);
            } catch (InterruptedException e) {
                break;
            }
        }
        shutdown(null);
    }

    private void shutdown(String why) {
        boolean was = running;
        running = false;
        synchronized (ackLock) {
            ackLock.notifyAll();
        }
        try {
            if (port != null) port.close();
        } catch (IOException e) {
            //Порт уже закрыт
        }
        if (was) listener.closed(why);
    }

    private void writeLoop() {
        try {
            while (running) {
                String cmd = queue.poll(POLL_MS, TimeUnit.MILLISECONDS);
                if (cmd == null) cmd = "@S";
                synchronized (ackLock) {
                    acked = false;
                }
                out.write((cmd + "\r").getBytes(CP1251));
                out.flush();
                long end = System.currentTimeMillis() + ACK_MS;
                synchronized (ackLock) {
                    long left;
                    while (!acked && running && (left = end - System.currentTimeMillis()) > 0) ackLock.wait(left);
                }
            }
        } catch (IOException e) {
            if (running) shutdown("ошибка передачи: " + e.getMessage());
        } catch (InterruptedException e) {
            shutdown(null);
        }
    }

    private void readLoop() {
        ByteArrayOutputStream line = new ByteArrayOutputStream(1500);
        byte[] buf = new byte[512];
        try {
            InputStream in = port.getInputStream();
            boolean first = true;                           //Первая строка без «#» - принята с середины: отбросить
            while (running) {
                int n = in.read(buf);
                if (n < 0) break;
                for (int k = 0; k < n; k++) {
                    byte b = buf[k];
                    if (b == '\r' || b == '\n') {
                        byte[] ln = line.toByteArray();
                        if (ln.length > 0 && (!first || ln[0] == '#')) handle(new String(ln, CP1251));
                        line.reset();
                        first = false;
                    } else if (line.size() < 4096) line.write(b);
                }
            }
            if (running) shutdown("порт закрыт");
        } catch (IOException e) {
            if (running) shutdown("ошибка приёма: " + e.getMessage());
        }
    }

    private void ack() {
        synchronized (ackLock) {
            acked = true;
            ackLock.notifyAll();
        }
    }

    private static Map<String, Integer> kv(String line, Map<String, String> strings) {
        Map<String, Integer> m = new HashMap<>();
        for (String t : line.trim().split("\\s+")) {
            int e = t.indexOf('=');
            if (e <= 0) continue;
            String k = t.substring(0, e), v = t.substring(e + 1);
            try {
                m.put(k, Integer.parseInt(v));
            } catch (NumberFormatException x) {
                if (strings != null) strings.put(k, v);
            }
        }
        return m;
    }

    private void handle(String s) {
        while (s.startsWith("> ")) s = s.substring(2);      //Приглашение терминала перед строкой
        if (s.startsWith("#S")) {
            ack();
            listener.status(kv(s.substring(2), null));
        } else if (s.startsWith("#I")) {
            ack();
            Map<String, String> str = new HashMap<>();
            Map<String, Integer> m = kv(s.substring(2), str);
            listener.info(m, str.getOrDefault("fw", "?"));
        } else if (s.startsWith("#E")) {
            ack();
            listener.text("Стенд не понял команду: " + s.substring(2).trim());
        } else if (s.startsWith("#W")) {
            Map<String, Integer> m = kv(s.substring(2), null);
            Frame f = new Frame();
            f.seq = m.getOrDefault("seq", 0);
            f.n = m.getOrDefault("n", 0);
            f.dt = m.getOrDefault("dt", 50);
            f.pre = m.getOrDefault("pre", 0);
            f.trig = m.getOrDefault("trig", 0);
            f.src = m.getOrDefault("src", 0);
            f.edge = m.getOrDefault("edge", 0);
            f.lvl = m.getOrDefault("lvl", 0);
            f.late = m.getOrDefault("late", 0);
            if (f.n <= 0 || f.n > 10000) return;
            f.u = new int[f.n];
            f.c = new int[f.n];
            building = f;
            got = 0;
        } else if (s.startsWith("#D")) {
            Frame f = building;
            String[] p = s.split("\\s+");
            if (f == null || p.length != 4) return;
            int[] dst = "U".equals(p[1]) ? f.u : "C".equals(p[1]) ? f.c : null;
            int off;
            try {
                off = Integer.parseInt(p[2]);
            } catch (NumberFormatException e) {
                return;
            }
            String hx = p[3];
            int cnt = hx.length() / 3;
            if (dst == null || off < 0 || off + cnt > f.n || hx.length() % 3 != 0) {
                building = null;                            //Кадр испорчен - ждём следующий
                return;
            }
            for (int k = 0; k < cnt; k++) {
                try {
                    dst[off + k] = Integer.parseInt(hx.substring(3 * k, 3 * k + 3), 16);
                } catch (NumberFormatException e) {
                    building = null;
                    return;
                }
            }
            got += cnt;
            if (got == 2 * f.n) {
                building = null;
                listener.frame(f);
            }
        } else if (!s.isBlank()) {
            listener.text(s);
        }
    }
}
