#define MyAppName "Compton's 3D World Atlas Deluxe - Windows 11 Compatibility"
#define MyAppVersion "1.1.0"
#define MyAppPublisher "Trevor Menagh"
#define MyAppURL "https://github.com/trevmex/Comptons-3D-World-Atlas-Windows11"

[Setup]
AppId={{4A58D51A-1C83-4F56-9E07-3D7E6C8F1F11}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={localappdata}\Comptons 3D World Atlas Deluxe Toolkit
DisableProgramGroupPage=yes
DisableReadyPage=no
PrivilegesRequired=lowest
Uninstallable=yes
UninstallDisplayName={#MyAppName}
OutputDir=..\dist
OutputBaseFilename=Comptons-3D-World-Atlas-Windows11-Setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=no
ArchitecturesAllowed=x86 x64

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\NOTICE.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\CONTRIBUTING.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\scripts\*"; DestDir: "{app}\scripts"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\src\*"; DestDir: "{app}\src"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\archive\*"; DestDir: "{app}\archive"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\docs\*"; DestDir: "{app}\docs"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\build\Wlbrw32.dll"; DestDir: "{app}\build"; Flags: ignoreversion
Source: "..\build\Wlbrw32.dll.sha256"; DestDir: "{app}\build"; Flags: ignoreversion

[Code]
var
  DiscDrive: string;

function IsAtlasDisc(const Drive: string): Boolean;
begin
  Result := FileExists(Drive + '\ATLAS.EXE') and FileExists(Drive + '\WLBRW32.DLL');
end;

function FindAtlasDisc: string;
var
  Index: Integer;
  Candidate: string;
begin
  Result := '';
  for Index := Ord('A') to Ord('Z') do begin
    Candidate := Chr(Index) + ':';
    if IsAtlasDisc(Candidate) then begin
      Result := Candidate;
      exit;
    end;
  end;
end;

function GetDiscDrive: string;
var
  Value: string;
  ExplicitDrive: string;
begin
  ExplicitDrive := ExpandConstant('{param:DISC|}');
  if ExplicitDrive = '' then begin
    if IsAtlasDisc('D:') then
      Result := 'D:'
    else begin
      Value := FindAtlasDisc;
      if Value <> '' then
        Result := Value
      else
        Result := 'D:';
    end;
    exit;
  end;

  Value := ExplicitDrive;
  while (Length(Value) > 0) and ((Value[Length(Value)] = '\') or (Value[Length(Value)] = '/')) do
    Delete(Value, Length(Value), 1);
  if (Length(Value) = 2) and (Value[2] = ':') then
    Result := Value
  else
    Result := 'D:';
end;

function DiscFile(const Name: string): string;
begin
  Result := DiscDrive + '\' + Name;
end;

function InitializeSetup: Boolean;
begin
  DiscDrive := GetDiscDrive;
  Result := FileExists(DiscFile('ATLAS.EXE')) and FileExists(DiscFile('WLBRW32.DLL'));
  if not Result and not WizardSilent then
    MsgBox('The physical Compton''s 3D World Atlas Deluxe CD was not found at ' + DiscDrive + '.' + #13#10 + #13#10 +
      'Insert your lawful 3DATLAS disc and run this installer again. No files are installed without the disc.',
      mbError, MB_OK);
end;

function RunCompatibilityInstall: Boolean;
var
  PowerShell: string;
  Parameters: string;
  ResultCode: Integer;
  AppRoot: string;
  LogPath: string;
begin
  AppRoot := ExpandConstant('{app}');
  LogPath := AppRoot + '\Install-AtlasWindows11.log';
  WizardForm.StatusLabel.Caption := 'Preparing Atlas media and offline Online documentation...';
  WizardForm.ProgressGauge.Style := npbstMarquee;
  PowerShell := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Parameters := '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' +
    AppRoot + '\scripts\Install-AtlasWindows11.ps1" -DiscDrive "' + DiscDrive +
    '" -LogPath "' + LogPath + '"';
  Result := Exec(PowerShell, Parameters, AppRoot, SW_HIDE, ewWaitUntilTerminated, ResultCode);
  WizardForm.ProgressGauge.Style := npbstNormal;
  WizardForm.StatusLabel.Caption := 'Installation complete.';
  if not Result then begin
    MsgBox('Windows PowerShell could not be started.', mbError, MB_OK);
    exit;
  end;
  if ResultCode <> 0 then begin
    MsgBox('The compatibility installation failed with exit code ' + IntToStr(ResultCode) + '.' + #13#10 + #13#10 +
      'Detailed diagnostic output was written to:' + #13#10 + LogPath + #13#10 + #13#10 +
      'The physical disc must remain mounted and the archive endpoint must be reachable.',
      mbError, MB_OK);
    Result := False;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then begin
    if not FileExists(DiscFile('ATLAS.EXE')) then begin
      MsgBox('The physical disc was removed before installation completed.', mbError, MB_OK);
      Abort;
    end;
    if not RunCompatibilityInstall then
      Abort;
  end;
end;
