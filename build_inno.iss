; Inno Setup script for Gabooth Assistant
; Modeled on gabooth_selfphoto/build_inno.iss but trimmed for this project
; (no sentry, no auto-updater, no objectbox, no canon SDK, no ffmpeg).
; - Bundles only the plugins this project actually uses.
; - Downloads Visual C++ runtime DLLs at install time.
; - Adds program-based firewall rules so the print server is reachable.
; - Auto-starts with Windows so the tray server is ready after boot.
; - Cleans %APPDATA%\GaboothAssistant on uninstall (matches logger path).

#define MyAppName "Gabooth Assistant"
#define MyAppVersion "1.2.0"
#define MyAppPublisher "Gabooth"
#define MyAppURL "https://gabooth.com"
#define MyAppExeName "gabooth_assistant.exe"
#define MyAppId "adc171f2-6c7b-4f2c-a0b1-c2e4c8c1ffa9"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=outputs
OutputBaseFilename=GaboothAssistant
SetupIconFile=windows\runner\resources\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
LZMADictionarySize=1048576
LZMANumFastBytes=273
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
WizardImageBackColor=clWhite
Uninstallable=yes
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
AppMutex=Gabooth_Assistant_Installer_Mutex

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked; OnlyBelowVersion: 6.1

[Files]
; Main executable
Source: "build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion

; Flutter engine
Source: "build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion

; Plugin DLLs (matches the plugins this project depends on)
Source: "build\windows\x64\runner\Release\print_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\screen_retriever_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\tray_manager_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\window_manager_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion

; PDF rendering (used by print_windows for the print pipeline)
Source: "build\windows\x64\runner\Release\pdfium.dll"; DestDir: "{app}"; Flags: ignoreversion

; VC++ runtime DLLs are downloaded at install time (see [Code] section below).

; Data folder (Flutter assets, including the tray icon)
Source: "build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: quicklaunchicon

[Run]
; Add firewall exception for the print server (HTTP + UDP discovery rely on this).
Filename: "netsh"; Parameters: "advfirewall firewall add rule name=""{#MyAppName}"" dir=in action=allow program=""{app}\{#MyAppExeName}"" enable=yes"; Flags: runhidden
Filename: "netsh"; Parameters: "advfirewall firewall add rule name=""{#MyAppName}"" dir=out action=allow program=""{app}\{#MyAppExeName}"" enable=yes"; Flags: runhidden
; Launch application after installation
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Logger output dir (services/logger_service.dart writes to %APPDATA%\GaboothAssistant\logs)
Type: filesandordirs; Name: "{userappdata}\GaboothAssistant"
Type: files; Name: "{tmp}\gabooth_assistant_*"

[Code]
var
  DownloadPage: TDownloadWizardPage;
  NeedMsvcp140: Boolean;
  NeedVcruntime140: Boolean;
  NeedVcruntime140_1: Boolean;

procedure CheckRequiredFiles();
var
  AppDir: String;
begin
  AppDir := ExpandConstant('{app}');

  if DirExists(AppDir) then
  begin
    NeedMsvcp140 := not FileExists(AppDir + '\msvcp140.dll');
    NeedVcruntime140 := not FileExists(AppDir + '\vcruntime140.dll');
    NeedVcruntime140_1 := not FileExists(AppDir + '\vcruntime140_1.dll');
  end
  else
  begin
    NeedMsvcp140 := True;
    NeedVcruntime140 := True;
    NeedVcruntime140_1 := True;
  end;
end;

