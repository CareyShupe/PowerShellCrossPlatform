#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Performs controlled operations against a specified target drive.

.DESCRIPTION
    This advanced function uses CmdletBinding to enable common PowerShell
    features such as -Verbose, -ErrorAction, and -WhatIf/-Confirm support.

    SupportsShouldProcess is enabled to allow safe execution of actions
    that modify system state, with ConfirmImpact set to 'Medium' to prompt
    for confirmation when appropriate.

    Parameters are validated to ensure proper input formatting and to
    support reliable, repeatable execution in automated workflows.

.PARAMETER DriveLetter
    Specifies the target drive letter. Must be a single alphabetical character.

.PARAMETER Force
    Overrides default safeguards to force execution, such as overwriting
    or reprocessing existing resources.

.OUTPUTS
    None. Writes log output to the console.

.INPUTS
    None. Does not accept pipeline input.

.EXAMPLE
    PS> Invoke-Baseline -DriveLetter C -WhatIf
    Simulates the operation without making changes.

.EXAMPLE
    PS> Invoke-Baseline -DriveLetter D -Force
    Executes the operation and forces overwrite behavior.

.NOTES
    - Requires winget (App Installer) to be installed and available in PATH.
    - Designed for safe, idempotent, and automation-friendly execution.
#>

[CmdletBinding(
    SupportsShouldProcess = $true,
    ConfirmImpact = 'Medium'
)]
param(
    [Parameter(Mandatory, HelpMessage = "Enter the target drive letter (e.g., C, D, E).")]
    [ValidatePattern("^[A-Za-z]$")]
    [string]$DriveLetter,

    [Parameter(HelpMessage = "Force overwrite/re-download of existing packages.")]
    [switch]$Force
)

# =============================================================================
# GLOBAL CONFIGURATION & INITIALIZATION
# =============================================================================
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Normalize drive path and verify availability
$DriveLetter = $DriveLetter.ToUpper()
$DriveRoot = "${DriveLetter}:\"

if (-not (Test-Path $DriveRoot))
{
    throw "Drive $DriveLetter does not exist or is not ready."
}

# Define immutable path mapping for the baseline environment
$Paths = @{}
$Paths.Root = $DriveRoot
$Paths.Home = Join-Path -Path $Paths.Root -ChildPath "Secure.Baseline"
$Paths.VirtualMachines = Join-Path -Path $Paths.Root -ChildPath "VirtualMachines"
$Paths.OSMediaRoot = Join-Path -Path $Paths.Root -ChildPath "OS.Installation.Media"
$Paths.Logs = Join-Path -Path $Paths.Root -ChildPath "Logs"
$Paths.OSMedia = Join-Path -Path $Paths.OSMediaRoot -ChildPath "Microsoft.Windows.11.25H2.x64"
$Paths.Templates = Join-Path -Path $Paths.Home -ChildPath "ADMX.Templates"
$Paths.PolicyDefinitions = Join-Path -Path $Paths.Templates -ChildPath "PolicyDefinitions"
$Paths.Benchmarks = Join-Path -Path $Paths.Home -ChildPath "STIG.Benchmarks"
$Paths.GPOs = Join-Path -Path $Paths.Home -ChildPath "STIG.GPOs"
$Paths.Tools = Join-Path -Path $Paths.Home -ChildPath "STIG.Tools"
$Paths.LGPO = Join-Path -Path $Paths.Home -ChildPath "LGPO"
$Paths.Packages = Join-Path -Path $Paths.Home -ChildPath "Packages"
$Paths.Scripts = Join-Path -Path $Paths.Home -ChildPath "Scripts"

# Define idempotent download configuration.
$Downloads = @(
    @{
        BaseUrl = 'https://dl.dod.cyber.mil/wp-content/uploads/stigs/zip/'
        Files   = @(
            'U_MS_Windows_11_V2R8_STIG_SCAP_1-3_Benchmark.zip',
            'U_MS_Defender_Antivirus_V2R8_STIG_SCAP_1-3_Benchmark.zip',
            'U_MS_Edge_V2R5_STIG_SCAP_1-3_Benchmark.zip',
            'U_MS_DotNet_Framework_4-0_V2R7_STIG_SCAP_1-3_Benchmark.zip',
            'U_MS_Windows_Defender_Firewall_V2R3_STIG_SCAP_1-2_Benchmark.zip'
        )
        Path    = $Paths.Benchmarks
    },
    @{
        BaseUrl = 'https://dl.dod.cyber.mil/wp-content/uploads/pki-pke/zip'
        Files   = @(
            'U_STIG_GPO_Package_April_2026.zip'
        )
        Path    = $Paths.GPOs
    },
    @{
        BaseUrl = 'https://dl.dod.cyber.mil/wp-content/uploads/stigs/zip'
        Files   = @(
            'scc-5.14.1_Windows_bundle.zip'
        )
        Path    = $Paths.Tools
    },
    @{
        BaseUrl = 'https://dl.dod.cyber.mil/wp-content/uploads/pki-pke/msi'
        Files   = @(
            'InstallRoot_5.6x64.msi'
        )
        Path    = $Paths.Tools
    }
)

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

