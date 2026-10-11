; Nyxplorer Setup wizard (Inno Setup 6).
; Built by .github/workflows/nyxplorer-release.yml with:
;   /DAppVersion=x.y.z.w /DPayloadDir=... /DLicenseFile=... /DIconFile=... /DOutputDir=...
;   /DWizardSmallImages=a.png,b.png /DWizardLargeImages=c.png,d.png   (from nyxplorer/scripts/New-NyxplorerInstallerImages.ps1)

#ifndef AppVersion
  #define AppVersion "0.0.0.0"
#endif

[Setup]
AppId={{8E4C2B7A-6D1F-4A3E-9B5C-2F7D0A1E6C49}
AppName=Nyxplorer
AppVersion={#AppVersion}
AppVerName=Nyxplorer {#AppVersion}
AppPublisher=Shaiyon69
AppPublisherURL=https://github.com/Shaiyon69/Nyxplorer
AppSupportURL=https://github.com/Shaiyon69/Nyxplorer/issues
AppUpdatesURL=https://github.com/Shaiyon69/Nyxplorer/releases
VersionInfoVersion={#AppVersion}
VersionInfoCompany=Shaiyon69
VersionInfoDescription=Nyxplorer Setup
WizardStyle=modern dark
#ifdef WizardSmallImages
WizardSmallImageFile={#WizardSmallImages}
#endif
#ifdef WizardLargeImages
WizardImageFile={#WizardLargeImages}
#endif
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19041
; Nyxplorer is an MSIX app: Windows manages its folder and lists it in Settings > Apps for uninstall.
; Setup lets the user pick a folder and registers it as an app package volume, so Windows installs into <folder>\WindowsApps.
; Silent installs can pass /INSTALLPATH=D:\Apps\Nyxplorer (or /DRIVE=D:, the same as /INSTALLPATH=D:\)
CreateAppDir=no
Uninstallable=no
DisableProgramGroupPage=yes
DisableReadyPage=no
LicenseFile={#LicenseFile}
SetupIconFile={#IconFile}
OutputDir={#OutputDir}
OutputBaseFilename=Nyxplorer-Setup-{#AppVersion}-x64
Compression=lzma2/max
SolidCompression=yes
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Dirs]
Name: "{commonappdata}\NyxplorerSetup"; Permissions: users-modify

[Files]
Source: "{#PayloadDir}\*"; DestDir: "{commonappdata}\NyxplorerSetup"; Flags: recursesubdirs ignoreversion

[Run]
Filename: "{win}\explorer.exe"; Parameters: "nyxplorer:"; Description: "Launch Nyxplorer"; Flags: postinstall nowait skipifsilent runasoriginaluser; Check: InstallSucceeded

[Code]
const
  DRIVE_FIXED = 3;

var
  FailedStage: String;
  PathPage: TInputDirWizardPage;

function GetDriveType(lpRootPathName: String): UINT;
  external 'GetDriveTypeW@kernel32.dll stdcall';

function GetVolumeInformation(lpRootPathName: String; lpVolumeNameBuffer: String; nVolumeNameSize: DWORD;
  var lpVolumeSerialNumber: DWORD; var lpMaximumComponentLength: DWORD; var lpFileSystemFlags: DWORD;
  lpFileSystemNameBuffer: String; nFileSystemNameSize: DWORD): BOOL;
  external 'GetVolumeInformationW@kernel32.dll stdcall';

function GetFileSystem(const Root: String): String;
var
  Serial, MaxLength, Flags: DWORD;
  VolumeName, FileSystem: String;
begin
  VolumeName := StringOfChar(' ', 261);
  FileSystem := StringOfChar(' ', 261);
  if GetVolumeInformation(Root, VolumeName, 261, Serial, MaxLength, Flags, FileSystem, 261) then
    Result := Trim(Copy(FileSystem, 1, Pos(#0, FileSystem + #0) - 1))
  else
    Result := '';
end;

function InstallSucceeded: Boolean;
begin
  Result := FailedStage = '';
end;

function SystemDrive: String;
begin
  Result := Uppercase(ExtractFileDrive(ExpandConstant('{win}')));
end;

// A drive root keeps its trailing backslash ("D:\"), any other folder has none
function SelectedPath: String;
begin
  Result := RemoveBackslashUnlessRoot(Trim(PathPage.Values[0]));
  if Length(Result) = 2 then
    Result := Result + '\';
end;

function SelectedDrive: String;
begin
  Result := Uppercase(ExtractFileDrive(SelectedPath));
end;

function IsDefaultLocation: Boolean;
begin
  Result := CompareText(SelectedPath, SystemDrive + '\') = 0;
end;

procedure InitializeWizard;
var
  Requested: String;
begin
  Requested := ExpandConstant('{param:INSTALLPATH|}');
  if Requested = '' then
    Requested := ExpandConstant('{param:DRIVE|}');
  if Requested = '' then
    Requested := SystemDrive + '\';

  PathPage := CreateInputDirPage(wpLicense, 'Install location',
    'Choose the folder to install Nyxplorer in.',
    'Nyxplorer is a Windows app package, so Windows keeps its files in a protected WindowsApps folder inside the folder you pick, ' +
    'the same way the Microsoft Store does. Keep ' + SystemDrive + '\ to use the Windows default location, ' +
    'or pick a folder on another drive (Windows allows only its default location on ' + SystemDrive + '). ' +
    'The folder must be on an NTFS drive built into this PC.',
    False, '');
  PathPage.Add('Install Nyxplorer in:');
  PathPage.Values[0] := Requested;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  Path, Root: String;
begin
  Result := True;
  if CurPageID <> PathPage.ID then
    Exit;

  Path := SelectedPath;
  Root := SelectedDrive + '\';
  if (Length(Path) < 3) or (Path[2] <> ':') or (Path[3] <> '\') then
    Result := False
  else
    Result := (GetDriveType(Root) = DRIVE_FIXED) and (CompareText(GetFileSystem(Root), 'NTFS') = 0);

  if not Result then
  begin
    SuppressibleMsgBox('Choose a folder on an NTFS drive built into this PC, such as D:\Apps\Nyxplorer.' + #13#10 +
      'Network, removable and FAT/exFAT drives cannot hold apps.', mbError, MB_OK, IDOK);
    Exit;
  end;

  // Windows keeps one app store per drive, and the Windows drive's is fixed to Program Files\WindowsApps
  if (SelectedDrive = SystemDrive) and not IsDefaultLocation then
  begin
    Result := False;
    SuppressibleMsgBox('Windows only installs apps on ' + SystemDrive + ' in ' + SystemDrive + '\Program Files\WindowsApps.' + #13#10 +
      'Choose ' + SystemDrive + '\ for the default location, or a folder on another drive, such as D:\Apps\Nyxplorer.',
      mbError, MB_OK, IDOK);
  end;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo,
  MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
var
  Location: String;
begin
  if IsDefaultLocation then
    Location := 'Windows default app location (' + SystemDrive + '\Program Files\WindowsApps)'
  else
    Location := AddBackslash(SelectedPath) + 'WindowsApps (managed by Windows)';
  Result := 'Install location:' + NewLine + Space + Location + NewLine + NewLine +
            'Setup will also:' + NewLine +
            Space + 'Trust the Nyxplorer signing certificate' + NewLine +
            Space + 'Install the .NET 10 Desktop Runtime and Windows App Runtime if they are missing';
end;

function RunStage(const Stage: String; AsOriginalUser: Boolean): Boolean;
var
  Params, LogFile, Note: String;
  ResultCode: Integer;
  Started: Boolean;
begin
  LogFile := ExpandConstant('{commonappdata}\NyxplorerSetup\Nyxplorer-Setup-' + Stage + '.log');
  // A trailing backslash before the closing quote would escape it, so the path is always passed without one
  Params := '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{commonappdata}\NyxplorerSetup\Install-Nyxplorer.ps1') +
            '" -Stage ' + Stage + ' -InstallPath "' + RemoveBackslash(SelectedPath) + '" -LogPath "' + LogFile + '"';

  if AsOriginalUser then
    Started := ExecAsOriginalUser('powershell.exe', Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode)
  else
    Started := Exec('powershell.exe', Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

  // 2 = installed, but on the Windows drive; 3 = installed, but in <drive>\WindowsApps instead of the chosen folder
  Result := Started and ((ResultCode = 0) or (ResultCode = 2) or (ResultCode = 3));
  if not Result then
  begin
    FailedStage := Stage;
    // Keep the log where the user can find it after the payload folder is removed
    CopyFile(LogFile, ExpandConstant('{userdesktop}\Nyxplorer-Setup-' + Stage + '.log'), False);
    SuppressibleMsgBox('Nyxplorer could not be installed (' + Stage + ' step).' + #13#10 + #13#10 +
           'A log was saved to your desktop: Nyxplorer-Setup-' + Stage + '.log' + #13#10 +
           'Please attach it to an issue at github.com/Shaiyon69/Nyxplorer/issues.', mbError, MB_OK, IDOK);
  end
  else if (ResultCode = 2) or (ResultCode = 3) then
  begin
    if ResultCode = 2 then
      Note := 'Windows could not install Nyxplorer in ' + SelectedPath + ', so it was installed on the Windows drive instead.'
    else
      Note := 'Windows does not allow apps in ' + SelectedPath + ', so Nyxplorer was installed in ' + SelectedDrive + '\WindowsApps instead.';
    CopyFile(LogFile, ExpandConstant('{userdesktop}\Nyxplorer-Setup-' + Stage + '.log'), False);
    // The Machine stage logs why the package volume could not be created
    CopyFile(ExpandConstant('{commonappdata}\NyxplorerSetup\Nyxplorer-Setup-Machine.log'),
      ExpandConstant('{userdesktop}\Nyxplorer-Setup-Machine.log'), False);
    SuppressibleMsgBox(Note + #13#10 + 'The log on your desktop has the reason.', mbInformation, MB_OK, IDOK);
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    WizardForm.StatusLabel.Caption := 'Trusting the Nyxplorer certificate and checking .NET...';
    if RunStage('Machine', False) then
    begin
      WizardForm.StatusLabel.Caption := 'Installing Windows App Runtime and Nyxplorer...';
      RunStage('User', True);
    end;
  end
  else if CurStep = ssDone then
    DelTree(ExpandConstant('{commonappdata}\NyxplorerSetup'), True, True, True);
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = wpFinished) and (FailedStage <> '') then
    WizardForm.FinishedLabel.Caption := 'Nyxplorer was not installed. See the log on your desktop for details.';
end;
