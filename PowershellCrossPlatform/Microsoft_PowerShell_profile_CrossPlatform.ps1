<#
.SYNOPSIS
    Custom PowerShell 7+ Core Profile Configuration (Cross-Platform).
.DESCRIPTION
    Optimized terminal profile handling environment variables, fast registry drive
    mounting (Windows only), deferred asynchronous module/engine maintenance updates,
    custom PSReadLine interactive configurations, and native command completions.
    Now supports Windows, macOS, and Linux.
.NOTES
    File Path:   $PROFILE
    Author:      Carey Shupe (Updated for cross-platform)
    Version:     3.0
    Engine:      PowerShell Core v7.0+ (Required)
    Platform:    Windows, macOS, Linux
    Dependencies: PSReadLine (v2.2.0+ preferred), Terminal-Icons, oh-my-posh
.LINK
    https://github.com/PowerShell/PSReadLine
#>

#requires -Version 7.0
using namespace System.Management.Automation
using namespace System.Management.Automation.Language
using namespace System.Diagnostics.CodeAnalysis

# --- Platform Detection (PowerShell 7+ built-in variables) ---
# $IsWindows, $IsMacOS, $IsLinux are automatically available
# Fallback for older builds
if (-not (Get-Variable -Name IsWindows -Scope Script -ErrorAction SilentlyContinue))
{
    $Script:ProfileIsWindows = $PSVersionTable.OS -like '*Windows*'
    $Script:ProfileIsMacOS = $PSVersionTable.OS -like '*Darwin*'
    $Script:ProfileIsLinux = $PSVersionTable.OS -like '*Linux*'
}
else
{
    $Script:ProfileIsWindows = $IsWindows
    $Script:ProfileIsMacOS = $IsMacOS
    $Script:ProfileIsLinux = $IsLinux
}

# --- Console & Host Behavior ---
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest

$GLOBAL_GitHubApiUrl = 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'
$PSDefaultParameterValues['Out-File:Encoding'] = 'UTF-8'