#region Filesystem
function New-Directory
{
    <#
    .SYNOPSIS
        Ensures a directory exists in an idempotent manner.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (Test-Path -Path $Path -PathType Container)
    {
        Write-Verbose "Exists: $Path"
        return
    }

    if ($PSCmdlet.ShouldProcess($Path, "Create Directory"))
    {
        try
        {
            New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Information "Created: $Path" -InformationAction Continue
        }
        catch
        {
            Write-Error "CRITICAL: Failed to create $Path : $($_.Exception.Message)"
        }
    }
}
#endregion

#region Package Management
function Receive-Package
{
    <#
    .SYNOPSIS
        Downloads a Winget package to a structured local repository.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [string]$PackageId,

        [Parameter(Mandatory)]
        [string]$TargetRoot,

        [switch]$Force
    )

    $SafeName = $PackageId -replace '[^a-zA-Z0-9\.-]', '_'
    $TargetFolder = Join-Path -Path $TargetRoot -ChildPath $SafeName

    New-Directory -Path $TargetFolder

    $FolderHasFiles = Get-ChildItem -Path $TargetFolder -Recurse -File | Select-Object -First 1
    if ($FolderHasFiles -and -not $Force)
    {
        Write-Warning "Skipping: $PackageId (Files already exist in $SafeName). Use -Force to overwrite."
        return
    }

    Write-Information "Processing: $PackageId → $TargetFolder" -InformationAction Continue

    $arguments = @(
        "download",
        "--id", $PackageId,
        "--download-directory", $TargetFolder,
        "--accept-source-agreements",
        "--accept-package-agreements",
        "--disable-interactivity"
    )

    if ($Force)
    {
        $arguments += "--force"
    }

    if ($PSCmdlet.ShouldProcess($PackageId, "Winget Download to $TargetFolder"))
    {
        try
        {
            $proc = Start-Process `
                -FilePath "winget" `
                -ArgumentList $arguments `
                -NoNewWindow `
                -Wait `
                -PassThru `
                -ErrorAction Stop

            if ($proc.ExitCode -eq 0)
            {
                $NewFiles = Get-ChildItem -Path $TargetFolder -Recurse -File
                if (-not $NewFiles)
                {
                    Write-Warning "Winget reported success, but no files were found in $TargetFolder"
                }
                else
                {
                    Write-Information "Successfully Downloaded: $PackageId" -InformationAction Continue
                }
            }
            else
            {
                Write-Error "Winget failed for $PackageId (ExitCode $($proc.ExitCode))"
            }
        }
        catch
        {
            Write-Error "FAILED: $PackageId - $($_.Exception.Message)"
        }
    }
}

function Expand-AdmTemplates
{
    <#
    .SYNOPSIS
        Extracts ADMX/ADML pairs from an Administrative Template MSI.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory)] [string]$MsiPath,
        [Parameter(Mandatory)] [string]$DestinationPath,
        [string]$TempPath = (Join-Path $env:TEMP "ADMX_Extract")
    )

    if ($PSCmdlet.ShouldProcess($MsiPath, "Extract ADMX Templates to $DestinationPath"))
    {
        if (Test-Path $TempPath)
        {
            Remove-Item $TempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        Unblock-File -Path $MsiPath -ErrorAction Stop
        New-Item -ItemType Directory -Path $TempPath | Out-Null

        Write-Verbose "Executing administrative extraction for MSI..."
        $arguments = "/a `"$MsiPath`" /qn TARGETDIR=`"$TempPath`""
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $arguments -Wait -PassThru
        if ($process.ExitCode -ne 0)
        {
            throw "MSI extraction failed with code $($process.ExitCode)"
        }

        $policyPath = Get-ChildItem -Path $TempPath -Recurse -Directory -Filter "PolicyDefinitions" | Select-Object -First 1
        if (-not $policyPath)
        {
            throw "PolicyDefinitions not found in MSI."
        }

        $systemLang = (Get-Culture).Name
        $availableLangs = Get-ChildItem -Path $policyPath.FullName -Directory | Select-Object -ExpandProperty Name

        $finalLang = $null
        if ($availableLangs -contains $systemLang)
        {
            $finalLang = $systemLang
        }
        elseif ($systemLang.Contains("-") -and ($availableLangs -contains $systemLang.Split("-")[0]))
        {
            $finalLang = $systemLang.Split("-")[0]
        }
        elseif ($availableLangs -contains "en-US")
        {
            $finalLang = "en-US"
        }
        elseif ($availableLangs.Count -gt 0)
        {
            $finalLang = $availableLangs[0]
        }
        else
        {
            throw "No language folders found. ADMX files require at least one ADML folder."
        }

        Write-Verbose "Selected Language: $finalLang"
        if (-not (Test-Path $DestinationPath))
        {
            New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
        }

        Copy-Item -Path "$($policyPath.FullName)\*.admx" -Destination $DestinationPath -Force
        $destLangDir = New-Item -ItemType Directory -Path (Join-Path $DestinationPath $finalLang) -Force
        Copy-Item -Path "$($policyPath.FullName)\$finalLang\*.adml" -Destination $destLangDir -Force

        Remove-Item $TempPath -Recurse -Force
    }
}
#endregion

