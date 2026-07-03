<#
.SYNOPSIS
    Custom PowerShell 7+ Core Profile Configuration.
.DESCRIPTION
    Optimized terminal profile handling environment variables, fast registry drive
    mounting, deferred asynchronous module/engine maintenance updates, custom
    PSReadLine interactive configurations, and native command completions.
.NOTES
    File Path:   $PROFILE
    Author:      Carey Shupe
    Version:     2.1
    Engine:      PowerShell Core v7.0+ (Required)
    Dependencies:PSReadLine (v2.2.0+ preferred), Terminal-Icons, oh-my-posh
.LINK
    https://github.com/PowerShell/PSReadLine
#>

#requires -Version 7.0
using namespace System.Management.Automation
using namespace System.Management.Automation.Language
using namespace System.Diagnostics.CodeAnalysis

# --- Console & Host Behavior ---
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest

$GLOBAL_GitHubApiUrl = 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'
$PSDefaultParameterValues['Out-File:Encoding'] = 'UTF-8'

# Set window title quickly if not admin
if (-not [System.Security.Principal.WindowsPrincipal]::new([System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
{
    $Host.UI.RawUI.WindowTitle = "PowerShell (User)"
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
        }
    } -ThrottleLimit 3
}

function Update-PowerShell
{
    param ([string]$ApiUrl = $GLOBAL_GitHubApiUrl)

    if (-not (Test-Connection 'github.com' -Count 1 -Quiet -TimeoutSeconds 1))
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
        $packageManagers = @('winget', 'choco', 'scoop')
        foreach ($pm in $packageManagers)
        {
            if (Get-Command $pm -ErrorAction SilentlyContinue -CommandType Application)
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
                }
                break
            }
        }
    }
}

# --- Fast Mounting & Module Loading ---
foreach ($drive in @{"HKU" = "HKEY_USERS"; "HKCR" = "HKEY_CLASSES_ROOT"; "HKCC" = "HKEY_CURRENT_CONFIG" }.GetEnumerator())
{
    if (-not (Get-PSDrive -Name $drive.Key -ErrorAction SilentlyContinue))
    {
        New-PSDrive -Name $drive.Key -PSProvider Registry -Root $drive.Value | Out-Null
    }
}

# Direct imports
@('PSReadLine', 'Terminal-Icons') | ForEach-Object { Import-Module $_ -ErrorAction SilentlyContinue }

# --- Deferred Maintenance Gate (Non-blocking execution) ---
$lastCheck = Get-Content "$env:TEMP\ps_update_check.txt" -ErrorAction SilentlyContinue
if (-not $lastCheck -or ((Get-Date) - [datetime]$lastCheck).TotalHours -gt 24)
{
    # Run updates asynchronously; pass script global safely via argument
    Start-ThreadJob -ScriptBlock {
        param($Url)
        Update-Modules
        Update-PowerShell -ApiUrl $Url
        (Get-Date).ToString() | Set-Content "$env:TEMP\ps_update_check.txt"
    } -ArgumentList $GLOBAL_GitHubApiUrl | Out-Null
}

# --- Prompt Initialization ---
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue)
{
    oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\jandedobbeleer.omp.json" | Invoke-Expression
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

# Out-GridView History Search
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
            if (($line -cne $last) -and (!$pattern -or ($line -match $pattern)))
            {
                $last = $line
                $line
            }
        }
    )
    $history.Reverse()

    $command = $history | Out-GridView -Title History -PassThru
    if ($command)
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert(($command -join "`n"))
    }
}