# --- Window Title (Windows only) ---
if ($IsWindows)
{
    try
    {
        if (-not [System.Security.Principal.WindowsPrincipal]::new([System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
        {
            $Host.UI.RawUI.WindowTitle = "PowerShell (User)"
        }
    }
    catch
    {
        # Silently fail if window title not supported
    }
}

# --- Core Functions ---
function Update-Modules
{
    $modules = @('PSScriptAnalyzer', 'Pester', 'PowerShellGet', 'PackageManagement', 'Terminal-Icons', 'PSReadLine')
    $latestModules = Find-Module -Name $modules -ErrorAction SilentlyContinue

    if (-not $latestModules)
    {
        return
    }

    $modules | ForEach-Object -Parallel {
        try
        {
            $installed = Get-Module -ListAvailable -Name $_ | Sort-Object Version -Descending | Select-Object -First 1
            $latest = $using:latestModules | Where-Object Name -EQ $_
            if (-not $latest)
            {
                return
            }

            if (-not $installed -or ($installed.Version -lt $latest.Version))
            {
                Install-Module -Name $_ -Force -Scope CurrentUser -AllowClobber -SkipPublisherCheck
            }
        }
        catch
        {
            # Silently skip failed module updates
        }
    } -ThrottleLimit 3
}

function Update-PowerShell
{
    param ([string]$ApiUrl = $GLOBAL_GitHubApiUrl)

    if (-not (Test-Connection 'github.com' -Count 1 -Quiet -TimeoutSeconds 1 -ErrorAction SilentlyContinue))
    {
        return $false
    }

    try
    {
        $latestReleaseInfo = Invoke-RestMethod -Uri $ApiUrl -TimeoutSec 5
        $tag = $latestReleaseInfo.tag_name -replace '^[vV]', ''
        $latestVersion = [Version]$tag
    }
    catch
    {
        return $false
    }

    if ($PSVersionTable.PSVersion -lt $latestVersion)
    {
        if ($IsWindows)
        {
            $packageManagers = @('winget', 'choco', 'scoop')
        }
        elseif ($IsMacOS)
        {
            $packageManagers = @('brew')
        }
        elseif ($IsLinux)
        {
            $packageManagers = @('apt', 'dnf', 'pacman', 'zypper', 'emerge')
        }
        else
        {
            $packageManagers = @()
        }

        if (-not $packageManagers)
        {
            return
        }

        foreach ($pm in $packageManagers)
        {
            if (Get-Command $pm -ErrorAction SilentlyContinue -CommandType Application)
            {
                try
                {
                    switch ($pm)
                    {
                        'winget'
                        {
                            winget upgrade 'Microsoft.PowerShell' --accept-source-agreements --accept-package-agreements -h
                        }
                        'choco'
                        {
                            choco upgrade powershell-core -y
                        }
                        'scoop'
                        {
                            scoop update powershell
                        }
                        'brew'
                        {
                            brew upgrade powershell
                        }
                        { $_ -in @('apt', 'dnf', 'pacman', 'zypper', 'emerge') }
                        {
                            Write-Host "Run: sudo $pm install powershell-core (or equivalent for your distro)"
                        }
                    }
                }
                catch
                {
                    # Silently continue if package manager update fails
                }
                break
            }
        }
    }
}

# --- Fast Mounting & Module Loading ---
# Registry drives only available on Windows
if ($IsWindows)
{
    $registryDrives = @{
        "HKU"  = "HKEY_USERS"
        "HKCR" = "HKEY_CLASSES_ROOT"
        "HKCC" = "HKEY_CURRENT_CONFIG"
    }

    foreach ($drive in $registryDrives.GetEnumerator())
    {
        if (-not (Get-PSDrive -Name $drive.Key -ErrorAction SilentlyContinue))
        {
            try
            {
                New-PSDrive -Name $drive.Key -PSProvider Registry -Root $drive.Value | Out-Null
            }
            catch
            {
                # Silently skip if drive mounting fails
            }
        }
    }
}

# Direct imports
@('PSReadLine', 'Terminal-Icons') | ForEach-Object {
    Import-Module $_ -ErrorAction SilentlyContinue
}

# --- Deferred Maintenance Gate (Non-blocking execution) ---
# Use cross-platform temp path
$tempPath = if ($IsWindows)
{
    $env:TEMP
}
else
{
    $env:TMPDIR
}
$checkFile = Join-Path $tempPath "ps_update_check.txt"

$lastCheck = Get-Content $checkFile -ErrorAction SilentlyContinue
if (-not $lastCheck -or ((Get-Date) - [datetime]$lastCheck).TotalHours -gt 24)
{
    # Use ThreadJob if available, otherwise fall back to synchronous execution
    if (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue)
    {
        Start-ThreadJob -ScriptBlock {
            param($Url, $CheckFile)
            Update-Modules
            Update-PowerShell -ApiUrl $Url
            (Get-Date).ToString() | Set-Content $CheckFile
        } -ArgumentList $GLOBAL_GitHubApiUrl, $checkFile | Out-Null
    }
    else
    {
        # Fallback for systems without ThreadJob
        Update-Modules
        Update-PowerShell -ApiUrl $GLOBAL_GitHubApiUrl
        (Get-Date).ToString() | Set-Content $checkFile
    }
}

# --- Prompt Initialization ---
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue)
{
    $themePath = if ($env:POSH_THEMES_PATH)
    {
        "$env:POSH_THEMES_PATH\jandedobbeleer.omp.json"
    }
    else
    {
        # Fallback: use a default theme or let oh-my-posh choose
        ''
    }

    $initCmd = "oh-my-posh init pwsh"
    if ($themePath -and (Test-Path $themePath))
    {
        $initCmd += " --config `"$themePath`""
    }

    Invoke-Expression $initCmd
}

# --- PSReadLine Configurations ---
$PSReadLineOptions = @{
    ContinuationPrompt            = ' '
    Colors                        = @{
        Command            = $PSStyle.Foreground.BrightYellow
        Comment            = $PSStyle.Foreground.BrightGreen
        ContinuationPrompt = $PSStyle.Foreground.BrightWhite
        Default            = $PSStyle.Foreground.BrightWhite
        Emphasis           = $PSStyle.Foreground.Cyan
        Error              = $PSStyle.Foreground.Red
        Keyword            = $PSStyle.Foreground.Magenta
        Member             = $PSStyle.Foreground.Cyan
        Number             = $PSStyle.Foreground.Magenta
        Operator           = $PSStyle.Foreground.White
        Parameter          = $PSStyle.Foreground.White
        Selection          = $PSStyle.Foreground.White + $PSStyle.Background.Cyan
        String             = $PSStyle.Foreground.Yellow
        Type               = $PSStyle.Foreground.Blue
        Variable           = $PSStyle.Foreground.Cyan
    }
    PredictionSource              = "HistoryAndPlugin"
    PredictionViewStyle           = "ListView"
    EditMode                      = "Emacs"
    HistorySaveStyle              = "SaveIncrementally"
    HistoryNoDuplicates           = $true
    HistorySearchCursorMovesToEnd = $true
    ShowToolTips                  = $true
    MaximumHistoryCount           = 10000
    BellStyle                     = "None"
    AddToHistoryHandler           = { param($line) if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^\s*#')
        {
            return
        }; $line }
}

if (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue)
{
    $psrlModule = Get-Module PSReadLine
    if ($psrlModule -and $psrlModule.Version -ge [Version]'2.2.0')
    {
        Set-PSReadLineOption @PSReadLineOptions
    }
    else
    {
        $reducedOptions = $PSReadLineOptions.Clone()
        $reducedOptions.Remove('PredictionViewStyle')
        Set-PSReadLineOption @reducedOptions
    }
}

# --- PSReadLine Key Handlers ---
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

# Out-GridView History Search (Windows only)
if ($IsWindows -and (Get-Command Out-GridView -ErrorAction SilentlyContinue))
{
    Set-PSReadLineKeyHandler -Key F7 `
        -BriefDescription History `
        -LongDescription 'Show command history' `
        -ScriptBlock {
        [string] $pattern = $null
        [int]    $cursor = 0
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$pattern, [ref]$cursor)

        if ($pattern)
        {
            $pattern = [regex]::Escape($pattern)
        }

        $history = [System.Collections.ArrayList]@(
            $last = ''
            $lines = ''
            foreach ($line in [System.IO.File]::ReadLines((Get-PSReadLineOption).HistorySavePath))
            {
                if ($line.EndsWith('`'))
                {
                    $line = $line.Substring(0, $line.Length - 1)
                    $lines = if ($lines)
                    {
                        "$lines`n$line"
                    }
                    else
                    {
                        $line
                    }
                    continue
                }
                if ($lines)
                {
                    $line = "$lines`n$line"; $lines = ''
                }
                if (-not $pattern -or $line -match $pattern)
                {
                    if ($line -ne $last)
                    {
                        $history.Add($line) | Out-Null
                        $last = $line
                    }
                }
            }
        )

        $selected = $history | Out-GridView -Title History -OutputMode Single
        if ($null -ne $selected)
        {
            [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine()
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($selected)
        }
    }
}

# Git command auto-correction
Set-PSReadLineKeyHandler -Key Tab -BriefDescription "GitAutoCorrection" -LongDescription "Auto-correct git subcommands" -ScriptBlock {
    param($key, $arg)

    $buffer = $null
    $cursor = 0
    $ast = $null
    $tokens = @()
    $parseErrors = @()

    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState(
        [ref]$buffer, [ref]$cursor,
        [ref]$ast, [ref]$tokens, [ref]$parseErrors
    )

    $CommandAst = $ast.Find({
            $args[0] -is [System.Management.Automation.Language.CommandAst] -and
            $args[0].Extent.StartOffset -le $cursor -and
            $args[0].Extent.EndOffset -gt $cursor
        }, $true)

    if (-not $CommandAst)
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::Complete()
        return
    }

    $CommandName = $CommandAst.CommandElements[0].Value
    if ($CommandName -ne 'git')
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::Complete()
        return
    }

    if ($CommandAst.CommandElements.Count -lt 2)
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::Complete()
        return
    }

    $gitCmd = $CommandAst.CommandElements[1].Extent
    switch ($gitCmd.Text)
    {
        'cmt'
        {
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace($gitCmd.StartOffset, $gitCmd.EndOffset - $gitCmd.StartOffset, 'commit')
        }
    }
}

