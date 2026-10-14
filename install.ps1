param(
    [string]$PackagePath = $(if (Test-Path -LiteralPath (Join-Path $PSScriptRoot "runtime") -PathType Container) {
            $PSScriptRoot
        }
        else {
            Split-Path -Parent $PSScriptRoot
        })
)

$ErrorActionPreference = "Stop"
$serviceName = "RestartService"
$displayName = "RestartService"
$serviceDescription = "Yapilandirmada belirtilen Windows servislerini belirlenen araliklarla izler; durmalari halinde yeniden baslatir ve istege bagli olarak planli restart uygular."
$installRoot = Join-Path $env:ProgramFiles "RestartServiceByM"
$PackagePath = [System.IO.Path]::GetFullPath($PackagePath)
$packagePathRoot = [System.IO.Path]::GetPathRoot($PackagePath)
if ($PackagePath.Length -gt $packagePathRoot.Length) {
    $PackagePath = $PackagePath.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
}
$runtimeSource = Join-Path $PackagePath "runtime"
$configurationSource = Join-Path $PackagePath "appsettings.json"
$currentStep = "initialization"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting administrator approval..."
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' +
        $PSCommandPath + '" -PackagePath "' + $PackagePath + '"'
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
    Write-Host "Installation error during '$currentStep': $($_.Exception.Message)" -ForegroundColor Red
    if ($_.InvocationInfo.PositionMessage) {
        Write-Host $_.InvocationInfo.PositionMessage -ForegroundColor DarkRed
    }
    if ($env:CODEBYM_INSTALLER_PAUSE -eq "1") {
        Read-Host "Press Enter to return to the installer window" | Out-Null
    }
    exit 1
}

$currentStep = "package validation"
if (-not (Test-Path -LiteralPath (Join-Path $runtimeSource "ServiceRestart.exe") -PathType Leaf)) {
    throw "runtime\ServiceRestart.exe was not found in package directory: $PackagePath"
}
if (-not (Test-Path -LiteralPath $configurationSource -PathType Leaf)) {
    throw "appsettings.json was not found in package directory: $PackagePath"
}

Get-Content -LiteralPath $configurationSource -Raw -ErrorAction Stop |
    ConvertFrom-Json -ErrorAction Stop |
    Out-Null
$developmentConfiguration = Join-Path $PackagePath "appsettings.Development.json"
if (Test-Path -LiteralPath $developmentConfiguration -PathType Leaf) {
    Get-Content -LiteralPath $developmentConfiguration -Raw -ErrorAction Stop |
        ConvertFrom-Json -ErrorAction Stop |
        Out-Null
}

