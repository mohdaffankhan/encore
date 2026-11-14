; Inno Setup script for the Encore Windows installer. Built in CI by
; .github/workflows/build.yml:  iscc /DAppVersion=1.2.3 windows\installer.iss
; Installs per user (no admin prompt).

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{6F1E2A57-3C8B-4E7D-9A41-2B5C0D8E9F13}
AppName=Encore
AppVersion={#AppVersion}
AppPublisher=Encore contributors
DefaultDirName={localappdata}\Programs\Encore
DefaultGroupName=Encore
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\build\installer
OutputBaseFilename=encore-windows-setup
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\encore.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\Encore"; Filename: "{app}\encore.exe"
Name: "{userdesktop}\Encore"; Filename: "{app}\encore.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\encore.exe"; Description: "Launch Encore"; Flags: nowait postinstall skipifsilent
; An update Encore started (its update reminder or Settings): Encore opens
; again once installed. Encore passes /RELAUNCH; 0.3.0 passed only
; /CLOSEAPPLICATIONS (and reopened itself through cmd, which failed).
; Release checks pass neither, so their silent installs open nothing.
Filename: "{app}\encore.exe"; Flags: nowait; Check: UpdatedFromEncore

[Code]
function UpdatedFromEncore: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if (CompareText(ParamStr(I), '/RELAUNCH') = 0) or
       (CompareText(ParamStr(I), '/CLOSEAPPLICATIONS') = 0) then
      Result := True;
end;
