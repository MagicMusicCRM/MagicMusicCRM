[Setup]
AppName=MagicMusic CRM
AppVersion=1.1.0
DefaultDirName={autopf}\MagicMusicCRM
DefaultGroupName=MagicMusicCRM
; Изменили на простую папку в корне проекта
OutputDir=installer_output
OutputBaseFilename=MagicMusicCRM_Setup
Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
; Иконка приложения (путь от корня проекта)
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\magic_music_crm.exe

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Основной экзешник (подтвержденный путь)
Source: "build\windows\x64\runner\Release\magic_music_crm.exe"; DestDir: "{app}"; Flags: ignoreversion
; Все DLL библиотеки
Source: "build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion
; Папка данных (Asset-ы и шейдеры)
Source: "build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\MagicMusic CRM"; Filename: "{app}\magic_music_crm.exe"
Name: "{autodesktop}\MagicMusic CRM"; Filename: "{app}\magic_music_crm.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\magic_music_crm.exe"; Description: "{cm:LaunchProgram,MagicMusic CRM}"; Flags: nowait postinstall skipifsilent