procedure InitializeWizard;
begin
  DownloadPage := CreateDownloadPage(
    'Downloading Required Components',
    'Downloading Visual C++ runtime. Please wait...',
    nil);
  DownloadPage.ShowBaseNameInsteadOfUrl := True;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  if CurPageID = wpReady then
  begin
    CheckRequiredFiles();

    if not NeedMsvcp140 and not NeedVcruntime140 and not NeedVcruntime140_1 then
    begin
      Result := True;
      Exit;
    end;

    DownloadPage.Clear;

    if NeedMsvcp140 then
      DownloadPage.Add(
        'http://bfejlxhltqhzgknonzzo.supabase.co/storage/v1/object/public/dependencies/msvcp140.zip',
        'msvcp140.zip',
        'f1e7d26da18cc39bce3c2f2fd217161444dceef733ed05fe31f3983c233f05e2');

    if NeedVcruntime140 then
      DownloadPage.Add(
        'http://bfejlxhltqhzgknonzzo.supabase.co/storage/v1/object/public/dependencies/vcruntime140.zip',
        'vcruntime140.zip',
        'afe9cd6ebe2989ba96f57fc5bf30ceb1c7877ec859f17d89ed28b5fef27f1220');

    if NeedVcruntime140_1 then
      DownloadPage.Add(
        'http://bfejlxhltqhzgknonzzo.supabase.co/storage/v1/object/public/dependencies/vcruntime140_1.zip',
        'vcruntime140_1.zip',
        'c24cff3bd062550d090f122002082bc9f69409189169eceb6b005e7d7bd3d7f3');

    DownloadPage.Show;
    try
      try
        DownloadPage.Download;
        Result := True;
      except
        SuppressibleMsgBox(AddPeriod(GetExceptionMessage), mbCriticalError, MB_OK, IDOK);
        Result := False;
      end;
    finally
      DownloadPage.Hide;
    end;
  end
  else
    Result := True;
end;

function ExtractSingleDep(ZipName: String; FileName: String): Boolean;
var
  TempZipPath: String;
  ExtractPath: String;
  ResultCode: Integer;
begin
  Result := False;
  TempZipPath := ExpandConstant('{tmp}\' + ZipName);
  ExtractPath := ExpandConstant('{tmp}\dep_' + ZipName);

  if not FileExists(TempZipPath) then
  begin
    Result := True;
    Exit;
  end;

  if not DirExists(ExtractPath) then
    if not CreateDir(ExtractPath) then
      Exit;

  if Exec('powershell.exe',
    '-Command "Expand-Archive -Path ''' + TempZipPath + ''' -DestinationPath ''' + ExtractPath + ''' -Force"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    if ResultCode = 0 then
    begin
      if FileExists(ExtractPath + '\' + FileName) then
      begin
        CopyFile(ExtractPath + '\' + FileName, ExpandConstant('{app}\' + FileName), False);
        Result := True;
      end;
    end;
  end;

  if FileExists(TempZipPath) then
    DeleteFile(TempZipPath);
  if DirExists(ExtractPath) then
    DelTree(ExtractPath, True, True, True);
end;

function ExtractDependencies(): Boolean;
begin
  Result := True;
  if not ExtractSingleDep('msvcp140.zip', 'msvcp140.dll') then
    Result := False;
  if not ExtractSingleDep('vcruntime140.zip', 'vcruntime140.dll') then
    Result := False;
  if not ExtractSingleDep('vcruntime140_1.zip', 'vcruntime140_1.dll') then
    Result := False;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  case CurStep of
    ssPostInstall:
    begin
      if NeedMsvcp140 or NeedVcruntime140 or NeedVcruntime140_1 then
      begin
        if not ExtractDependencies() then
        begin
          MsgBox('Failed to extract required components. Installation cannot continue.',
                 mbError, MB_OK);
          Abort;
        end;
      end;
    end;
  end;
end;

function InitializeUninstall(): Boolean;
var
  ResultCode: Integer;
begin
  Result := True;
  Exec('netsh', 'advfirewall firewall delete rule name="Gabooth Assistant"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

[Registry]
; Auto-start with Windows so the print server / tray icon are ready after boot.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#MyAppName}"; ValueData: """{app}\{#MyAppExeName}"""; Flags: uninsdeletevalue
