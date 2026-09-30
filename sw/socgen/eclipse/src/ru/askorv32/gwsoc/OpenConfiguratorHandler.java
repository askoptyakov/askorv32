package ru.askorv32.gwsoc;

import org.eclipse.core.commands.AbstractHandler;
import org.eclipse.core.commands.ExecutionEvent;
import org.eclipse.core.commands.ExecutionException;
import org.eclipse.core.resources.IFile;
import org.eclipse.core.resources.IProject;
import org.eclipse.core.resources.IResource;
import org.eclipse.core.runtime.Adapters;
import org.eclipse.core.runtime.CoreException;
import org.eclipse.jface.dialogs.MessageDialog;
import org.eclipse.jface.viewers.ISelection;
import org.eclipse.jface.viewers.IStructuredSelection;
import org.eclipse.ui.IEditorPart;
import org.eclipse.ui.IFileEditorInput;
import org.eclipse.ui.IWorkbenchWindow;
import org.eclipse.ui.handlers.HandlerUtil;
import org.eclipse.ui.ide.IDE;

/**
 * Команда «Конфигуратор ПЛИС» (меню проекта и панель инструментов): открывает файл .gwsoc
 * из корня выбранного проекта (или проекта активного редактора) в конфигураторе.
 */
public class OpenConfiguratorHandler extends AbstractHandler {
    @Override
    public Object execute(ExecutionEvent event) throws ExecutionException {
        IWorkbenchWindow win = HandlerUtil.getActiveWorkbenchWindowChecked(event);
        IProject project = projectOf(HandlerUtil.getCurrentSelection(event));
        if (project == null) {
            IEditorPart ed = win.getActivePage().getActiveEditor();
            if (ed != null && ed.getEditorInput() instanceof IFileEditorInput fi) project = fi.getFile().getProject();
        }
        if (project == null) {
            MessageDialog.openInformation(win.getShell(), "Конфигуратор ПЛИС", "Выберите проект с кодом МК в Project Explorer.");
            return null;
        }
        IFile cfg = findConfig(project);
        if (cfg == null) {
            MessageDialog.openInformation(win.getShell(), "Конфигуратор ПЛИС",
                "В корне проекта «" + project.getName() + "» нет файла конфигурации ПЛИС (*.gwsoc).");
            return null;
        }
        try {
            IDE.openEditor(win.getActivePage(), cfg, GwsocEditor.ID, true);
        } catch (CoreException e) {
            throw new ExecutionException("Не удалось открыть " + cfg.getName(), e);
        }
        return null;
    }

    private static IProject projectOf(ISelection sel) {
        if (sel instanceof IStructuredSelection ss && !ss.isEmpty()) {
            IResource r = Adapters.adapt(ss.getFirstElement(), IResource.class);
            if (r != null) return r.getProject();
        }
        return null;
    }

    private static IFile findConfig(IProject project) {
        try {
            for (IResource r : project.members())
                if (r instanceof IFile f && "gwsoc".equalsIgnoreCase(f.getFileExtension())) return f;
        } catch (CoreException ignored) { }
        return null;
    }
}
