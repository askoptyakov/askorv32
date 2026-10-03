package ru.askorv32.gwsoc;

import org.eclipse.core.commands.AbstractHandler;
import org.eclipse.core.commands.ExecutionEvent;
import org.eclipse.core.commands.ExecutionException;
import org.eclipse.core.resources.IFile;
import org.eclipse.core.resources.IProject;
import java.util.ArrayList;
import java.util.List;

import org.eclipse.core.resources.IContainer;
import org.eclipse.core.resources.IFolder;
import org.eclipse.core.resources.IResource;
import org.eclipse.core.runtime.Adapters;
import org.eclipse.core.runtime.CoreException;
import org.eclipse.jface.dialogs.MessageDialog;
import org.eclipse.jface.viewers.LabelProvider;
import org.eclipse.jface.window.Window;
import org.eclipse.swt.widgets.Shell;
import org.eclipse.jface.viewers.ISelection;
import org.eclipse.jface.viewers.IStructuredSelection;
import org.eclipse.ui.IEditorPart;
import org.eclipse.ui.IFileEditorInput;
import org.eclipse.ui.IWorkbenchWindow;
import org.eclipse.ui.dialogs.ElementListSelectionDialog;
import org.eclipse.ui.handlers.HandlerUtil;
import org.eclipse.ui.ide.IDE;

/**
 * Команда «Конфигуратор ПЛИС» (меню проекта и панель инструментов): открывает файл .gwsoc выбранного проекта
 * (или проекта активного редактора) в конфигураторе. Файлы плат - fw/boards/<плата>/<плата>.gwsoc (или корень
 * проекта - старый вид); если плат несколько, берётся выделенный файл или плата выбирается из списка.
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
        IFile cfg = chooseConfig(win.getShell(), project, HandlerUtil.getCurrentSelection(event), "Конфигуратор ПЛИС");
        if (cfg == null) return null;
        try {
            IDE.openEditor(win.getActivePage(), cfg, GwsocEditor.ID, true);
        } catch (CoreException e) {
            throw new ExecutionException("Не удалось открыть " + cfg.getName(), e);
        }
        return null;
    }

    static IProject projectOf(ISelection sel) {
        if (sel instanceof IStructuredSelection ss && !ss.isEmpty()) {
            IResource r = Adapters.adapt(ss.getFirstElement(), IResource.class);
            if (r != null) return r.getProject();
        }
        return null;
    }

    //Файлы конфигурации ПЛИС проекта: корень и подкаталоги на два уровня (fw/boards/<плата>/)
    static List<IFile> findConfigs(IProject project) {
        List<IFile> out = new ArrayList<>();
        collect(project, 0, out);
        out.sort((a, b) -> a.getProjectRelativePath().toString().compareToIgnoreCase(b.getProjectRelativePath().toString()));
        return out;
    }

    private static void collect(IContainer c, int depth, List<IFile> out) {
        try {
            for (IResource r : c.members()) {
                if (r instanceof IFile f && "gwsoc".equalsIgnoreCase(f.getFileExtension())) out.add(f);
                else if (r instanceof IFolder d && depth < 2 && !d.getName().startsWith(".")) collect(d, depth + 1, out);
            }
        } catch (CoreException ignored) { }
    }

    //Плата для команды: выделенный в Project Explorer файл .gwsoc, единственный в проекте или выбранный из списка
    static IFile chooseConfig(Shell shell, IProject project, ISelection sel, String title) {
        if (sel instanceof IStructuredSelection ss && !ss.isEmpty()) {
            IResource r = Adapters.adapt(ss.getFirstElement(), IResource.class);
            if (r instanceof IFile f && "gwsoc".equalsIgnoreCase(f.getFileExtension())) return f;
        }
        List<IFile> all = findConfigs(project);
        if (all.isEmpty()) {
            MessageDialog.openInformation(shell, title,
                "В проекте «" + project.getName() + "» нет файла конфигурации ПЛИС (fw/boards/<плата>/<плата>.gwsoc).");
            return null;
        }
        if (all.size() == 1) return all.get(0);
        ElementListSelectionDialog d = new ElementListSelectionDialog(shell, new LabelProvider() {
            @Override
            public String getText(Object o) {
                if (!(o instanceof IFile f)) return String.valueOf(o);
                String n = f.getName();
                return n.substring(0, n.length() - ".gwsoc".length()) + "   (" + f.getProjectRelativePath() + ")";
            }
        });
        d.setTitle(title);
        d.setMessage("Плата - файл конфигурации ПЛИС:");
        d.setElements(all.toArray());
        d.setMultipleSelection(false);
        return d.open() == Window.OK && d.getFirstResult() instanceof IFile f ? f : null;
    }
}
