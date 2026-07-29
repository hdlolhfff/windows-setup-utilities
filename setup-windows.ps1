[CmdletBinding()]
param([switch]$SkipWinUtil)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)

    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Get-GitHubRelease {
    param([Parameter(Mandatory)][string]$Repository)

    Invoke-RestMethod `
        -Uri "https://api.github.com/repos/$Repository/releases/latest" `
        -Headers @{ Accept = 'application/vnd.github+json'; 'User-Agent' = 'Windows-Setup-Script' }
}

function Save-ReleaseAsset {
    param(
        [Parameter(Mandatory)]$Asset,
        [Parameter(Mandatory)][string]$Destination
    )

    Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $Destination -UseBasicParsing

    if ($Asset.digest -match '^sha256:([0-9a-fA-F]{64})$') {
        $expectedHash = $Matches[1]
        $actualHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
        if ($actualHash -ne $expectedHash) {
            Remove-Item -LiteralPath $Destination -Force
            throw "SHA-256 verification failed for $($Asset.name)."
        }
    }
}

# Relaunch the whole setup through UAC when it was not started as administrator.
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-File', ('"{0}"' -f $PSCommandPath)
    )
    $elevatedProcess = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -Wait -PassThru
    exit $elevatedProcess.ExitCode
}

if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'This setup requires 64-bit Windows.'
}

