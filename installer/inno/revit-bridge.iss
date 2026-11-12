; Revit Bridge Installer
; Conecta Autodesk Revit con Claude AI
; https://github.com/inno-arq/claude-revit-bridge

#define MyAppName "Revit Bridge"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Mallol Arquitectos"
#define MyAppURL "https://github.com/inno-arq/claude-revit-bridge"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={localappdata}\RevitBridge
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\..\dist
OutputBaseFilename=revit-bridge-setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
SetupIconFile=revit-bridge.ico
UninstallDisplayIcon={app}\revit-bridge.ico

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
spanish.WelcomeLabel1=Bienvenido a Revit Bridge
spanish.WelcomeLabel2=Este asistente conectara tu Revit con Claude AI.%n%nSolo necesitas tu email de Claude.
english.WelcomeLabel1=Welcome to Revit Bridge
english.WelcomeLabel2=This wizard will connect your Revit to Claude AI.%n%nYou only need your Claude email.

[Files]
Source: "..\silent-install.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "revit-bridge.ico"; DestDir: "{app}"; Flags: ignoreversion

[Code]
var
  EmailPage: TInputQueryWizardPage;

procedure InitializeWizard;
begin
  EmailPage := CreateInputQueryPage(wpWelcome,
    'Tu email de Claude',
    'Ingresa el email con el que accedes a Claude',
    'Este email se usa para identificar tu equipo automaticamente.');
  EmailPage.Add('Email:', False);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  Email: String;
begin
  Result := True;

  if CurPageID = EmailPage.ID then
  begin
    Email := EmailPage.Values[0];

    if Email = '' then
    begin
      MsgBox('Por favor ingresa tu email de Claude.', mbError, MB_OK);
      Result := False;
      Exit;
    end;

    // Validar formato basico de email
    if (Pos('@', Email) = 0) or (Pos('.', Email) = 0) then
    begin
      MsgBox('El email no parece valido. Verifica e intenta de nuevo.', mbError, MB_OK);
      Result := False;
      Exit;
    end;
  end;
end;

function GetEmail(Param: String): String;
begin
  Result := EmailPage.Values[0];
end;

[Run]
Filename: "powershell.exe"; \
  Parameters: "-ExecutionPolicy Bypass -File ""{app}\silent-install.ps1"" -Email ""{code:GetEmail}"""; \
  StatusMsg: "Instalando Revit Bridge..."; \
  Flags: runhidden waituntilterminated

[UninstallRun]
Filename: "schtasks.exe"; Parameters: "/Delete /TN ""RevitBridge"" /F"; Flags: runhidden

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