# Quick Macro Build Example
Set-PSReadLineKeyHandler -Key Ctrl+b `
    -BriefDescription "BuildCurrentDirectory" `
    -LongDescription "Build the current directory" `
    -ScriptBlock {
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("msbuild")
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
Set-PSReadLineKeyHandler -Key Ctrl+q -Function TabCompleteNext
Set-PSReadLineKeyHandler -Key Ctrl+Q -Function TabCompletePrevious
Set-PSReadLineKeyHandler -Key Ctrl+C -Function Copy

# Clipboard Here-String Insertion
Set-PSReadLineKeyHandler -Key Ctrl+V `
    -BriefDescription PasteAsHereString `
    -LongDescription "Paste clipboard text as a PowerShell here-string" `
    -ScriptBlock {
    param($key, $arg)
    try
    {
        if (-not ('System.Windows.Clipboard' -as [type]))
        {
            Add-Type -AssemblyName PresentationCore
        }
        if ([System.Windows.Clipboard]::ContainsText())
        {
            $text = [System.Windows.Clipboard]::GetText()
            $text = ($text -replace '\r\n?', "`n").TrimEnd()
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert("@'`n$text`n'@")
        }
        else
        {
            [Microsoft.PowerShell.PSConsoleReadLine]::Ding()
        }
    }
    catch
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::Ding()
        Write-Warning "Clipboard paste failed: $_"
    }
}

Set-PSReadLineKeyHandler -Key 'Ctrl+d,Ctrl+c' -Function CaptureScreen
Set-PSReadLineKeyHandler -Key Alt+Backspace -Function ShellBackwardKillWord
Set-PSReadLineKeyHandler -Key Alt+b -Function ShellBackwardWord
Set-PSReadLineKeyHandler -Key Alt+f -Function ShellForwardWord
Set-PSReadLineKeyHandler -Key Alt+B -Function SelectShellBackwardWord
Set-PSReadLineKeyHandler -Key Alt+F -Function SelectShellForwardWord

# --- Smart Insert/Delete Handlers ---
Set-PSReadLineKeyHandler -Key '"', "'" `
    -BriefDescription SmartInsertQuote `
    -LongDescription "Insert paired quotes if not already on a quote" `
    -ScriptBlock {
    param($key, $arg)
    $quote = $key.KeyChar
    $selectionStart = $null; $selectionLength = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

    function Find-TokenAtCursor
    {
        param([System.Management.Automation.Language.Token[]]$Tokens, [int]$Cursor)
        if (-not $Tokens)
        {
            return $null
        }
        foreach ($token in $Tokens)
        {
            if ($Cursor -lt $token.Extent.StartOffset)
            {
                continue
            }
            if ($Cursor -lt $token.Extent.EndOffset)
            {
                if ($token -is [StringExpandableToken])
                {
                    $nested = Find-TokenAtCursor -Tokens $token.NestedTokens -Cursor $Cursor
                    if ($nested)
                    {
                        return $nested
                    }
                }
                return $token
            }
        }
        return $null
    }

    [string] $line = $null; [int] $cursor = 0
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    $ast = $null; $tokens = @(); $parseErrors = @(); $cursorForAst = 0
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$parseErrors, [ref]$cursorForAst)

    $token = Find-TokenAtCursor -Tokens $tokens -Cursor $cursor

    if ($token -is [StringToken] -and $token.Kind -ne [TokenKind]::Generic)
    {
        if ($token.Extent.StartOffset -eq $cursor)
        {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$quote$quote ")
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
            return
        }
        if ($token.Extent.EndOffset -eq ($cursor + 1) -and $line[$cursor] -eq $quote)
        {
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
            return
        }
    }

    if ($null -eq $token -or $token.Kind -eq [TokenKind]::RParen -or $token.Kind -eq [TokenKind]::RCurly -or $token.Kind -eq [TokenKind]::RBracket)
    {
        $quoteCount = if ([string]::IsNullOrEmpty($line) -or $cursor -le 0)
        {
            0
        }
        else
        {
            $safeLength = [Math]::Min($cursor, $line.Length)
            @($line.Substring(0, $safeLength).ToCharArray() | Where-Object { $_ -eq $quote }).Count
        }
        if ($quoteCount % 2 -eq 1)
        {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($quote)
        }
        else
        {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$quote$quote")
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
        }
        return
    }

    if ($token.Extent.StartOffset -eq $cursor)
    {
        if ($token.Kind -eq [TokenKind]::Generic -or $token.Kind -eq [TokenKind]::Identifier -or
            $token.Kind -eq [TokenKind]::Variable -or $token.TokenFlags.hasFlag([TokenFlags]::Keyword))
        {
            $end = $token.Extent.EndOffset; $len = $end - $cursor
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace($cursor, $len, $quote + $line.SubString($cursor, $len) + $quote)
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($end + 2)
            return
        }
    }
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert($quote)
}

Set-PSReadLineKeyHandler -Key '(', '{', '[' `
    -BriefDescription InsertPairedBraces `
    -LongDescription "Insert matching braces" `
    -ScriptBlock {
    param($key, $arg)
    $closeChar = switch ($key.KeyChar)
    {
        '('
        {
            [char]')'
        }
        '{'
        {
            [char]'}'
        }
        '['
        {
            [char]']'
        }
    }
    $selectionStart = $null; $selectionLength = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)
    $line = $null; $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    if ($selectionStart -ne -1)
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, $key.KeyChar + $line.SubString($selectionStart, $selectionLength) + $closeChar)
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
    }
    else
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)$closeChar")
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
    }
}