$logDirectory = Join-Path $env:ProgramData 'WindowsSetup\Logs'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$logPath = Join-Path $logDirectory ("Windows-Setup-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
Start-Transcript -LiteralPath $logPath -Force | Out-Null
Write-Host "Log file: $logPath" -ForegroundColor DarkGray

$workDirectory = Join-Path $env:TEMP 'WindowsProvisioning'
if (Test-Path -LiteralPath $workDirectory) {
    Remove-Item -LiteralPath $workDirectory -Recurse -Force
}
New-Item -ItemType Directory -Path $workDirectory | Out-Null

try {
    if ($SkipWinUtil) {
        Write-Step 'Skipping WinUtil because the Standard preset already completed'
    }
    else {
        Write-Step 'Applying the WinUtil Standard preset without Disk Cleanup'
        $winUtilPath = Join-Path $workDirectory 'winutil.ps1'
        $winUtilConfigPath = Join-Path $workDirectory 'winutil-standard-no-disk-cleanup.json'
        Invoke-WebRequest -Uri 'https://christitus.com/win' -OutFile $winUtilPath -UseBasicParsing
        $standardTweaks = (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/ChrisTitusTech/winutil/main/config/preset.json').Standard |
            Where-Object { $_ -ne 'WPFTweaksDiskCleanup' }
        if (-not $standardTweaks -or $standardTweaks -contains 'WPFTweaksDiskCleanup') {
            throw 'Could not create the WinUtil Standard configuration without Disk Cleanup.'
        }
        [IO.File]::WriteAllText($winUtilConfigPath, ($standardTweaks | ConvertTo-Json), [Text.Encoding]::UTF8)
        $escapedWinUtilPath = $winUtilPath.Replace("'", "''")
        $escapedWinUtilConfigPath = $winUtilConfigPath.Replace("'", "''")
        $winUtilCommand = "& ([ScriptBlock]::Create([IO.File]::ReadAllText('$escapedWinUtilPath'))) -Config '$escapedWinUtilConfigPath'"
        $encodedWinUtilCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($winUtilCommand))
        $previousErrorPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedWinUtilCommand
        $winUtilExitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousErrorPreference
        if ($winUtilExitCode -ne 0) {
            throw "WinUtil Standard preset failed (exit code $winUtilExitCode)."
        }
        New-Item -ItemType Directory -Path $workDirectory -Force | Out-Null
    }

    Write-Step 'Checking Winget'
    if (-not (Get-Command 'winget.exe' -ErrorAction SilentlyContinue)) {
        throw 'Winget was not found. Install or update App Installer from Microsoft Store, then run this setup again.'
    }

    $wingetPackages = @(
        @{ Name = 'WinDirStat'; Id = 'WinDirStat.WinDirStat' }
        @{ Name = '7-Zip'; Id = '7zip.7zip' }
    )

    foreach ($package in $wingetPackages) {
        $previousErrorPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & winget.exe list --id $package.Id --exact --accept-source-agreements --disable-interactivity | Out-Host
        $wingetListExitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousErrorPreference
        if ($wingetListExitCode -eq 0) {
            Write-Step "$($package.Name) is already installed"
            continue
        }

        Write-Step "Installing $($package.Name)"
        & winget.exe install `
            --id $package.Id `
            --exact `
            --silent `
            --accept-package-agreements `
            --accept-source-agreements `
            --disable-interactivity
        if ($LASTEXITCODE -ne 0) {
            throw "Winget failed to install $($package.Name) (exit code $LASTEXITCODE)."
        }
    }

    Write-Step 'Installing the latest Blur AutoClicker release'
    $blurRelease = Get-GitHubRelease -Repository 'Blur009/Blur-AutoClicker'
    $blurAsset = $blurRelease.assets |
        Where-Object { $_.name -match '(?i)x64.*setup\.exe$' } |
        Select-Object -First 1
    if (-not $blurAsset) {
        throw 'The latest Blur AutoClicker release has no x64 setup executable.'
    }

    $blurInstaller = Join-Path $workDirectory $blurAsset.name
    Save-ReleaseAsset -Asset $blurAsset -Destination $blurInstaller
    $blurProcess = Start-Process -FilePath $blurInstaller -ArgumentList '/S' -Wait -PassThru
    if ($blurProcess.ExitCode -ne 0) {
        throw "Blur AutoClicker setup failed (exit code $($blurProcess.ExitCode))."
    }

    Write-Step 'Downloading the latest FluentTweaker release'
    $fluentRelease = Get-GitHubRelease -Repository 'builtbybel/FluentTweaker'
    $fluentAsset = $fluentRelease.assets |
        Where-Object { $_.name -match '(?i)win-x64\.zip$' } |
        Select-Object -First 1
    if (-not $fluentAsset) {
        throw 'The latest FluentTweaker release has no Windows x64 archive.'
    }

    $fluentArchive = Join-Path $workDirectory $fluentAsset.name
    $fluentDirectory = Join-Path $env:LOCALAPPDATA 'Programs\FluentTweaker'
    Save-ReleaseAsset -Asset $fluentAsset -Destination $fluentArchive
    if (Test-Path -LiteralPath $fluentDirectory) {
        Remove-Item -LiteralPath $fluentDirectory -Recurse -Force
    }
    New-Item -ItemType Directory -Path $fluentDirectory | Out-Null
    Expand-Archive -LiteralPath $fluentArchive -DestinationPath $fluentDirectory -Force

    $fluentExecutable = Get-ChildItem -LiteralPath $fluentDirectory -Filter '*.exe' -File -Recurse |
        Where-Object { $_.Name -match '(?i)^(FluentTweaker|FTweaker|Winslopr)\.exe$' } |
        Select-Object -First 1
    if (-not $fluentExecutable) {
        throw "Could not find the FluentTweaker executable in $fluentDirectory."
    }

    Write-Step 'Launching FluentTweaker as administrator'
    Write-Host 'Setup will continue after FluentTweaker is closed.' -ForegroundColor DarkGray
    Start-Process -FilePath $fluentExecutable.FullName -WorkingDirectory $fluentExecutable.DirectoryName -Verb RunAs -Wait

    Write-Step 'Opening Task Manager on the Startup apps tab'
    Start-Process -FilePath (Join-Path $env:WINDIR 'System32\Taskmgr.exe') -ArgumentList '/0', '/startup'

    Write-Host "`nSetup completed successfully. FluentTweaker is installed at:`n$fluentDirectory" -ForegroundColor Green
    Write-Host "`nChoose what to do next:" -ForegroundColor Cyan
    Write-Host '1. Do not restart (NOT recommended)'
    Write-Host '2. Restart in 5 seconds (Recommended)'

    do {
        $restartChoice = Read-Host 'Select 1 or 2 [2]'
        if ([string]::IsNullOrWhiteSpace($restartChoice)) {
            $restartChoice = '2'
        }
    } until ($restartChoice -in '1', '2')

    if ($restartChoice -eq '1') {
        Write-Host 'Restart skipped. Restart Windows later to finish applying the changes.' -ForegroundColor Yellow
    }
    else {
        Write-Host 'Windows will restart in 5 seconds. Save any open work now.' -ForegroundColor Yellow
        & shutdown.exe /r /t 5 /d p:2:4 /c 'Restarting to finish Windows setup.'
        if ($LASTEXITCODE -ne 0) {
            throw "Could not schedule the restart (exit code $LASTEXITCODE)."
        }
    }
}
catch {
    Write-Error $_
    exit 1
}
finally {
    if (Test-Path -LiteralPath $workDirectory) {
        Remove-Item -LiteralPath $workDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
}
