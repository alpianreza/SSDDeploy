; BootDeploy 2.0.0 — Inno Setup installer script
; Build: buka file ini dengan Inno Setup 6, lalu Compile (Ctrl+F9).
; Hasil: BootDeploy-2.0.0-Setup.exe

#define MyAppName "BootDeploy"
#define MyAppVersion "2.0.0"
#define MyAppPublisher "REZA"
#define MyAppURL "https://github.com/alpianreza/SSDDeploy"

[Setup]
AppId={{82af3e3a-23a5-446c-b096-c9be05def13a}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=.\
OutputBaseFilename=BootDeploy-{#MyAppVersion}-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
UninstallDisplayName={#MyAppName} {#MyAppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "..\BootDeploy.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\START-BootDeploy.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion isreadme

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\START-BootDeploy.cmd"; Comment: "Jalankan BootDeploy sebagai Administrator"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\START-BootDeploy.cmd"; Comment: "Jalankan BootDeploy sebagai Administrator"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Buat shortcut di Desktop"; GroupDescription: "Shortcut tambahan:"

[Run]
Filename: "{app}\START-BootDeploy.cmd"; Description: "Jalankan {#MyAppName} sekarang"; Flags: nowait postinstall shellexec skipifsilent