Set-PSReadLineKeyHandler -Key ')', ']', '}' `
    -BriefDescription SmartCloseBraces `
    -LongDescription "Insert closing brace or skip" `
    -ScriptBlock {
    param($key, $arg)
    $line = $null; $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    if ($line[$cursor] -eq $key.KeyChar)
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
    }
    else
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)")
    }
}

Set-PSReadLineKeyHandler -Key Backspace `
    -BriefDescription SmartBackspace `
    -LongDescription 'Delete matching pairs when between them' `
    -ScriptBlock {
    param($key, $arg)
    $line = $null; $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    if ($cursor -le 0 -or $cursor -ge $line.Length)
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::BackwardDeleteChar($key, $arg)
        return
    }

    $left = $line[$cursor - 1]; $right = $line[$cursor]
    $pairs = @{ '"' = '"'; "'" = "'"; '(' = ')'; '[' = ']'; '{' = '}' }

    if ($pairs.ContainsKey($left) -and $pairs[$left] -eq $right)
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::Delete($cursor - 1, 2)
        return
    }
    [Microsoft.PowerShell.PSConsoleReadLine]::BackwardDeleteChar($key, $arg)
}

# --- Advanced Line Manipulation ---
Set-PSReadLineKeyHandler -Key Alt+w `
    -BriefDescription SaveInHistory `
    -LongDescription "Save current line in history but do not execute" `
    -ScriptBlock {
    param($key, $arg)
    $line = $null; $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    [Microsoft.PowerShell.PSConsoleReadLine]::AddToHistory($line)
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
}

Set-PSReadLineKeyHandler -Key 'Alt+(' `
    -BriefDescription ParenthesizeSelection `
    -LongDescription "Put parenthesis around the selection or entire line and move the cursor to after the closing parenthesis" `
    -ScriptBlock {
    param($key, $arg)
    $selectionStart = $null; $selectionLength = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)
    $line = $null; $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    if ($selectionStart -ne -1)
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, '(' + $line.SubString($selectionStart, $selectionLength) + ')')
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
    }
    else
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, '(' + $line + ')')
        [Microsoft.PowerShell.PSConsoleReadLine]::EndOfLine()
    }
}

