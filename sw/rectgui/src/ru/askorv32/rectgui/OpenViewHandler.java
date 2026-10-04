package ru.askorv32.rectgui;

import org.eclipse.core.commands.AbstractHandler;
import org.eclipse.core.commands.ExecutionEvent;
import org.eclipse.core.commands.ExecutionException;
import org.eclipse.ui.IWorkbenchWindow;
import org.eclipse.ui.PartInitException;
import org.eclipse.ui.handlers.HandlerUtil;

/** Кнопка панели инструментов: открыть «Пульт выпрямителя» */
public class OpenViewHandler extends AbstractHandler {
    @Override
    public Object execute(ExecutionEvent event) throws ExecutionException {
        IWorkbenchWindow w = HandlerUtil.getActiveWorkbenchWindowChecked(event);
        try {
            w.getActivePage().showView(RectView.ID);
        } catch (PartInitException e) {
            throw new ExecutionException("Пульт выпрямителя не открылся", e);
        }
        return null;
    }
}
