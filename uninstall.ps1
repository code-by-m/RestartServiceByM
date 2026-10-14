$ErrorActionPreference = "Stop"
$serviceName = "ServisRestart"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting administrator approval..."
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    try {
        $process = Start-Process `
            -FilePath (Join-Path $PSHOME "powershell.exe") `
            -Verb RunAs `
            -ArgumentList $arguments `
            -Wait `
            -PassThru
        exit $process.ExitCode
    }
    catch [System.ComponentModel.Win32Exception] {
        if ($_.Exception.NativeErrorCode -eq 1223) {
            Write-Host "Administrator approval was cancelled."
            exit 1223
        }

        throw
    }
}

trap {
    Write-Host "Uninstallation error: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.InvocationInfo.PositionMessage) {
        Write-Host $_.InvocationInfo.PositionMessage -ForegroundColor DarkRed
    }
    if ($env:CODEBYM_UNINSTALLER_PAUSE -eq "1") {
        Read-Host "Press Enter to return to the uninstaller window" | Out-Null
    }
    exit 1
}

function Invoke-ScCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & "$env:SystemRoot\System32\sc.exe" @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "sc.exe $($Arguments -join ' ') failed with exit code ${exitCode}: $output"
    }
}

function Get-ExistingService {
    try {
        return Get-Service -Name $serviceName -ErrorAction Stop
    }
    catch [Microsoft.PowerShell.Commands.ServiceCommandException] {
        if ($_.FullyQualifiedErrorId -like "NoServiceFoundForGivenName*") {
            return $null
        }

        throw
    }
}

$service = Get-ExistingService
if ($null -eq $service) {
    Write-Host "$serviceName is not installed."
    return
}

if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
    Stop-Service -Name $serviceName -ErrorAction Stop
    $service = Get-Service -Name $serviceName -ErrorAction Stop
    $service.WaitForStatus(
        [System.ServiceProcess.ServiceControllerStatus]::Stopped,
        [TimeSpan]::FromSeconds(60))
}

Invoke-ScCommand @("delete", $serviceName)

$deadline = [DateTime]::UtcNow.AddSeconds(60)
do {
    Start-Sleep -Milliseconds 500
    $service = Get-ExistingService
    if ($null -eq $service) {
        Write-Host "$serviceName was stopped and removed."
        return
    }
} while ([DateTime]::UtcNow -lt $deadline)

throw "Service deletion was accepted but $serviceName is still registered. Close service handles and retry."
