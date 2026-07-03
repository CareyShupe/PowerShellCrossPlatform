$AdminUserName = "secure.baseline.adm"

# Disable the Secondary Logon service
Set-Service -Name seclogon -StartupType Disabled -ErrorAction SilentlyContinue

$LGPOPath = "C:\Windows\Temp\LGPO\LGPO.exe"
$StigPath = "C:\Windows\Temp\STIG.GPOs"

# Apply the Group Policies
$StigFolders = @(
    "DoD Microsoft Defender Antivirus STIG v2r7",
    "DoD Microsoft Edge v2r4",
    "DoD Windows 11 v2r6",
    "DoD Windows Defender Firewall v2r2"
)

foreach ($folder in $StigFolders)
{
    $path = Join-Path $StigPath $folder
    if (Test-Path $path)
    {
        & $LGPOPath /g $path
    }
}

#  Apply the Audit and Security Templates
$AuditCSV = Join-Path $StigPath "DoD Windows 11 v2r7\GPOs\DoD Windows 11 v2r6\GPOs\{B89351F4-E48C-442A-833D-7BC43D7BBFB7}\DomainSysvol\GPO\Machine\microsoft\windows nt\Audit\audit.csv"
$SecEdit = Join-Path $StigPath "DoD Windows 11 v2r6\GPOs\{B89351F4-E48C-442A-833D-7BC43D7BBFB7}\DomainSysvol\GPO\Machine\microsoft\windows nt\SecEdit\GptTmpl.inf"

if (Test-Path $AuditCSV)
{
    & $LGPOPath /ac $AuditCSV 
}
if (Test-Path $SecEdit)
{
    & $LGPOPath /s  $SecEdit 
}

& $LGPOPath /t C:\Windows\Temp\policies.txt

reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" /f


# Set Password expiration
$users = @($AdminUserName, 'Administrator', 'Guest', 'X_Admin', 'DefaultAccount', 'Visitor', 'WDAGUtilityAccount', 'defaultuser0')

foreach ($user in $users)
{
    if (Get-LocalUser -Name $user -ErrorAction SilentlyContinue)
    {
        Set-LocalUser -Name $user -PasswordNeverExpires $false
    }
}

# Disable DEP (NX OptOut)
bcdedit.exe /set "{current}" nx OptOut | Out-Null
net user defaultuser0 /delete

Add-BitLockerKeyProtector -MountPoint "C:" -TpmProtector
manage-bde -on C: -UsedSpaceOnly -EncryptionMethod xts_aes256 -SkipHardwareTest