Set-PSReadLineKeyHandler -Key "Alt+'" `
    -BriefDescription ToggleQuoteArgument `
    -LongDescription "Toggle quotes on the argument under the cursor" `
    -ScriptBlock {
    param($key, $arg)
    [string] $line = $null; [int] $cursor = 0
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    $ast = $null; $tokens = @(); $parseErrors = @(); $cursorForAst = 0
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$parseErrors, [ref]$cursorForAst)

    $tokenToChange = $null
    foreach ($token in $tokens)
    {
        $extent = $token.Extent
        if ($extent.StartOffset -le $cursor -and $extent.EndOffset -ge $cursor)
        {
            $tokenToChange = $token; break
        }
    }

    if ($tokenToChange -ne $null)
    {
        $extent = $tokenToChange.Extent
        $tokenText = $extent.Text
        if ($tokenText.Length -ge 2 -and $tokenText[0] -eq '"' -and $tokenText[-1] -eq '"')
        {
            $replacement = $tokenText.Substring(1, $tokenText.Length - 2)
        }
        elseif ($tokenText.Length -ge 2 -and $tokenText[0] -eq "'" -and $tokenText[-1] -eq "'")
        {
            $replacement = '"' + $tokenText.Substring(1, $tokenText.Length - 2) + '"'
        }
        else
        {
            $replacement = "'" + $tokenText + "'"
        }
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($extent.StartOffset, $tokenText.Length, $replacement)
    }
}

Set-PSReadLineKeyHandler -Key "Alt+%" `
    -BriefDescription ExpandAliases `
    -LongDescription "Replace all aliases with the full command" `
    -ScriptBlock {
    param($key, $arg)
    [string] $line = $null; [int] $cursor = 0
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    $ast = $null; $tokens = @(); $parseErrors = @(); $cursorForAst = 0
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$parseErrors, [ref]$cursorForAst)

    $startAdjustment = 0
    foreach ($token in $tokens)
    {
        if ($token.TokenFlags -band [System.Management.Automation.Language.TokenFlags]::CommandName)
        {
            $alias = $ExecutionContext.InvokeCommand.GetCommand($token.Extent.Text, 'Alias')
            if ($alias -ne $null)
            {
                $resolvedCommand = $alias.ResolvedCommandName
                if ($resolvedCommand -ne $null)
                {
                    $extent = $token.Extent
                    $length = $extent.EndOffset - $extent.StartOffset
                    [Microsoft.PowerShell.PSConsoleReadLine]::Replace($extent.StartOffset + $startAdjustment, $length, $resolvedCommand)
                    $startAdjustment += ($resolvedCommand.Length - $length)
                }
            }
        }
    }
}

Set-PSReadLineKeyHandler -Key F1 `
    -BriefDescription CommandHelp `
    -LongDescription "Open the help window for the current command" `
    -ScriptBlock {
    param($key, $arg)
    [string] $line = $null; [int] $cursor = 0
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    $ast = $null; $tokens = @(); $parseErrors = @(); $cursorForAst = 0
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$parseErrors, [ref]$cursorForAst)

    $commandAst = $ast.FindAll( {
            $node = $args[0]
            $node -is [CommandAst] -and $node.Extent.StartOffset -le $cursor -and $node.Extent.EndOffset -ge $cursor
        }, $true) | Select-Object -Last 1

    if ($commandAst -ne $null)
    {
        $commandName = $commandAst.GetCommandName()
        if ($commandName -ne $null)
        {
            $command = $ExecutionContext.InvokeCommand.GetCommand($commandName, 'All')
            if ($command -is [AliasInfo])
            {
                $commandName = $command.ResolvedCommandName
            }
            if ($commandName -ne $null)
            {
                Get-Help $commandName -ShowWindow
            }
        }
    }
}

# --- Quick Directory Marks (Case Conflict Fixed) ---
$global:PSReadLineMarks = @{}

# Shift+J chords cleanly for marking
Set-PSReadLineKeyHandler -Key 'Ctrl+Shift+J' `
    -BriefDescription MarkDirectory `
    -LongDescription "Mark the current directory" `
    -ScriptBlock {
    param($key, $arg)
    $key = [Console]::ReadKey($true)
    $global:PSReadLineMarks[$key.KeyChar] = $pwd
}

