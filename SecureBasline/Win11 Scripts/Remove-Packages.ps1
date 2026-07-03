#Requires -RunAsAdministrator
#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string[]]$PackageNames = @(
        'Microsoft.Microsoft3DViewer'
        'Microsoft.MixedReality.Portal'
        'Microsoft.BingSearch'
        'Microsoft.BingNews'
        'Microsoft.BingWeather'
        'Microsoft.WindowsCamera'
        'Clipchamp.Clipchamp'
        'Microsoft.WindowsAlarms'
        'Microsoft.549981C3F5F10'
        'Microsoft.GetHelp'
        'Microsoft.Windows.DevHome'
        'MicrosoftCorporationII.MicrosoftFamily'
        'microsoft.windowscommunicationsapps'
        'Microsoft.SkypeApp'
        'MSTeams'
        'Microsoft.WindowsFeedbackHub'
        'Microsoft.WindowsMaps'
        'Microsoft.MicrosoftOfficeHub'
        'Microsoft.OutlookForWindows'
        'Microsoft.MSPaint'
        'Microsoft.Paint'
        'Microsoft.People'
        'Microsoft.PowerAutomateDesktop'
        'MicrosoftCorporationII.QuickAssist'
        'Microsoft.MicrosoftSolitaireCollection'
        'Microsoft.GamingApp'
        'Microsoft.XboxApp'
        'Microsoft.XboxIdentityProvider'
        'Microsoft.XboxGameOverlay'
        'Microsoft.Xbox.TCUI'
        'Microsoft.XboxGamingOverlay'
        'Microsoft.ZuneVideo'
        'Microsoft.WindowsSoundRecorder'
        'Microsoft.MicrosoftStickyNotes'
        'Microsoft.Getstarted'
        'Microsoft.Todos'
        'Microsoft.YourPhone'
        'Microsoft.Office.OneNote'
    ),

    [string[]]$CapabilityNames = @(
        'App.Support.QuickAssist'
        'App.StepsRecorder'
        'Microsoft.Windows.MSPaint'
        'OpenSSH.Server'
    ),

    [string[]]$OptionalFeatureNames = @(
        'Microsoft-Windows-Subsystem-Linux'
        'NetFx3'
        'Containers-DisposableClientVM'
        'Recall'
    ),

    [string]$TranscriptPath = "$env:ProgramData\SecureBaseline\Logs\Remove-Packages.log",

    [switch]$ContinueOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

$failures = New-Object System.Collections.Generic.List[object]
$results = New-Object System.Collections.Generic.List[object]
$transcriptStarted = $false

function Write-CleanupLog
{
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message

    switch ($Level)
    {
        'WARN'
        {
            Write-Warning $line 
        }
        'ERROR'
        {
            Write-Error -Message $line -ErrorAction Continue 
        }
        default
        {
            Write-Information $line 
        }
    }
}

function Add-Result
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Succeeded', 'Skipped', 'Failed', 'WhatIf')]
        [string]$Status,

        [string]$Message
    )

    $results.Add([pscustomobject]@{
            Category = $Category
            Name     = $Name
            Action   = $Action
            Status   = $Status
            Message  = $Message
        })
}

function Add-Failure
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Add-Result -Category $Category -Name $Name -Action $Action -Status 'Failed' -Message $Message
    $failures.Add([pscustomobject]@{
            Category = $Category
            Name     = $Name
            Action   = $Action
            Message  = $Message
        })
    Write-CleanupLog -Level ERROR -Message "$Category '$Name' failed during '$Action': $Message"
}

function Invoke-TrackedAction
{
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock
    )

    if (-not $PSCmdlet.ShouldProcess($Name, $Action))
    {
        Add-Result -Category $Category -Name $Name -Action $Action -Status 'WhatIf' -Message 'Action was not executed.'
        return
    }

    try
    {
        & $ScriptBlock
        Add-Result -Category $Category -Name $Name -Action $Action -Status 'Succeeded'
        Write-CleanupLog -Level INFO -Message "$Category '$Name' completed action '$Action'."
    }
    catch
    {
        Add-Failure -Category $Category -Name $Name -Action $Action -Message $_.Exception.Message
    }
}

function Get-MatchingProvisionedPackage
{
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$ProvisionedPackages,

        [Parameter(Mandatory = $true)]
        [string]$TargetName
    )

    $escapedTarget = [regex]::Escape($TargetName)

    $ProvisionedPackages | Where-Object {
        $_.DisplayName -eq $TargetName -or
        $_.PackageName -match "^$escapedTarget([_.]|$)"
    }
}

function Get-MatchingAppxPackage
{
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$AppxPackages,

        [Parameter(Mandatory = $true)]
        [string]$TargetName
    )

    $escapedTarget = [regex]::Escape($TargetName)

    $AppxPackages | Where-Object {
        $_.Name -eq $TargetName -or
        $_.PackageFullName -match "^$escapedTarget([_.]|$)" -or
        $_.PackageFamilyName -match "^$escapedTarget([_.]|$)"
    }
}

