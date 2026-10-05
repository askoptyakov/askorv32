; Общий установщик инструментов askoRV32 (Inno Setup 6).
; Собирается скриптом build.py: он готовит каталог stage/ и передаёт версии через /D.
; Ручной запуск ISCC без build.py не предусмотрен.

#ifndef Stage
  #error Запускайте сборку через build.py
#endif

#define AppName "askoRV32 SDK"
#define EnvKeyUser "Environment"
#define EnvKeyMachine "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
#define StateKey "Software\askoRV32\SDK"

[Setup]
AppId={{6F0B7C2E-5A3D-4E8B-9C41-2D7A0E3F9B15}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=askoRV32
AppComments=Eclipse Embedded CDT, xPack RISC-V GCC, OpenOCD, openFPGALoader, OSS CAD Suite, Icarus Verilog
; Все инструменты - подпапками одного каталога: C:\riscv-sdk\eclipse, C:\riscv-sdk\riscv-toolchain, ...
; При выборе другой папки к ней добавляется riscv-sdk (D:\ -> D:\riscv-sdk)
DefaultDirName=C:\riscv-sdk
DirExistsWarning=no
UsePreviousAppDir=yes
UninstallFilesDir={app}\uninstall
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\eclipse\eclipse.exe
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; Без прав администратора - переменные среды пользователя; с правами (выбор в диалоге) - системные
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline
ChangesEnvironment=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
WizardSizePercent=120
ShowLanguageDialog=no
OutputDir={#OutDir}
OutputBaseFilename=askorv32-sdk-setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
LZMAUseSeparateProcess=yes
LZMANumBlockThreads=8

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"

[Messages]
ru.SelectDirLabel3=Инструменты будут установлены в отдельные папки внутри этого каталога (eclipse, riscv-toolchain, oss-cad-suite, iverilog, openfpgaloader, zadig). Что именно ставить - на следующей странице.
ru.SelectDirBrowseLabel=Нажмите «Далее», чтобы продолжить. Путь должен быть коротким, без пробелов и кириллицы, например C:\riscv-sdk или D:\riscv-sdk.
ru.FinishedLabel=Установка завершена. Переменные среды и PATH обновлены - откройте терминалы заново. В Eclipse импортируйте проект fw\ из репозитория askorv32 (File > Import > Existing Projects into Workspace): пути MCU и плагины askoRV32 уже настроены.

[Tasks]
Name: "desktopicon"; Description: "Ярлык Eclipse на рабочем столе"

[Files]
; Что ставить - решает окно выбора инструментов ([Code], ToolInst).
; solidbreak - у каждого инструмента свой сжатый поток: невыбранные не распаковываются впустую
Source: "{#Stage}\eclipse\*"; DestDir: "{app}\eclipse"; Check: ToolInst('eclipse'); Flags: ignoreversion recursesubdirs createallsubdirs solidbreak
Source: "{#Stage}\riscv-toolchain\{#GccDir}\*"; DestDir: "{app}\riscv-toolchain\{#GccDir}"; Check: ToolInst('gcc'); Flags: ignoreversion recursesubdirs createallsubdirs solidbreak
Source: "{#Stage}\riscv-toolchain\{#BuildToolsDir}\*"; DestDir: "{app}\riscv-toolchain\{#BuildToolsDir}"; Check: ToolInst('buildtools'); Flags: ignoreversion recursesubdirs createallsubdirs solidbreak
Source: "{#Stage}\riscv-toolchain\{#OpenOcdDir}\*"; DestDir: "{app}\riscv-toolchain\{#OpenOcdDir}"; Check: ToolInst('openocd'); Flags: ignoreversion recursesubdirs createallsubdirs solidbreak
Source: "{#Stage}\openfpgaloader\*"; DestDir: "{app}\openfpgaloader"; Check: ToolInst('openfpgaloader'); Flags: ignoreversion recursesubdirs createallsubdirs solidbreak
Source: "{#Stage}\oss-cad-suite\*"; DestDir: "{app}\oss-cad-suite"; Check: ToolInst('oss'); Flags: ignoreversion recursesubdirs createallsubdirs solidbreak
Source: "{#Stage}\iverilog\*"; DestDir: "{app}\iverilog"; Check: ToolInst('iverilog'); Flags: ignoreversion recursesubdirs createallsubdirs solidbreak
Source: "{#Stage}\zadig\*"; DestDir: "{app}\zadig"; Check: ToolInst('zadig'); Flags: ignoreversion solidbreak
; Сторонние установщики уже сжаты: без повторного сжатия, во временный каталог, запускаются в [Code]
Source: "{#Stage}\redist\{#PythonExe}"; DestDir: "{tmp}"; Check: ToolInst('python'); Flags: nocompression deleteafterinstall
Source: "{#Stage}\redist\{#GowinExe}"; DestDir: "{tmp}"; Check: ToolInst('gowin'); Flags: nocompression deleteafterinstall
Source: "{#Stage}\redist\{#GitHubExe}"; DestDir: "{tmp}"; Check: ToolInst('github'); Flags: nocompression deleteafterinstall

[Dirs]
; Рабочее пространство Eclipse по умолчанию (в профиле пользователя может быть пробел); при удалении не трогается
Name: "{app}\workspace"; Check: ToolHas('eclipse'); Flags: uninsneveruninstall

[Icons]
Name: "{group}\Eclipse (askoRV32)"; Filename: "{app}\eclipse\eclipse.exe"; WorkingDir: "{app}\eclipse"; Check: ToolHas('eclipse')
Name: "{group}\GTKWave"; Filename: "{code:ToolPath|iverilog}\gtkwave.exe"; Check: ToolHas('iverilog')
Name: "{group}\Zadig"; Filename: "{app}\zadig\{#ZadigExe}"; Check: ToolHas('zadig')
Name: "{group}\OSS CAD Suite (командная строка)"; Filename: "{cmd}"; Parameters: "/k ""{code:ToolPath|oss}\environment.bat"""; WorkingDir: "{userdocs}"; Check: ToolHas('oss')
Name: "{group}\Удалить {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Eclipse (askoRV32)"; Filename: "{app}\eclipse\eclipse.exe"; WorkingDir: "{app}\eclipse"; Tasks: desktopicon; Check: ToolHas('eclipse')

[UninstallDelete]
; Eclipse и OSS CAD Suite дописывают файлы при работе (кэш OSGi, __pycache__) - удаляются папки целиком
Type: filesandordirs; Name: "{app}\eclipse"
Type: filesandordirs; Name: "{app}\oss-cad-suite"
Type: dirifempty; Name: "{app}\riscv-toolchain"
Type: dirifempty; Name: "{app}"

[Code]
var
  { Инструменты: Id, название, размер (текст и МБ на диске), где найден (''- нет), найденная устаревшая версия
    (ToolOld: '' - нет; такой инструмент считается не установленным), обязателен, ставить }
  ToolId, ToolName, ToolSize, ToolFound, ToolOld, ToolOldPath: array of String;
  ToolMB: array of Integer;
  ToolRequired, ToolInstall: array of Boolean;
  ToolsPage: TWizardPage;
  ToolsList: TNewCheckListBox;
  ReinstallBox: TNewCheckBox;
  HintLabel, SpaceLabel: TNewStaticText;
  DetectedDir: String;

procedure Push(var A: TArrayOfString; S: String);
begin
  SetArrayLength(A, GetArrayLength(A) + 1);
  A[GetArrayLength(A) - 1] := S;
end;

procedure AddTool(Id, Name, Size: String; MB: Integer; Required: Boolean);
var
  N: Integer;
begin
  N := GetArrayLength(ToolId) + 1;
  SetArrayLength(ToolId, N);
  SetArrayLength(ToolName, N);
  SetArrayLength(ToolSize, N);
  SetArrayLength(ToolMB, N);
  SetArrayLength(ToolFound, N);
  SetArrayLength(ToolOld, N);
  SetArrayLength(ToolOldPath, N);
  SetArrayLength(ToolRequired, N);
  SetArrayLength(ToolInstall, N);
  ToolId[N - 1] := Id;
  ToolName[N - 1] := Name;
  ToolSize[N - 1] := Size;
  ToolMB[N - 1] := MB;
  ToolRequired[N - 1] := Required;
end;

function ToolIndex(Id: String): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to GetArrayLength(ToolId) - 1 do
    if ToolId[I] = Id then Result := I;
end;

{ Ставится ли инструмент сейчас }
function ToolInst(Id: String): Boolean;
begin
  Result := ToolInstall[ToolIndex(Id)];
end;

{ Каталог установленного (сейчас или раньше) инструмента: bin для компиляторов и программ, корень для Eclipse,
  OSS CAD Suite и Zadig, каталог IDE для Gowin; '' - инструмента нет }
function ToolPath(Id: String): String;
var
  I: Integer;
  App: String;
begin
  I := ToolIndex(Id);
  Result := ToolFound[I];
  if not ToolInstall[I] then exit;
  App := ExpandConstant('{app}');
  case Id of
    'eclipse':        Result := App + '\eclipse';
    'gcc':            Result := App + '\riscv-toolchain\{#GccDir}\bin';
    'buildtools':     Result := App + '\riscv-toolchain\{#BuildToolsDir}\bin';
    'openocd':        Result := App + '\riscv-toolchain\{#OpenOcdDir}\bin';
    'openfpgaloader': Result := App + '\openfpgaloader\bin';
    'oss':            Result := App + '\oss-cad-suite';
    'iverilog':       Result := App + '\iverilog\bin';
    'zadig':          Result := App + '\zadig';
  end;
end;

function ToolHas(Id: String): Boolean;
begin
  Result := ToolPath(Id) <> '';
end;

{ ---------- поиск уже установленного ---------- }

function Present(Path: String): Boolean;
begin
  Result := FileExists(Path) or DirExists(Path);
end;

{ Последний по алфавиту каталог по маске (Base\Mask), в котором есть файл Sub }
function FindDirGlob(Base, Mask, Sub: String): String;
var
  FR: TFindRec;
begin
  Result := '';
  if FindFirst(Base + '\' + Mask, FR) then
    try
      repeat
        if (FR.Attributes and FILE_ATTRIBUTE_DIRECTORY <> 0) and FileExists(Base + '\' + FR.Name + Sub) then
          if CompareText(Base + '\' + FR.Name, Result) > 0 then Result := Base + '\' + FR.Name;
      until not FindNext(FR);
    finally
      FindClose(FR);
    end;
end;

{ Каталог, если в нём есть файл Sub }
function DirWith(Dir, Sub: String): String;
begin
  if (Dir <> '') and FileExists(Dir + Sub) then Result := Dir else Result := '';
end;

{ Сравнение версий вида 1.9.11.03 по числам: <0, 0, >0 }
function CompareVer(A, B: String): Integer;
var
  PA, PB, NA, NB: Integer;
begin
  Result := 0;
  while (Result = 0) and ((A <> '') or (B <> '')) do begin
    PA := Pos('.', A + '.');
    PB := Pos('.', B + '.');
    NA := StrToIntDef(Copy(A, 1, PA - 1), 0);
    NB := StrToIntDef(Copy(B, 1, PB - 1), 0);
    Delete(A, 1, PA);
    Delete(B, 1, PB);
    if NA < NB then Result := -1 else if NA > NB then Result := 1;
  end;
end;

{ Запись установщика Gowin в списке программ (один ключ Gowin - последняя установка): каталог установки
  (там uninst.exe и IDE) и версия «V1.9.11.03 Education (64-bit)». Установщик Gowin 32-битный - ищется в обоих видах реестра }
function GowinUninstEntry(var Dir, Ver: String): Boolean;
var
  Roots: array of Integer;
  I: Integer;
  Uninst: String;
begin
  Result := False;
  SetArrayLength(Roots, 3);
  Roots[0] := HKLM64;
  Roots[1] := HKLM32;
  Roots[2] := HKCU;
  for I := 0 to 2 do
    if not Result and RegQueryStringValue(Roots[I], 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Gowin', 'UninstallString', Uninst) then begin
      Dir := ExtractFileDir(RemoveQuotes(Uninst));
      if not RegQueryStringValue(Roots[I], 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Gowin', 'DisplayVersion', Ver) then Ver := '';
      Result := True;
    end;
end;

{ Версия Gowin EDA: в программах IDE её нет - берётся из имени каталога (Gowin_V1.9.11.03_Education_x64),
  иначе из записи установщика Gowin в списке программ; '' - неизвестна }
function GowinVerOf(Ide: String): String;
var
  P, I: Integer;
  S, Dir: String;
begin
  Result := '';
  P := Pos('gowin_v', Lowercase(Ide));
  if P > 0 then begin
    S := Copy(Ide, P + 7, 32);
    I := 1;
    while (I <= Length(S)) and (((S[I] >= '0') and (S[I] <= '9')) or (S[I] = '.')) do I := I + 1;
    Result := Copy(S, 1, I - 1);
  end
  else if GowinUninstEntry(Dir, S) and (Pos(Lowercase(Dir) + '\', Lowercase(Ide) + '\') = 1) then begin
    if (S <> '') and (S[1] = 'V') then Delete(S, 1, 1);
    P := Pos(' ', S + ' ');
    Result := Copy(S, 1, P - 1);
  end;
end;

{ Из найденных Gowin EDA остаётся самый новый }
procedure ConsiderGowin(Ide: String; var Best, BestVer: String);
var
  V: String;
begin
  if not FileExists(Ide + '\bin\gw_sh.exe') then exit;
  V := GowinVerOf(Ide);
  if (Best = '') or (CompareVer(V, BestVer) > 0) then begin
    Best := Ide;
    BestVer := V;
  end;
end;

{ Base\IDE, Base\*\IDE и Base\*\*\IDE: установщик Gowin добавляет к выбранному каталогу свою папку
  Gowin_V<версия>_Education_x64, так что при /D=...\Gowin_V... IDE оказывается на два уровня глубже }
procedure ConsiderGowinIn(Base: String; Depth: Integer; var Best, BestVer: String);
var
  FR: TFindRec;
begin
  ConsiderGowin(Base + '\IDE', Best, BestVer);
  if (Depth > 0) and FindFirst(Base + '\*', FR) then
    try
      repeat
        if (FR.Attributes and FILE_ATTRIBUTE_DIRECTORY <> 0) and (FR.Name <> '.') and (FR.Name <> '..')
           and (CompareText(FR.Name, 'IDE') <> 0) and (CompareText(FR.Name, 'Programmer') <> 0) then
          ConsiderGowinIn(Base + '\' + FR.Name, Depth - 1, Best, BestVer);
      until not FindNext(FR);
    finally
      FindClose(FR);
    end;
end;

{ Каталог IDE самого нового Gowin EDA: GOWIN_HOME, запись установщика Gowin, каталог установки
  и те же места, что у sw/socgen/socgen.py }
procedure DetectGowin(App: String; var Ide, Ver: String);
var
  Dir, V: String;
begin
  Ide := '';
  Ver := '';
  ConsiderGowin(GetEnv('GOWIN_HOME'), Ide, Ver);
  if GowinUninstEntry(Dir, V) then ConsiderGowin(Dir + '\IDE', Ide, Ver);
  ConsiderGowinIn(App + '\Gowin', 2, Ide, Ver);
  ConsiderGowinIn(ExpandConstant('{commonpf64}\Gowin'), 2, Ide, Ver);
  ConsiderGowinIn('C:\Gowin', 2, Ide, Ver);
  ConsiderGowinIn('D:\Gowin', 2, Ide, Ver);
end;

{ Gowin EDA старше {#GowinVer} не годится: в gw_sh 1.9.9.03 нет команд проекта (open_project), сборка
  конфигуратора падает. Такой считается не установленным - окно предложит поставить новый.
  Версия неизвестна (каталог без номера) - принимается как есть }
procedure SetGowinFound(App: String);
var
  I: Integer;
  Ide, Ver: String;
begin
  I := ToolIndex('gowin');
  DetectGowin(App, Ide, Ver);
  ToolFound[I] := Ide;
  ToolOld[I] := '';
  ToolOldPath[I] := '';
  if (Ide <> '') and (Ver <> '') and (CompareVer(Ver, '{#GowinVer}') < 0) then begin
    ToolFound[I] := '';
    ToolOld[I] := Ver;
    ToolOldPath[I] := Ide;
  end;
end;

function DetectPy: String;
begin
  Result := FileSearch('py.exe', GetEnv('PATH'));
  if Result = '' then Result := DirWith(ExpandConstant('{win}'), '\py.exe');
  if Result = '' then Result := DirWith(ExpandConstant('{localappdata}\Programs\Python\Launcher'), '\py.exe');
  if Result = '' then Result := DirWith(ExpandConstant('{localappdata}\Microsoft\WindowsApps'), '\py.exe');
  if (Result <> '') and FileExists(Result) then Result := ExtractFileDir(Result);
end;

{ Где уже стоит каждый инструмент: сначала в каталоге установки (та же версия), затем в местах из sdk/SETUP.md }
procedure DetectTools(App: String);
var
  Tc, S: String;
begin
  App := RemoveBackslashUnlessRoot(App);
  Tc := ExpandConstant('{commonpf64}\Eclipse\riscv-toolchain');

  S := '';
  if DirExists(App + '\eclipse\plugins\{#EclipseProduct}') and Present(App + '\eclipse\plugins\{#GwsocPlugin}')
     and Present(App + '\eclipse\plugins\{#RectguiPlugin}') then S := App + '\eclipse';
  ToolFound[ToolIndex('eclipse')] := S;

  S := DirWith(App + '\riscv-toolchain\{#GccDir}\bin', '\riscv-none-elf-gcc.exe');
  if S = '' then begin
    S := FindDirGlob(Tc, 'xpack-riscv-none-elf-gcc-*', '\bin\riscv-none-elf-gcc.exe');
    if S <> '' then S := S + '\bin';
  end;
  ToolFound[ToolIndex('gcc')] := S;

  S := DirWith(App + '\riscv-toolchain\{#BuildToolsDir}\bin', '\make.exe');
  if S = '' then begin
    S := FindDirGlob(Tc, 'xpack-windows-build-tools-*', '\bin\make.exe');
    if S <> '' then S := S + '\bin';
  end;
  ToolFound[ToolIndex('buildtools')] := S;

  S := DirWith(App + '\riscv-toolchain\{#OpenOcdDir}\bin', '\openocd.exe');
  if (S = '') and FileExists(GetEnv('OPENOCD')) then S := ExtractFileDir(GetEnv('OPENOCD'));
  if S = '' then begin
    S := FindDirGlob(Tc, 'xpack-openocd-*', '\bin\openocd.exe');
    if S <> '' then S := S + '\bin';
  end;
  ToolFound[ToolIndex('openocd')] := S;

  { Исправленный openFPGALoader есть только у этого установщика }
  ToolFound[ToolIndex('openfpgaloader')] := DirWith(App + '\openfpgaloader\bin', '\openFPGALoader.exe');

  S := DirWith(App + '\oss-cad-suite', '\bin\yosys.exe');
  if S = '' then S := DirWith(GetEnv('OSS_CAD_SUITE'), '\bin\yosys.exe');
  if S = '' then S := DirWith('C:\oss-cad-suite', '\bin\yosys.exe');
  ToolFound[ToolIndex('oss')] := S;

  S := DirWith(App + '\iverilog\bin', '\iverilog.exe');
  if S = '' then S := DirWith('C:\iverilog\bin', '\iverilog.exe');
  if S = '' then begin
    S := FileSearch('iverilog.exe', GetEnv('PATH'));
    if S <> '' then S := ExtractFileDir(S);
  end;
  if (S <> '') and not FileExists(S + '\gtkwave.exe') then S := '';     { нужен и GTKWave }
  ToolFound[ToolIndex('iverilog')] := S;

  ToolFound[ToolIndex('zadig')] := DirWith(App + '\zadig', '\{#ZadigExe}');
  ToolFound[ToolIndex('python')] := DetectPy;
  SetGowinFound(App);
  ToolFound[ToolIndex('github')] := DirWith(ExpandConstant('{localappdata}\GitHubDesktop'), '\GitHubDesktop.exe');
  DetectedDir := App;
end;

{ Без окна (тихая установка): ставится то, чего нет; /TOOLS=id,id,... - ставить именно эти (и заново) }
procedure DefaultSelection;
var
  I: Integer;
  List: String;
begin
  List := ',' + Lowercase(ExpandConstant('{param:TOOLS|}')) + ',';
  for I := 0 to GetArrayLength(ToolId) - 1 do
    if List <> ',,' then
      ToolInstall[I] := (Pos(',' + ToolId[I] + ',', List) > 0) or (ToolRequired[I] and (ToolFound[I] = ''))
    else
      ToolInstall[I] := ToolFound[I] = '';
end;

{ ---------- окно выбора инструментов ---------- }

{ Ставится отмеченное и доступное (серые галочки - уже установленное) и обязательное, которого нет }
function WillInstall(I: Integer): Boolean;
begin
  Result := ToolsList.Checked[I] and ToolsList.ItemEnabled[I] or ToolRequired[I] and (ToolFound[I] = '');
end;

function SelectedMB: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to GetArrayLength(ToolId) - 1 do
    if WillInstall(I) then Result := Result + ToolMB[I];
end;

{ Свободно на диске каталога установки, МБ (-1 - не удалось узнать) }
function FreeMB: Integer;
var
  Free, Total: Int64;
begin
  if GetSpaceOnDisk64(ExtractFileDrive(DetectedDir) + '\', Free, Total) then
    Result := Free div (1024 * 1024)
  else
    Result := -1;
end;

function GB(MB: Integer): String;
begin
  if MB < 1024 then
    Result := IntToStr(MB) + ' МБ'
  else
    Result := IntToStr(MB div 1024) + ',' + IntToStr((MB mod 1024) * 10 div 1024) + ' ГБ';
end;

{ Стандартная строка Inno о месте на диске не видит инструменты из этого окна - считаем сами }
procedure UpdateSpace;
var
  Need, Free: Integer;
begin
  Need := SelectedMB;
  Free := FreeMB;
  SpaceLabel.Caption := 'Потребуется около ' + GB(Need) + ' на диске ' + ExtractFileDrive(DetectedDir);
  if Free >= 0 then SpaceLabel.Caption := SpaceLabel.Caption + ', свободно ' + GB(Free);
  if (Free >= 0) and (Need > Free) then SpaceLabel.Font.Color := clRed else SpaceLabel.Font.Color := clWindowText;
end;

procedure FillToolsList;
var
  I: Integer;
  Found: Boolean;
  Sub: String;
begin
  ToolsList.Items.Clear;
  for I := 0 to GetArrayLength(ToolId) - 1 do begin
    Found := ToolFound[I] <> '';
    if Found then
      { Установленное: серая галочка, не ставится; с «Установить заново» - доступно, по умолчанию снято }
      ToolsList.AddCheckBox(ToolName[I], '✓ установлено', 0, not ReinstallBox.Checked, ReinstallBox.Checked, False, False, nil)
    else begin
      Sub := ToolSize[I];
      if ToolRequired[I] then Sub := Sub + ', обязательно';
      if ToolOld[I] <> '' then Sub := 'устарел V' + ToolOld[I] + ', ' + Sub;
      ToolsList.AddCheckBox(ToolName[I], Sub, 0, True, not ToolRequired[I], False, False, nil);
    end;
  end;
  HintLabel.Caption := 'Выделите строку, чтобы увидеть, где найден инструмент.';
  UpdateSpace;
end;

procedure ToolsListClickCheck(Sender: TObject);
begin
  UpdateSpace;
end;

procedure ToolsListClick(Sender: TObject);
var
  I: Integer;
begin
  I := ToolsList.ItemIndex;
  if I < 0 then exit;
  if ToolFound[I] <> '' then
    HintLabel.Caption := 'Установлено: ' + ToolFound[I]
  else if ToolOld[I] <> '' then
    HintLabel.Caption := 'Устарел V' + ToolOld[I] + ': ' + ToolOldPath[I]
  else
    HintLabel.Caption := 'Не найдено - будет установлено в ' + DetectedDir;
end;

procedure ReinstallClick(Sender: TObject);
begin
  FillToolsList;
end;

procedure InitializeWizard;
begin
  ToolsPage := CreateCustomPage(wpSelectDir, 'Выбор инструментов',
    'Отметьте, что установить. Уже установленные инструменты отмечены серой галочкой и не ставятся заново.');
  ToolsList := TNewCheckListBox.Create(ToolsPage);
  ToolsList.Parent := ToolsPage.Surface;
  ToolsList.Left := 0;
  ToolsList.Top := 0;
  ToolsList.Width := ToolsPage.SurfaceWidth;
  ToolsList.Height := ToolsPage.SurfaceHeight - ScaleY(74);
  ToolsList.Anchors := [akLeft, akTop, akRight, akBottom];
  ToolsList.OnClick := @ToolsListClick;
  ToolsList.OnClickCheck := @ToolsListClickCheck;

  ReinstallBox := TNewCheckBox.Create(ToolsPage);
  ReinstallBox.Parent := ToolsPage.Surface;
  ReinstallBox.Left := 0;
  ReinstallBox.Top := ToolsList.Top + ToolsList.Height + ScaleY(8);
  ReinstallBox.Width := ToolsPage.SurfaceWidth;
  ReinstallBox.Anchors := [akLeft, akRight, akBottom];
  ReinstallBox.Caption := 'Разрешить установить заново уже установленные (их можно будет отметить в списке)';
  ReinstallBox.OnClick := @ReinstallClick;

  HintLabel := TNewStaticText.Create(ToolsPage);
  HintLabel.Parent := ToolsPage.Surface;
  HintLabel.Left := 0;
  HintLabel.Top := ReinstallBox.Top + ReinstallBox.Height + ScaleY(6);
  HintLabel.Width := ToolsPage.SurfaceWidth;
  HintLabel.Anchors := [akLeft, akRight, akBottom];
  HintLabel.AutoSize := False;
  HintLabel.Height := ScaleY(16);

  SpaceLabel := TNewStaticText.Create(ToolsPage);
  SpaceLabel.Parent := ToolsPage.Surface;
  SpaceLabel.Left := 0;
  SpaceLabel.Top := HintLabel.Top + HintLabel.Height + ScaleY(4);
  SpaceLabel.Width := ToolsPage.SurfaceWidth;
  SpaceLabel.Anchors := [akLeft, akRight, akBottom];
  SpaceLabel.AutoSize := False;
  SpaceLabel.Height := ScaleY(16);

  { «Требуется как минимум ...» на странице папки считает только файлы Inno без учёта выбора - скрыта }
  WizardForm.DiskSpaceLabel.Visible := False;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  { Каталог могли сменить - поиск заново; иначе выбор пользователя сохраняется }
  if (CurPageID = ToolsPage.ID) and (CompareText(RemoveBackslashUnlessRoot(WizardDirValue), DetectedDir) <> 0) then begin
    DetectTools(WizardDirValue);
    FillToolsList;
  end;
end;

{ ---------- переменные среды ---------- }

function EnvRoot: Integer;
begin
  if IsAdminInstallMode then Result := HKLM else Result := HKCU;
end;

function EnvKey: String;
begin
  if IsAdminInstallMode then Result := '{#EnvKeyMachine}' else Result := '{#EnvKeyUser}';
end;

{ Записанное значение запоминается: при удалении переменная убирается, только если его не меняли }
procedure SetEnv(Name, Value: String);
begin
  if not RegWriteStringValue(EnvRoot, EnvKey, Name, Value) then
    Log('Не удалось записать переменную ' + Name);
  RegWriteStringValue(EnvRoot, '{#StateKey}', 'Env_' + Name, Value);
end;

procedure UnsetEnv(Name: String);
var
  Cur, Mine: String;
begin
  if RegQueryStringValue(EnvRoot, '{#StateKey}', 'Env_' + Name, Mine)
     and RegQueryStringValue(EnvRoot, EnvKey, Name, Cur) and (CompareText(Cur, Mine) = 0) then
    RegDeleteValue(EnvRoot, EnvKey, Name);
end;

function PathHas(PathVal, Dir: String): Boolean;
begin
  Result := Pos(';' + Lowercase(RemoveBackslashUnlessRoot(Dir)) + ';', ';' + Lowercase(PathVal) + ';') > 0;
end;

{ Каталоги добавляются в конец PATH; что добавлено - запоминается для удаления }
procedure AddToPath(Dirs: TArrayOfString);
var
  PathVal, Added: String;
  I: Integer;
begin
  if not RegQueryStringValue(EnvRoot, EnvKey, 'Path', PathVal) then PathVal := '';
  RegQueryStringValue(EnvRoot, '{#StateKey}', 'AddedPath', Added);
  for I := 0 to GetArrayLength(Dirs) - 1 do
    if (Dirs[I] <> '') and not PathHas(PathVal, Dirs[I]) then begin
      if (PathVal <> '') and (PathVal[Length(PathVal)] <> ';') then PathVal := PathVal + ';';
      PathVal := PathVal + Dirs[I];
      Added := Added + Dirs[I] + ';';
    end;
  RegWriteExpandStringValue(EnvRoot, EnvKey, 'Path', PathVal);
  RegWriteStringValue(EnvRoot, '{#StateKey}', 'AddedPath', Added);
end;

procedure RemoveAddedPath;
var
  PathVal, Added, NewPath, Item: String;
  P: Integer;
begin
  if not RegQueryStringValue(EnvRoot, '{#StateKey}', 'AddedPath', Added) then exit;
  if not RegQueryStringValue(EnvRoot, EnvKey, 'Path', PathVal) then exit;
  NewPath := '';
  PathVal := PathVal + ';';
  while PathVal <> '' do begin
    P := Pos(';', PathVal);
    Item := Copy(PathVal, 1, P - 1);
    Delete(PathVal, 1, P);
    if (Item <> '') and (Pos(';' + Lowercase(Item) + ';', ';' + Lowercase(Added)) = 0) then begin
      if NewPath <> '' then NewPath := NewPath + ';';
      NewPath := NewPath + Item;
    end;
  end;
  RegWriteExpandStringValue(EnvRoot, EnvKey, 'Path', NewPath);
end;

{ ---------- настройки Eclipse ---------- }

{ Значение для .prefs (java.util.Properties): \ и : экранируются, не-ASCII - \uXXXX }
function PropValue(S: String): String;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(S) do begin
    C := S[I];
    if C = '\' then Result := Result + '\\'
    else if C = ':' then Result := Result + '\:'
    else if Ord(C) > 127 then Result := Result + Format('\u%.4x', [Ord(C)])
    else Result := Result + C;
  end;
end;

procedure WritePrefs(FileName, Key1, Value1, Key2, Value2: String);
var
  Dir: String;
  Lines: TArrayOfString;
begin
  Push(Lines, 'eclipse.preferences.version=1');
  Push(Lines, Key1 + '=' + PropValue(Value1));
  if Key2 <> '' then Push(Lines, Key2 + '=' + PropValue(Value2));
  Dir := ExpandConstant('{app}\eclipse\configuration\.settings');
  ForceDirectories(Dir);
  if not SaveStringsToFile(Dir + '\' + FileName, Lines, False) then
    Log('Не удалось записать ' + FileName);
end;

{ Пути MCU «Global» (Window > Preferences > MCU) хранятся в configuration/.settings пакета Eclipse
  и действуют для любого рабочего пространства. Инструменты, найденные в другом месте, берутся оттуда.
  Рабочее пространство по умолчанию - папка workspace в каталоге установки }
procedure ConfigureEclipse;
var
  Lines: TArrayOfString;
  Ini, Ws: String;
  I: Integer;
begin
  if ToolHas('buildtools') then
    WritePrefs('org.eclipse.embedcdt.managedbuild.cross.core.prefs', 'buildTools.path', ToolPath('buildtools'), '', '');
  { 2273142913 - номер набора «xPack GNU RISC-V Embedded GCC» в Embedded CDT }
  if ToolHas('gcc') then
    WritePrefs('org.eclipse.embedcdt.managedbuild.cross.riscv.core.prefs',
      'toolchain.id', '2273142913', 'toolchain.path.2273142913', ToolPath('gcc'));
  if ToolHas('openocd') then
    WritePrefs('org.eclipse.embedcdt.debug.gdbjtag.openocd.core.prefs',
      'executable.name', 'openocd.exe', 'install.folder', ToolPath('openocd'));

  Ini := ExpandConstant('{app}\eclipse\eclipse.ini');
  Ws := ExpandConstant('{app}\workspace');
  StringChangeEx(Ws, '\', '/', True);
  if LoadStringsFromFile(Ini, Lines) then begin
    for I := 0 to GetArrayLength(Lines) - 1 do
      if Pos('-Dosgi.instance.area.default=', Lines[I]) = 1 then
        Lines[I] := '-Dosgi.instance.area.default=' + Ws;
    SaveStringsToUTF8FileWithoutBOM(Ini, Lines, False);
  end;
end;

{ ---------- сторонние установщики ---------- }

procedure Status(S: String);
begin
  WizardForm.StatusLabel.Caption := S;
  WizardForm.FilenameLabel.Caption := '';
  Log(S);
end;

procedure RunPython;
var
  Code: Integer;
  Params: String;
begin
  Status('Установка Python {#PythonVer}...');
  if IsAdminInstallMode then
    Params := '/quiet InstallAllUsers=1 InstallLauncherAllUsers=1'
  else
    Params := '/quiet InstallAllUsers=0 InstallLauncherAllUsers=0';
  Params := Params + ' PrependPath=1 Include_launcher=1 Include_test=0';
  if not Exec(ExpandConstant('{tmp}\{#PythonExe}'), Params, '', SW_SHOW, ewWaitUntilTerminated, Code) or (Code <> 0) then
    SuppressibleMsgBox('Python не установлен (код ' + IntToStr(Code) + '). Установите его вручную: python.org или sdk/SETUP.md, п. 2.',
      mbError, MB_OK, IDOK);
end;

procedure RunGowin;
var
  Code: Integer;
begin
  Status('Установка Gowin EDA - продолжите в окне установщика Gowin...');
  { NSIS: /D= - каталог по умолчанию, последним параметром и без кавычек. Установщик Gowin сам добавляет
    к нему папку Gowin_V<версия>_Education_x64 (по её имени узнаётся версия): IDE - <app>\Gowin\Gowin_V...\IDE }
  if not ShellExec('', ExpandConstant('{tmp}\{#GowinExe}'),
                   '/D=' + ExpandConstant('{app}\Gowin'), '',
                   SW_SHOW, ewWaitUntilTerminated, Code) then
    SuppressibleMsgBox('Не удалось запустить установщик Gowin EDA: ' + SysErrorMessage(Code), mbError, MB_OK, IDOK);
  { Где Gowin оказался на самом деле (каталог могли сменить в его окне); старый остаётся, но GOWIN_HOME - на новый }
  SetGowinFound(ExpandConstant('{app}'));
  ToolInstall[ToolIndex('gowin')] := False;
  if ToolFound[ToolIndex('gowin')] = '' then
    SuppressibleMsgBox('Gowin EDA {#GowinVer} не найден после установки. Укажите каталог IDE в переменной GOWIN_HOME (sdk/SETUP.md, п. 4).',
      mbError, MB_OK, IDOK);
end;

procedure RunGitHub;
var
  Code: Integer;
begin
  Status('Установка GitHub Desktop...');
  { Программа ставится в профиль пользователя - от имени того, кто запустил установку }
  if not ExecAsOriginalUser(ExpandConstant('{tmp}\{#GitHubExe}'), '--silent', '', SW_SHOW, ewWaitUntilTerminated, Code) then
    SuppressibleMsgBox('Не удалось запустить установщик GitHub Desktop: ' + SysErrorMessage(Code), mbError, MB_OK, IDOK);
end;

{ ---------- шаги установки ---------- }

function InitializeSetup: Boolean;
begin
  AddTool('eclipse', 'Eclipse IDE for Embedded C/C++ {#EclipseVer} + плагины askoRV32', '{#SizeEclipse} МБ', {#SizeEclipse}, False);
  AddTool('gcc', 'xPack RISC-V GCC ({#GccDir})', '{#SizeGcc} МБ', {#SizeGcc}, True);
  AddTool('buildtools', 'xPack Windows Build Tools: make, rm ({#BuildToolsDir})', '{#SizeBuildTools} МБ', {#SizeBuildTools}, True);
  AddTool('openocd', 'xPack OpenOCD - отладка через JTAG ({#OpenOcdDir})', '{#SizeOpenOcd} МБ', {#SizeOpenOcd}, False);
  AddTool('openfpgaloader', 'openFPGALoader с исправлениями askoRV32 - загрузка ПЛИС', '{#SizeLoader} МБ', {#SizeLoader}, False);
  AddTool('oss', 'OSS CAD Suite {#OssDate}: Yosys, nextpnr, apicula', '{#SizeOss} МБ', {#SizeOss}, False);
  AddTool('iverilog', 'Icarus Verilog + GTKWave - симуляция', '{#SizeIverilog} МБ', {#SizeIverilog}, False);
  AddTool('zadig', 'Zadig - драйвер WinUSB для JTAG платы', '{#SizeZadig} МБ', {#SizeZadig}, False);
  { Сторонние программы: копия установщика во временном каталоге + примерный размер установленной программы
    (Python ~110 МБ, Gowin EDA ~1,5 ГБ - sdk/SETUP.md п. 4.1, GitHub Desktop ~450 МБ) }
  AddTool('python', 'Python {#PythonVer} с командой py', '~110 МБ', {#SizePython} + 110, False);
  AddTool('gowin', 'Gowin EDA Education {#GowinVer} (своё окно установки)', '~1,5 ГБ', {#SizeGowin} + 1536, False);
  AddTool('github', 'GitHub Desktop', '~450 МБ', {#SizeGitHub} + 450, False);
  Result := True;
end;

{ Файлы пишутся без длинных путей (MAX_PATH): самый длинный путь в пакете - {#LongestRel} символов от каталога }
function DirTooLong(Dir: String): String;
begin
  Result := '';
  if Length(AddBackslash(Dir)) + {#LongestRel} > 259 then
    Result := 'Слишком длинный путь к каталогу установки (' + IntToStr(Length(Dir)) + ' символов, можно не более ' +
      IntToStr(259 - {#LongestRel} - 1) + '): часть файлов Eclipse не поместится в ограничение Windows на длину пути. ' +
      'Выберите каталог короче, например C:\riscv-sdk.';
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  I, Need: Integer;
begin
  Result := DirTooLong(WizardDirValue);
  if (Result = '') and WizardSilent then begin
    DetectTools(WizardDirValue);
    DefaultSelection;
    Need := 0;
    for I := 0 to GetArrayLength(ToolId) - 1 do
      if ToolInstall[I] then Need := Need + ToolMB[I];
    if (FreeMB >= 0) and (Need > FreeMB) then
      Result := 'Не хватает места на диске ' + ExtractFileDrive(DetectedDir) + ': нужно около ' + GB(Need) + ', свободно ' + GB(FreeMB) + '.';
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  Dir: String;
  I: Integer;
  Bad: Boolean;
begin
  Result := True;
  if CurPageID = wpSelectDir then begin
    Dir := WizardDirValue;
    if DirTooLong(Dir) <> '' then begin
      SuppressibleMsgBox(DirTooLong(Dir), mbError, MB_OK, IDOK);
      Result := False;
      exit;
    end;
    Bad := Pos(' ', Dir) > 0;
    for I := 1 to Length(Dir) do
      if Ord(Dir[I]) > 127 then Bad := True;
    if Bad then
      Result := SuppressibleMsgBox('В пути есть пробелы или кириллица:' + #13#10 + Dir + #13#10#13#10 +
        'Сборка и отладка в Eclipse с таким путём могут не работать (sdk/SETUP.md). Всё равно продолжить?',
        mbConfirmation, MB_YESNO or MB_DEFBUTTON2, IDYES) = IDYES;
  end
  else if CurPageID = ToolsPage.ID then begin
    if (FreeMB >= 0) and (SelectedMB > FreeMB) then begin
      SuppressibleMsgBox('Не хватает места на диске ' + ExtractFileDrive(DetectedDir) + ': нужно около ' + GB(SelectedMB) +
        ', свободно ' + GB(FreeMB) + '. Снимите часть инструментов или выберите другой диск.', mbError, MB_OK, IDOK);
      Result := False;
      exit;
    end;
    for I := 0 to GetArrayLength(ToolId) - 1 do
      ToolInstall[I] := WillInstall(I);
  end;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo,
  MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
var
  I: Integer;
  Inst, Have: String;
begin
  for I := 0 to GetArrayLength(ToolId) - 1 do
    if ToolInstall[I] then Inst := Inst + Space + ToolName[I] + NewLine
    else if ToolFound[I] <> '' then Have := Have + Space + ToolName[I] + ' - ' + ToolFound[I] + NewLine;
  if Inst = '' then Inst := Space + 'ничего (только переменные среды и настройки Eclipse)' + NewLine;
  Result := MemoDirInfo + NewLine + NewLine + 'Будет установлено:' + NewLine + Inst;
  if Have <> '' then Result := Result + NewLine + 'Уже установлено (не меняется):' + NewLine + Have;
  if MemoTasksInfo <> '' then Result := Result + NewLine + MemoTasksInfo;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  App: String;
  Dirs: TArrayOfString;
begin
  if CurStep <> ssPostInstall then exit;
  App := ExpandConstant('{app}');
  if ToolInst('python') then RunPython;
  if ToolInst('gowin') then RunGowin;
  if ToolInst('github') then RunGitHub;
  if ToolHas('eclipse') then begin
    Status('Настройка Eclipse...');
    ConfigureEclipse;
  end;

  Status('Переменные среды...');
  RegWriteStringValue(EnvRoot, '{#StateKey}', 'InstallDir', App);
  SetEnv('ASKORV32_SDK', App);
  if ToolHas('openocd') then SetEnv('OPENOCD', ToolPath('openocd') + '\openocd.exe');
  { OSS CAD Suite в PATH не добавляется: в нём свой Python и DLL. Скрипты берут его из OSS_CAD_SUITE }
  if ToolHas('oss') then SetEnv('OSS_CAD_SUITE', ToolPath('oss'));
  if ToolHas('gowin') then SetEnv('GOWIN_HOME', ToolPath('gowin'));
  Push(Dirs, ToolPath('gcc'));
  Push(Dirs, ToolPath('buildtools'));
  Push(Dirs, ToolPath('openocd'));
  Push(Dirs, ToolPath('openfpgaloader'));
  Push(Dirs, ToolPath('iverilog'));
  AddToPath(Dirs);
end;

{ Переменные убираются после удаления файлов. GOWIN_HOME остаётся, пока стоит сам Gowin EDA (у него свой деинсталлятор) }
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Gowin: String;
begin
  if CurUninstallStep <> usPostUninstall then exit;
  RemoveAddedPath;
  UnsetEnv('ASKORV32_SDK');
  UnsetEnv('OPENOCD');
  UnsetEnv('OSS_CAD_SUITE');
  if not (RegQueryStringValue(EnvRoot, '{#StateKey}', 'Env_GOWIN_HOME', Gowin) and FileExists(Gowin + '\bin\gw_sh.exe')) then
    UnsetEnv('GOWIN_HOME');
  RegDeleteKeyIncludingSubkeys(EnvRoot, '{#StateKey}');
  RegDeleteKeyIfEmpty(EnvRoot, 'Software\askoRV32');
end;
