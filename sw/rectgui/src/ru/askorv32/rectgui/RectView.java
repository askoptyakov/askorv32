package ru.askorv32.rectgui;

import org.eclipse.swt.widgets.Composite;
import org.eclipse.ui.part.ViewPart;

/**
 * Вид Eclipse «Пульт выпрямителя»: сама панель - RectPanel (её же показывает отдельная программа RectApp).
 */
public class RectView extends ViewPart {
    public static final String ID = "ru.askorv32.rectgui.view";
    private final RectPanel panel = new RectPanel();

    @Override
    public void createPartControl(Composite parent) {
        panel.createPartControl(parent);
    }

    @Override
    public void setFocus() {
        panel.setFocus();
    }

    @Override
    public void dispose() {
        panel.dispose();
        super.dispose();
    }
}
