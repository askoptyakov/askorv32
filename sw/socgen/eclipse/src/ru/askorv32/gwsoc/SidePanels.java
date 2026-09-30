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
import org.eclipse.swt.widgets.Control;
import org.eclipse.swt.widgets.Display;
import org.eclipse.ui.IPartListener2;
import org.eclipse.ui.IWorkbenchPage;
import org.eclipse.ui.IWorkbenchPartReference;
import org.eclipse.ui.IWorkbenchPartSite;

/**
 * Пока вкладка конфигуратора видна, все панели вне области редакторов (Project Explorer, Outline,
 * Problems, Console...) свёрнуты в значки по краям окна - как кнопкой Minimize. Когда вкладка
 * скрывается (активен другой редактор) или закрывается, свёрнутые здесь панели возвращаются.
 * Панели, свёрнутые пользователем заранее, не трогаются.
 */
final class SidePanels {
    private final IWorkbenchPartSite site;
    private final Object part;
    private final Control anchor;         //Содержимое редактора: пока оно не видно, сворачивать нечего
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

    //После раскладки окна: при открытии редактора модель ещё перестраивается
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
        for (MPartStack st : ms.findElements(persp, null, MPartStack.class, null)) {
            if (!st.isToBeRendered() || !st.isVisible() || st.getChildren().isEmpty()) continue;
            if (st.getTags().contains(IPresentationEngine.MINIMIZED) || inEditorArea(st)) continue;
            st.getTags().add(IPresentationEngine.MINIMIZED);
            folded.add(st);
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
}
