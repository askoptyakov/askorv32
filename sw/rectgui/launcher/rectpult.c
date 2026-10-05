/*
 * RectPult.exe - запуск пульта выпрямителя askoRV32 без Eclipse: рядом с программой каталоги runtime (Java)
 * и lib (rectgui.jar, SWT, COM-порт CDT, serial.dll). Запускает runtime\bin\javaw.exe с классом RectApp
 * и выходит. Сборка - sw/rectgui/build_exe.py (gcc и windres MSYS2 UCRT64).
 */
#include <windows.h>
#include <wchar.h>

#define MAIN_CLASS L"ru.askorv32.rectgui.RectApp"

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE prev, PWSTR args, int show) {
	wchar_t dir[MAX_PATH], java[MAX_PATH + 32], cmd[4 * MAX_PATH + 256];
	(void)inst; (void)prev; (void)show;
	DWORD n = GetModuleFileNameW(NULL, dir, MAX_PATH);
	if (n == 0 || n >= MAX_PATH) return 1;
	wchar_t *slash = wcsrchr(dir, L'\\');
	if (slash) *slash = L'\0';

	_snwprintf(java, sizeof java / sizeof java[0], L"%ls\\runtime\\bin\\javaw.exe", dir);
	java[sizeof java / sizeof java[0] - 1] = L'\0';
	if (GetFileAttributesW(java) == INVALID_FILE_ATTRIBUTES) {
		MessageBoxW(NULL, L"Не найдена Java: каталог runtime рядом с RectPult.exe.\nСоберите программу заново: py sw/rectgui/build_exe.py",
		            L"Пульт выпрямителя askoRV32", MB_ICONERROR);
		return 1;
	}
	_snwprintf(cmd, sizeof cmd / sizeof cmd[0],
	           L"\"%ls\" -Dfile.encoding=UTF-8 --enable-native-access=ALL-UNNAMED \"-Djava.library.path=%ls\\lib\" "
	           L"-cp \"%ls\\lib\\*\" " MAIN_CLASS L" %ls", java, dir, dir, args ? args : L"");
	cmd[sizeof cmd / sizeof cmd[0] - 1] = L'\0';

	STARTUPINFOW si = { sizeof si };
	PROCESS_INFORMATION pi;
	if (!CreateProcessW(NULL, cmd, NULL, NULL, FALSE, 0, NULL, dir, &si, &pi)) {
		MessageBoxW(NULL, L"Не удалось запустить Java (runtime\\bin\\javaw.exe).", L"Пульт выпрямителя askoRV32", MB_ICONERROR);
		return 1;
	}
	CloseHandle(pi.hThread);
	CloseHandle(pi.hProcess);
	return 0;
}
