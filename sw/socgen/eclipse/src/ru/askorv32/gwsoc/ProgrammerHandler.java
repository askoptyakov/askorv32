package ru.askorv32.gwsoc;

import org.eclipse.core.commands.AbstractHandler;
import org.eclipse.core.commands.ExecutionEvent;
import org.eclipse.core.commands.ExecutionException;
import org.eclipse.core.resources.IFile;
import org.eclipse.core.resources.IProject;
import org.eclipse.jface.dialogs.MessageDialog;
import org.eclipse.ui.IEditorPart;
import org.eclipse.ui.IFileEditorInput;
import org.eclipse.ui.IWorkbenchWindow;
import org.eclipse.ui.handlers.HandlerUtil;

/**
 * Команда «Программатор ПЛИС» (меню проекта и панель инструментов): окно записи и очистки памяти ПЛИС
 * для платы - файла .gwsoc проекта (выделенного, открытого в конфигураторе или выбранного из списка).
 */
public class ProgrammerHandler extends AbstractHandler {
    @Override
    public Object execute(ExecutionEvent event) throws ExecutionException {
        IWorkbenchWindow win = HandlerUtil.getActiveWorkbenchWindowChecked(event);
        IProject project = OpenConfiguratorHandler.projectOf(HandlerUtil.getCurrentSelection(event));
        if (project == null) {
            IEditorPart ed = win.getActivePage().getActiveEditor();
            if (ed != null && ed.getEditorInput() instanceof IFileEditorInput fi) project = fi.getFile().getProject();
        }
        if (project == null) {
            MessageDialog.openInformation(win.getShell(), "Программатор ПЛИС", "Выберите проект с кодом МК в Project Explorer.");
            return null;
        }
        //Плата: файл, открытый в конфигураторе (активный редактор), иначе выделенный .gwsoc, единственный или из списка
        IFile cfg = null;
        IEditorPart act = win.getActivePage().getActiveEditor();
        if (act instanceof GwsocEditor && act.getEditorInput() instanceof IFileEditorInput fi && fi.getFile().getProject().equals(project))
            cfg = fi.getFile();
        if (cfg == null) cfg = OpenConfiguratorHandler.chooseConfig(win.getShell(), project, HandlerUtil.getCurrentSelection(event), "Программатор ПЛИС");
        if (cfg == null) return null;
        ProgrammerDialog.open(win.getShell(), project, cfg);
        return null;
    }
}