function Test-DirectoryIsProtected {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DirectoryPath
    )

    if (-not (Test-Path -LiteralPath $DirectoryPath -PathType Container)) {
        New-Item -ItemType Directory -Path $DirectoryPath -Force | Out-Null
    }

    $resolved = [System.IO.Path]::GetFullPath($DirectoryPath).TrimEnd('\')
    $programFilesPath = [System.IO.Path]::GetFullPath($env:ProgramFiles).TrimEnd('\')
    if (-not $resolved.StartsWith(
            "$programFilesPath\",
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Install directory must be under '$programFilesPath'. Path '$resolved' is not permitted."
    }

    $acl = Get-Acl -LiteralPath $resolved
    foreach ($access in $acl.Access) {
        if (Test-IsUntrustedPrincipal -IdentityReference $access.IdentityReference) {
            $writeRights = [System.Security.AccessControl.FileSystemRights]::WriteData `
                -bor [System.Security.AccessControl.FileSystemRights]::AppendData `
                -bor [System.Security.AccessControl.FileSystemRights]::WriteAttributes `
                -bor [System.Security.AccessControl.FileSystemRights]::WriteExtendedAttributes `
                -bor [System.Security.AccessControl.FileSystemRights]::CreateFiles `
                -bor [System.Security.AccessControl.FileSystemRights]::CreateDirectories `
                -bor [System.Security.AccessControl.FileSystemRights]::Delete `
                -bor [System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles `
                -bor [System.Security.AccessControl.FileSystemRights]::ChangePermissions `
                -bor [System.Security.AccessControl.FileSystemRights]::TakeOwnership
            if (($access.FileSystemRights -band $writeRights) -ne 0) {
                throw "Install directory '$resolved' is writable by $($access.IdentityReference.Value)."
            }
        }
    }
}

function Test-IsUntrustedPrincipal {
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.Principal.IdentityReference]$IdentityReference
    )

    try {
        $sid = $IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value
        return $sid -in @('S-1-5-32-545', 'S-1-5-11', 'S-1-1-0')
    }
    catch [System.Security.Principal.IdentityNotMappedException] {
        return $IdentityReference.Value -in @('Users', 'Authenticated Users', 'Everyone')
    }
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

$currentStep = "installation directory validation and ACL check"
Test-DirectoryIsProtected -DirectoryPath $installRoot
$runtimeDestination = Join-Path $installRoot "runtime"
Test-DirectoryIsProtected -DirectoryPath $runtimeDestination
$logsDirectory = Join-Path $installRoot "logs"
if (-not (Test-Path -LiteralPath $logsDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $logsDirectory -Force | Out-Null
}
$logsAcl = Get-Acl -LiteralPath $logsDirectory
$localServiceAccount = [System.Security.Principal.NTAccount]::new('NT AUTHORITY\LOCAL SERVICE')
$logsAcl.PurgeAccessRules($localServiceAccount)
$logsRule = [System.Security.AccessControl.FileSystemAccessRule]::new(
    'NT AUTHORITY\SYSTEM',
    [System.Security.AccessControl.FileSystemRights]::Modify,
    [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
        [System.Security.AccessControl.InheritanceFlags]::ObjectInherit,
    [System.Security.AccessControl.PropagationFlags]::None,
    [System.Security.AccessControl.AccessControlType]::Allow)
$logsAcl.SetAccessRule($logsRule)
Set-Acl -LiteralPath $logsDirectory -AclObject $logsAcl

$currentStep = "existing service shutdown"
$existingService = Get-ExistingService
if ($null -ne $existingService -and
    $existingService.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
    Stop-Service -Name $serviceName -ErrorAction Stop
    $existingService = Get-Service -Name $serviceName -ErrorAction Stop
    $existingService.WaitForStatus(
        [System.ServiceProcess.ServiceControllerStatus]::Stopped,
        [TimeSpan]::FromSeconds(60))
}

$currentStep = "runtime files copy"
Copy-Item -Path (Join-Path $runtimeSource '*') -Destination $runtimeDestination -Recurse -Force
$installedConfiguration = Join-Path $installRoot "appsettings.json"
$currentStep = "configuration install"
if (-not (Test-Path -LiteralPath $installedConfiguration -PathType Leaf)) {
    Copy-Item -LiteralPath $configurationSource -Destination $installedConfiguration
}
else {
    Write-Warning "Keeping existing configuration '$installedConfiguration'; review it manually for package updates."
}

$installedDevelopmentConfiguration = Join-Path $installRoot "appsettings.Development.json"
if ((Test-Path -LiteralPath $developmentConfiguration -PathType Leaf) -and
    -not (Test-Path -LiteralPath $installedDevelopmentConfiguration -PathType Leaf)) {
    Copy-Item -LiteralPath $developmentConfiguration -Destination $installedDevelopmentConfiguration
}

$executablePath = Join-Path $runtimeDestination "ServiceRestart.exe"
$configurationPath = Join-Path $installRoot "appsettings.json"
$currentStep = "installed file ACL check"
$filesToProtect = @($executablePath, $configurationPath)
if (Test-Path -LiteralPath $installedDevelopmentConfiguration -PathType Leaf) {
    $filesToProtect += $installedDevelopmentConfiguration
}
foreach ($filePath in $filesToProtect) {
    $fileAcl = Get-Acl -LiteralPath $filePath
    foreach ($access in $fileAcl.Access) {
        if (Test-IsUntrustedPrincipal -IdentityReference $access.IdentityReference) {
            $writeRights = [System.Security.AccessControl.FileSystemRights]::WriteData `
                -bor [System.Security.AccessControl.FileSystemRights]::AppendData `
                -bor [System.Security.AccessControl.FileSystemRights]::WriteAttributes `
                -bor [System.Security.AccessControl.FileSystemRights]::WriteExtendedAttributes `
                -bor [System.Security.AccessControl.FileSystemRights]::CreateFiles `
                -bor [System.Security.AccessControl.FileSystemRights]::CreateDirectories `
                -bor [System.Security.AccessControl.FileSystemRights]::Delete `
                -bor [System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles `
                -bor [System.Security.AccessControl.FileSystemRights]::ChangePermissions `
                -bor [System.Security.AccessControl.FileSystemRights]::TakeOwnership
            if (($access.FileSystemRights -band $writeRights) -ne 0) {
                throw "Installed file '$filePath' is writable by $($access.IdentityReference.Value)."
            }
        }
    }
}

$existingService = Get-ExistingService
$currentStep = "Windows Service registration"
if ($null -ne $existingService) {
    Invoke-ScCommand @(
        "config",
        $serviceName,
        "binPath=",
        "`"$executablePath`"",
        "obj=",
        "LocalSystem"
    )
}
else {
    Invoke-ScCommand @(
        "create",
        $serviceName,
        "binPath=",
        "`"$executablePath`"",
        "obj=",
        "LocalSystem",
        "start=",
        "auto",
        "DisplayName=",
        $displayName
    )
}

Invoke-ScCommand @("config", $serviceName, "start=", "delayed-auto")
Invoke-ScCommand @("config", $serviceName, "DisplayName=", $displayName)
Invoke-ScCommand @("description", $serviceName, $serviceDescription)
Invoke-ScCommand @(
    "failure",
    $serviceName,
    "reset=",
    "0",
    "actions=",
    "restart/60000/restart/60000/restart/60000"
)
Invoke-ScCommand @("failureflag", $serviceName, "1")

$currentStep = "service start and status verification"
Start-Service -Name $serviceName -ErrorAction Stop
$service = Get-Service -Name $serviceName -ErrorAction Stop
$service.WaitForStatus(
    [System.ServiceProcess.ServiceControllerStatus]::Running,
    [TimeSpan]::FromSeconds(60))

Write-Host "$displayName installed/updated from '$PackagePath' to '$installRoot' under LocalSystem."