try
{
    if ($TranscriptPath)
    {
        $logDirectory = Split-Path -Path $TranscriptPath -Parent
        if ($logDirectory -and -not (Test-Path -LiteralPath $logDirectory))
        {
            New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
        }

        Start-Transcript -Path $TranscriptPath -Append | Out-Null
        $transcriptStarted = $true
    }

    Write-CleanupLog -Level INFO -Message 'Starting Windows 11 package cleanup.'

    Write-CleanupLog -Level INFO -Message 'Loading installed and provisioned AppX package inventory.'
    $provisionedPackages = @(Get-AppxProvisionedPackage -Online)
    $appxPackages = @(Get-AppxPackage -AllUsers)

    foreach ($target in $PackageNames)
    {
        $matchingProvisionedPackages = @(Get-MatchingProvisionedPackage -ProvisionedPackages $provisionedPackages -TargetName $target)
        $matchingAppxPackages = @(Get-MatchingAppxPackage -AppxPackages $appxPackages -TargetName $target)

        if (-not $matchingProvisionedPackages -and -not $matchingAppxPackages)
        {
            Add-Result -Category 'AppX' -Name $target -Action 'Locate package' -Status 'Skipped' -Message 'No installed or provisioned package matched.'
            Write-CleanupLog -Level INFO -Message "AppX '$target' was not present."
            continue
        }

        foreach ($package in $matchingProvisionedPackages)
        {
            Invoke-TrackedAction -Category 'Provisioned AppX' -Name $package.PackageName -Action 'Remove provisioned package' -ScriptBlock {
                Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName | Out-Null
            }
        }

        foreach ($package in $matchingAppxPackages)
        {
            Invoke-TrackedAction -Category 'Installed AppX' -Name $package.PackageFullName -Action 'Remove installed package for all users' -ScriptBlock {
                Remove-AppxPackage -Package $package.PackageFullName -AllUsers
            }
        }
    }

    Write-CleanupLog -Level INFO -Message 'Loading installed Windows capability inventory.'
    $installedCapabilities = @(Get-WindowsCapability -Online | Where-Object { $_.State -eq 'Installed' })

    foreach ($target in $CapabilityNames)
    {
        $escapedTarget = [regex]::Escape($target)
        $matchingCapabilities = @($installedCapabilities | Where-Object { $_.Name -match "^$escapedTarget([~.]|$)" })

        if (-not $matchingCapabilities)
        {
            Add-Result -Category 'Capability' -Name $target -Action 'Locate capability' -Status 'Skipped' -Message 'Capability was not installed.'
            Write-CleanupLog -Level INFO -Message "Capability '$target' was not installed."
            continue
        }

        foreach ($capability in $matchingCapabilities)
        {
            Invoke-TrackedAction -Category 'Capability' -Name $capability.Name -Action 'Remove Windows capability' -ScriptBlock {
                Remove-WindowsCapability -Online -Name $capability.Name | Out-Null
            }
        }
    }

    foreach ($featureName in $OptionalFeatureNames)
    {
        try
        {
            $feature = Get-WindowsOptionalFeature -Online -FeatureName $featureName
        }
        catch
        {
            Add-Result -Category 'Optional Feature' -Name $featureName -Action 'Locate optional feature' -Status 'Skipped' -Message $_.Exception.Message
            Write-CleanupLog -Level WARN -Message "Optional feature '$featureName' was not found: $($_.Exception.Message)"
            continue
        }

        if ($feature.State -ne 'Enabled')
        {
            Add-Result -Category 'Optional Feature' -Name $featureName -Action 'Disable optional feature' -Status 'Skipped' -Message "Current state is '$($feature.State)'."
            Write-CleanupLog -Level INFO -Message "Optional feature '$featureName' is '$($feature.State)' and was skipped."
            continue
        }

        Invoke-TrackedAction -Category 'Optional Feature' -Name $featureName -Action 'Disable optional feature' -ScriptBlock {
            Disable-WindowsOptionalFeature -Online -FeatureName $featureName -NoRestart | Out-Null
        }
    }

    $results | Sort-Object Category, Name, Action | Format-Table -AutoSize

    if ($failures.Count -gt 0)
    {
        $message = "Windows 11 package cleanup completed with $($failures.Count) failure(s)."
        Write-CleanupLog -Level ERROR -Message $message

        if (-not $ContinueOnError)
        {
            throw $message
        }
    }

    Write-CleanupLog -Level INFO -Message 'Windows 11 package cleanup completed.'
}
finally
{
    if ($transcriptStarted)
    {
        Stop-Transcript | Out-Null
    }
}
