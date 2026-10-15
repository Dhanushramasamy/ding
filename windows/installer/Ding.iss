; Inno Setup script for Ding. Built by .github/workflows/windows.yml:
;   ISCC.exe /DAppVersion=1.0.0 windows\installer\Ding.iss
; Installs per user (no administrator prompt) into %LocalAppData%\Programs\Ding.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{8F0D6B0E-5C2A-4D8B-9E3F-3A1D2C4B5E6F}
AppName=Ding
AppVersion={#AppVersion}
AppVerName=Ding {#AppVersion}
AppPublisher=Dhanush Ramasamy
AppCopyright=© 2026 Dhanush Ramasamy
VersionInfoVersion={#AppVersion}
VersionInfoDescription=Ding installer
DefaultDirName={autopf}\Ding
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
DisableDirPage=yes
OutputDir=Output
OutputBaseFilename=Ding-Setup-{#AppVersion}
SetupIconFile=..\Assets\Ding.ico
UninstallDisplayIcon={app}\Ding.exe
UninstallDisplayName=Ding
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
MinVersion=10.0.17763

[Tasks]
Name: "startup"; Description: "Start Ding when I sign in to Windows"; GroupDescription: "Options:"
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Options:"; Flags: unchecked

[Files]
Source: "..\publish\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Ding"; Filename: "{app}\Ding.exe"
Name: "{autodesktop}\Ding"; Filename: "{app}\Ding.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Ding"; \
  ValueData: """{app}\Ding.exe"""; Tasks: startup; Flags: uninsdeletevalue

[Run]
Filename: "{app}\Ding.exe"; Description: "Open Ding now"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Quit Ding before its files are removed.
Filename: "{cmd}"; Parameters: "/C taskkill /IM Ding.exe /F"; Flags: runhidden; RunOnceId: "QuitDing"
