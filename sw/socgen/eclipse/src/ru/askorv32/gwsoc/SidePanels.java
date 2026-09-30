package ru.askorv32.gwsoc;

import java.util.ArrayList;
import java.util.List;

import org.eclipse.e4.ui.model.application.ui.MUIElement;
import org.eclipse.e4.ui.model.application.ui.advanced.MArea;
import org.eclipse.e4.ui.model.application.ui.advanced.MPerspective;
import org.eclipse.e4.ui.model.application.ui.basic.MPartStack;
import org.eclipse.e4.ui.model.application.ui.basic.MWindow;
import org.eclipse.e4.ui.workbench.IPresentationEngine;
import org.eclipse.e4.ui.workbench.modeling.EModelService;
import org.eclipse.swt.graphics.Point;
import org.eclipse.swt.graphics.Rectangle;
import org.eclipse.swt.widgets.Control;
import org.eclipse.swt.widgets.Display;
import org.eclipse.ui.IPartListener2;
import org.eclipse.ui.IWorkbenchPage;
import org.eclipse.ui.IWorkbenchPartReference;
import org.eclipse.ui.IWorkbenchPartSite;

/**
 * Пока вкладка конфигуратора видна, панели справа и снизу от редактора (Outline, Problems, Console...)
 * свёрнуты в значки по краям окна - как кнопкой Minimize. Когда вкладка скрывается (активен другой
 * редактор) или закрывается, свёрнутые здесь панели возвращаются. Project Explorer слева не трогается.
 */
final class SidePanels {
    private static final int SLACK = 8;   //Допуск на рамки и разделители, px

    private final IWorkbenchPartSite site;
    private final Object part;
    private final Control anchor;         //Содержимое редактора: по нему видно, где область редакторов
    private final List<MPartStack> folded = new ArrayList<>();

    private final IPartListener2 listener = new IPartListener2() {
        @Override
        public void partVisible(IWorkbenchPartReference ref) {
            if (ref.getPart(false) == part) foldLater();
        }

        @Override
        public void partHidden(IWorkbenchPartReference ref) {
            if (ref.getPart(false) == part) unfold();
        }
    };

    SidePanels(IWorkbenchPartSite site, Object part, Control anchor) {
        this.site = site;
        this.part = part;
        this.anchor = anchor;
    }

    void install() {
        site.getPage().addPartListener(listener);
        foldLater();   //Редактор уже виден: первое partVisible пришло до установки слушателя
    }

    void dispose() {
        IWorkbenchPage page = site.getPage();
        if (page != null) page.removePartListener(listener);
        unfold();
    }

    //После раскладки окна: при открытии редактора размеры ещё не известны
    private void foldLater() {
        Display.getDefault().asyncExec(this::fold);
    }

    private void fold() {
        if (anchor.isDisposed() || !anchor.isVisible()) return;
        EModelService ms = site.getService(EModelService.class);
        MWindow win = site.getService(MWindow.class);
        if (ms == null || win == null) return;
        MPerspective persp = ms.getActivePerspective(win);
        if (persp == null) return;
        Rectangle ed = displayBounds(anchor);
        for (MPartStack st : ms.findElements(persp, null, MPartStack.class, null)) {
            if (!st.isToBeRendered() || !st.isVisible() || st.getChildren().isEmpty()) continue;
            if (st.getTags().contains(IPresentationEngine.MINIMIZED) || inEditorArea(st)) continue;
            if (!(st.getWidget() instanceof Control c) || c.isDisposed() || !c.isVisible()) continue;
            Rectangle b = displayBounds(c);
            boolean right = b.x >= ed.x + ed.width - SLACK;
            boolean below = b.y >= ed.y + ed.height - SLACK;
            if (right || below) {
                st.getTags().add(IPresentationEngine.MINIMIZED);
                folded.add(st);
            }
        }
    }

    private void unfold() {
        for (MPartStack st : folded) st.getTags().remove(IPresentationEngine.MINIMIZED);
        folded.clear();
    }

    private static boolean inEditorArea(MUIElement e) {
        for (MUIElement p = e; p != null; p = p.getParent())
            if (p instanceof MArea) return true;
        return false;
    }

    private static Rectangle displayBounds(Control c) {
        Point p = c.toDisplay(0, 0);
        Point s = c.getSize();
        return new Rectangle(p.x, p.y, s.x, s.y);
    }
}
