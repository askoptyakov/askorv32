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
 * для проекта с файлом .gwsoc (выбранного или проекта активного редактора).
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
        IFile cfg = project != null ? OpenConfiguratorHandler.findConfig(project) : null;
        if (cfg == null) {
            MessageDialog.openInformation(win.getShell(), "Программатор ПЛИС",
                project == null ? "Выберите проект с кодом МК в Project Explorer."
                                : "В корне проекта «" + project.getName() + "» нет файла конфигурации ПЛИС (*.gwsoc).");
            return null;
        }
        ProgrammerDialog.open(win.getShell(), project, cfg);
        return null;
    }
}