Set-PSReadLineKeyHandler -Key RightArrow `
    -BriefDescription ForwardCharAndAcceptNextSuggestionWord `
    -LongDescription "Move cursor right or accept the next word in suggestion when at the end of current line" `
    -ScriptBlock {
    param($key, $arg)
    $line = $null; $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    if ($cursor -lt $line.Length)
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::ForwardChar($key, $arg)
    }
    else
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptNextSuggestionWord($key, $arg)
    }
}

Set-PSReadLineKeyHandler -Key Alt+a `
    -BriefDescription SelectCommandArguments `
    -LongDescription "Set current selection to next command argument" `
    -ScriptBlock {
    param($key, $arg)

    $line = $null
    $cursor = 0
    $ast = $null
    $tokens = @()
    $parseErrors = @()

    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState(
        [ref]$line, [ref]$cursor,
        [ref]$ast, [ref]$tokens, [ref]$parseErrors
    )

    $asts = $ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.ExpressionAst] -and
            $args[0].Parent -is [System.Management.Automation.Language.CommandAst] -and
            $args[0].Extent.StartOffset -ne $args[0].Parent.Extent.StartOffset
        }, $true)

    if ($asts.Count -eq 0)
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::Ding()
        return
    }

    $nextAst = if ($null -ne $arg)
    {
        $asts[$arg - 1]
    }
    else
    {
        $found = $null
        foreach ($astItem in $asts)
        {
            if ($astItem.Extent.StartOffset -ge $cursor)
            {
                $found = $astItem
                break
            }
        }
        if ($null -eq $found)
        {
            $asts[0]
        }
        else
        {
            $found
        }
    }

    $startOffsetAdjustment = 0
    $endOffsetAdjustment = 0
    if ($nextAst -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
        $nextAst.StringConstantType -ne [System.Management.Automation.Language.StringConstantType]::BareWord)
    {
        $startOffsetAdjustment = 1
        $endOffsetAdjustment = 2
    }

    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($nextAst.Extent.StartOffset + $startOffsetAdjustment)
    [Microsoft.PowerShell.PSConsoleReadLine]::SetMark($null, $null)
    [Microsoft.PowerShell.PSConsoleReadLine]::SelectForwardChar($null, ($nextAst.Extent.EndOffset - $nextAst.Extent.StartOffset) - $endOffsetAdjustment)
}