#region Download function
function Get-RemoteFile
{
    <#
    .SYNOPSIS
        Downloads a list of files from a baseline URI. Supports Force switches.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory)] [string]$BaseUri,
        [Parameter(Mandatory)] [string[]]$Downloads,
        [Parameter(Mandatory)] [string]$DestinationPath,
        [switch]$Force
    )

    if (-not(Test-Path $DestinationPath))
    {
        New-Item -ItemType Directory -Path $DestinationPath | Out-Null
    }

    # Fix potential trailing slash duplicate errors during concatenation
    $CleanBaseUri = $BaseUri.TrimEnd('/')

    foreach ($File in $Downloads)
    {
        $Uri = "$CleanBaseUri/$File"
        $OutFile = Join-Path $DestinationPath $File

        if ((Test-Path $OutFile) -and -not $Force)
        {
            Write-Verbose "Skipping existing file: $File. Use -Force to overwrite."
            continue
        }

        if ($PSCmdlet.ShouldProcess($Uri, "Download to $OutFile"))
        {
            try
            {
                Write-Information "Downloading remote file: $File" -InformationAction Continue
                Invoke-WebRequest -Uri $Uri -OutFile $OutFile -ErrorAction Stop
                Write-Information "[SUCCESS] Downloaded: $File" -InformationAction Continue
            }
            catch
            {
                Write-Error "Failed to download: $File - $($_.Exception.Message)"
                throw
            }
        }
    }
}
#endregion

# =============================================================================
# MAIN EXECUTION FLOW
# =============================================================================
function Invoke-MainExecution
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$DriveRoot,
        [hashtable]$Paths,
        [array]$Downloads,
        [switch]$Force
    )

    Write-Information "Using drive: $DriveRoot" -InformationAction Continue

    # STEP 1: Verify Core Dependencies
    if (-not (Get-Command winget -ErrorAction SilentlyContinue))
    {
        throw "winget is not installed or not in PATH. Please install App Installer."
    }

    # STEP 2: Provision Directory Structure
    foreach ($path in $Paths.Values)
    {
        New-Directory -Path $path
    }

    # STEP 3: Fetch Baseline Software Packages
    $PackageList = @(
        'Google.Chrome',
        'Microsoft.PowerShell',
        'Microsoft.VCRedist.2015+.x64',
        'Microsoft.VCRedist.2015+.x86',
        'Microsoft.WindowsTerminal',
        'Microsoft.AppInstaller',
        'Microsoft.WindowsADK',
        'valinet.ExplorerPatcher',
        'Microsoft.AdministrativeTemplates'
    )

    foreach ($pkg in $PackageList)
    {
        Receive-Package -PackageId $pkg -TargetRoot $Paths.Packages -Force:$Force
    }

    # STEP 4: Repository Hygiene
    if ($PSCmdlet.ShouldProcess("YAML manifest files in $($Paths.Home)", "Purge manifest artifacts"))
    {
        Write-Information "Cleaning up YAML files in Packages..." -InformationAction Continue
        Get-ChildItem -Path $Paths.Packages -Recurse -Include *.yaml, *.yml -File -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    # STEP 5: Administrative Template Extraction
    $MsiSearchPath = Get-ChildItem -Path "$($Paths.Packages)\Microsoft.AdministrativeTemplates\*.msi" -Recurse |
        Select-Object -ExpandProperty FullName -First 1

    if ($MsiSearchPath)
    {
        Expand-AdmTemplates -MsiPath $MsiSearchPath -DestinationPath $Paths.PolicyDefinitions
    }
    else
    {
        Write-Warning "Could not locate the AdministrativeTemplates MSI file. Skipping extraction step."
    }

    # STEP 6: Download Remote Files from DoD STIGs and PKI/PKE.
    foreach ($Download in $Downloads)
    {
        Get-RemoteFile -BaseUri $Download.BaseUrl -Downloads $Download.Files -DestinationPath $Download.Path -Force:$Force
    }

    # STEP 7: Finalization
    Write-Information "Deployment process finished successfully." -InformationAction Continue

    if ($PSCmdlet.ShouldProcess("Play completion tone", "Beep"))
    {
        [console]::beep(523, 300); [console]::beep(659, 300); [console]::beep(784, 500)
    }
}

# Explicitly pass the top-level parameters and configuration downstream
Invoke-MainExecution -DriveRoot $DriveRoot -Paths $Paths -Downloads $Downloads -Force:$Force -WhatIf:$WhatIfPreference