Set-PSReadLineKeyHandler -Key Ctrl+j `
    -BriefDescription JumpDirectory `
    -LongDescription "Goto the marked directory" `
    -ScriptBlock {
    param($key, $arg)
    $key = [Console]::ReadKey()
    $dir = $global:PSReadLineMarks[$key.KeyChar]
    if ($dir)
    {
        Set-Location $dir
        [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
    }
}

Set-PSReadLineKeyHandler -Key Alt+j `
    -BriefDescription ShowDirectoryMarks `
    -LongDescription "Show the currently marked directories" `
    -ScriptBlock {
    param($key, $arg)
    $global:PSReadLineMarks.GetEnumerator() | ForEach-Object {
        [PSCustomObject]@{Key = $_.Key; Dir = $_.Value } } | Format-Table -AutoSize | Out-Host
    [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
}

# Git Validation Auto-Correction
Set-PSReadLineOption -CommandValidationHandler {
    param([CommandAst]$CommandAst)
    if ($CommandAst.GetCommandName() -ne 'git' -or $CommandAst.CommandElements.Count -lt 2)
    {
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
    [string] $line = $null; [int] $cursor = 0
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    $ast = $null; $tokens = @(); $parseErrors = @(); $cursorForAst = 0
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$parseErrors, [ref]$cursorForAst)

    $asts = $ast.FindAll( {
            $args[0] -is [ExpressionAst] -and $args[0].Parent -is [CommandAst] -and $args[0].Extent.StartOffset -ne $args[0].Parent.Extent.StartOffset
        }, $true)

    if ($asts.Count -eq 0)
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::Ding(); return
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
                $found = $astItem; break
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

    $startOffsetAdjustment = 0; $endOffsetAdjustment = 0
    if ($nextAst -is [StringConstantExpressionAst] -and $nextAst.StringConstantType -ne [StringConstantType]::BareWord)
    {
        $startOffsetAdjustment = 1; $endOffsetAdjustment = 2
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
# Fixed to standard 'AcceptLine' function handler execution framework
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
    dotnet Complete --position $cursorPosition $commandAst.ToString() | ForEach-Object {
        [CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    [Console]::InputEncoding = [Console]::OutputEncoding = $OutputEncoding = [System.Text.Encoding]::UTF8
    $Local:word = $wordToComplete.Replace('"', '""')
    $Local:ast = $commandAst.ToString().Replace('"', '""')
    winget complete --word="$Local:word" --commandline "$Local:ast" --position $cursorPosition | ForEach-Object {
        [CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

# --- Dynamic Editor Logic ---
$editors = @('nvim', 'pvim', 'vim', 'vi', 'code', 'notepad++', 'sublime_text', 'notepad')
$EDITOR = 'notepad'
foreach ($editor in $editors)
{
    if ($null -ne (Get-Command $editor -ErrorAction SilentlyContinue -CommandType Application))
    {
        $EDITOR = $editor; break
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
        . $PROFILE; Write-Output 'Profile reloaded successfully.'
    }
    catch
    {
        Write-Error $_
    }
}

function Get-GitWhoami
{
    [PSCustomObject]@{ Author = (git config --get user.name); Email = (git config --get user.email) }
}

function gcom
{
    param([string]$Message) git add .; git commit -m $Message
}
function lazyg
{
    param([string]$Message) git add .; git commit -m $Message; git push
}

Set-Alias open Invoke-Item
Set-Alias edit $EDITOR
Set-Alias ep Edit-Profile
Set-Alias reload Sync-Profile
Set-Alias GWhoami Get-GitWhoami

# Streamlined function properties to pass directly down the pipeline natively
function ll
{
    Get-ChildItem @args
}
function la
{
    Get-ChildItem -Name @args
}
function lb
{
    Get-ChildItem @args | Out-Host
}