Set-PSReadLineKeyHandler -Chord 'Alt+x' `
    -BriefDescription ToUnicodeChar `
    -LongDescription "Transform Unicode code point into a UTF-16 encoded string" `
    -ScriptBlock {
    $buffer = $null; $cursor = 0
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref] $buffer, [ref] $cursor)
    if ($cursor -lt 4)
    {
        return
    }

    $number = 0
    $isNumber = [int]::TryParse($buffer.Substring($cursor - 4, 4), [System.Globalization.NumberStyles]::AllowHexSpecifier, $null, [ref] $number)
    if (-not $isNumber)
    {
        return
    }

    try
    {
        $unicode = [char]::ConvertFromUtf32($number)
    }
    catch
    {
        return
    }

    [Microsoft.PowerShell.PSConsoleReadLine]::Delete($cursor - 4, 4)
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert($unicode)
}

Set-PSReadLineKeyHandler -Chord Shift+Enter -Function AddLine
Set-PSReadLineKeyHandler -Chord Ctrl+f -Function ForwardWord
Set-PSReadLineKeyHandler -Chord Enter -Function AcceptLine

# --- Argument Completers ---
Register-ArgumentCompleter -Native -CommandName 'git', 'npm', 'deno' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $completions = @{
        'git'  = @('status', 'add', 'commit', 'push', 'pull', 'clone', 'diff', 'log', 'checkout')
        'npm'  = @('install', 'start', 'run', 'test', 'build')
        'deno' = @('run', 'compile', 'bundle', 'test', 'lint', 'fmt', 'cache', 'doc', 'upgrade')
    }
    $command = $commandAst.CommandElements[0].Value.ToLower()
    if ($completions.ContainsKey($command))
    {
        $completions[$command] | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}

Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    if (Get-Command dotnet -ErrorAction SilentlyContinue)
    {
        dotnet Complete --position $cursorPosition $commandAst.ToString() | ForEach-Object {
            [CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}

# Windows-only completer
if ($IsWindows)
{
    Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        [Console]::InputEncoding = [Console]::OutputEncoding = $OutputEncoding = [System.Text.Encoding]::UTF8
        $Local:word = $wordToComplete.Replace('"', '""')
        $Local:ast = $commandAst.ToString().Replace('"', '""')
        winget complete --word="$Local:word" --commandline "$Local:ast" --position $cursorPosition | ForEach-Object {
            [CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}

# --- Dynamic Editor Logic ---
$editors = if ($IsWindows)
{
    @('code', 'nvim', 'vim', 'notepad++', 'notepad')
}
elseif ($IsMacOS)
{
    @('code', 'nvim', 'vim', 'nano')
}
else
{
    @('code', 'nvim', 'vim', 'nano')
}

$EDITOR = 'nano'  # Safe default for all platforms
foreach ($editor in $editors)
{
    if ($null -ne (Get-Command $editor -ErrorAction SilentlyContinue -CommandType Application))
    {
        $EDITOR = $editor
        break
    }
}

# --- Cross-Platform Open Function ---
function Open-Item
{
    param([string]$Path)

    if (-not (Test-Path $Path))
    {
        Write-Error "Path not found: $Path"
        return
    }

    if ($IsWindows)
    {
        Invoke-Item $Path
    }
    elseif ($IsMacOS)
    {
        open $Path
    }
    else
    {
        xdg-open $Path 2>/dev/null || Write-Host "Cannot open path. Please open manually."
    }
}

# --- Clean Aliases & Git Utilities ---
function Edit-Profile
{
    & $EDITOR $PROFILE
}

function Sync-Profile
{
    try
    {
        . $PROFILE
        Write-Output 'Profile reloaded successfully.'
    }
    catch
    {
        Write-Error $_
    }
}

function Get-GitWhoami
{
    if (Get-Command git -ErrorAction SilentlyContinue)
    {
        [PSCustomObject]@{
            Author = (git config --get user.name)
            Email  = (git config --get user.email)
        }
    }
}

function gcom
{
    param([string]$Message)
    if (Get-Command git -ErrorAction SilentlyContinue)
    {
        git add .
        git commit -m $Message
    }
}

function lazyg
{
    param([string]$Message)
    if (Get-Command git -ErrorAction SilentlyContinue)
    {
        git add .
        git commit -m $Message
        git push
    }
}

Set-Alias open Open-Item
Set-Alias edit $EDITOR
Set-Alias ep Edit-Profile
Set-Alias reload Sync-Profile
Set-Alias GWhoami Get-GitWhoami

# --- Directory Listing Functions ---
function ll
{
    Get-ChildItem @args | Format-Table -AutoSize
}

function la
{
    Get-ChildItem -Name @args
}

function lh
{
    Get-ChildItem @args | Format-Wide -AutoSize
}

function lv
{
    Get-ChildItem @args | Format-List
}

function lb
{
    Get-ChildItem @args | Out-Host
}
