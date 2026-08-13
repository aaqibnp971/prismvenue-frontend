; Prism Venues — Inno Setup script.
;
; Optional. Everything ships and installs fine without this: the ZIP plus
; Install.cmd already gives shortcuts, an Add/Remove Programs entry and
; upgrade-in-place. This exists for when you want ONE double-clickable
; PrismVenuesSetup.exe to hand someone instead of a zip.
;
; Needs Inno Setup 6 (free): https://jrsoftware.org/isdl.php
;
; Build the staged folder first, then compile:
;   powershell -ExecutionPolicy Bypass -File packaging\build_windows_release.ps1
;   & "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" packaging\PrismVenues.iss
;
; Output lands in dist\PrismVenuesSetup.exe

#define MyAppName      "Prism Venues"
#define MyAppVersion   "1.0.0"
#define MyAppPublisher "Prism"
#define MyAppExeName   "prism_venues.exe"

[Setup]
AppId={{7C4F1E92-3B6A-4E71-9D28-5A1C0F8B3E44}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\PrismVenues
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=PrismVenuesSetup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Per-user by default, exactly like Install.ps1: no admin, no UAC. Inno picks
; {localappdata}\Programs for autopf under this mode.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
; The staged bundle from build_windows_release.ps1. Everything under app\ —
; the exe, the Flutter runtime DLLs, data\ (assets and the audio stems) and
; prism_core.dll — goes in flat, preserving subdirectories.
Source: "..\dist\PrismVenues-windows-x64\app\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; data\ is written into at runtime (the engine's extracted stems), so Inno does
; not consider it its own and would otherwise leave the folder behind.
Type: filesandordirs; Name: "{app}\data"
