# Runs the apps locally and PostgreSQL in Docker. Requires .NET 9 and Node/npm.
[CmdletBinding()]
param(
    [ValidateRange(1024, 65515)]
    [int]$FrontendPort = 5173
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$stateDir = Join-Path $PSScriptRoot '.local'
$stateFile = Join-Path $stateDir 'processes.json'
$composeFile = Join-Path $root 'docker-compose.local.yaml'
$started = @()
$dbStarted = $false

try {
    foreach ($command in @('docker', 'dotnet', 'npm.cmd', 'node')) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Required command missing: $command" }
    }
    if (Test-Path -LiteralPath $stateFile) { throw 'Local startup state exists. Run tasks/stop.ps1 before starting again.' }
    # Read listeners through .NET so port checks also work without elevated CIM access.
    $listeners = @([System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners() | ForEach-Object { $_.Port })
    if ($listeners -contains 5049) { throw 'Backend port 5049 is already in use. Stop the existing backend first (tasks/stop.ps1 for a script-managed instance).' }
    $requestedPort = $FrontendPort
    while ($listeners -contains $FrontendPort) {
        $FrontendPort++
        if ($FrontendPort -gt ($requestedPort + 20)) { throw "No available frontend port between $requestedPort and $($requestedPort + 20)." }
    }
    if ($FrontendPort -ne $requestedPort) {
        Write-Host "Frontend port $requestedPort is in use; using http://localhost:$FrontendPort instead."
    }
    & docker info *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Start Docker Desktop and retry.' }
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    $frontend = Join-Path $root 'TamzaFrontend'
    if (-not (Test-Path -LiteralPath (Join-Path $frontend 'node_modules/vite/bin/vite.js'))) {
        Push-Location $frontend
        try {
            # npm.cmd may prefer an outdated user-installed npm over Node's bundled copy.
            $bundledNpm = Join-Path (Split-Path (Get-Command node).Source -Parent) 'node_modules/npm/bin/npm-cli.js'
            if (Test-Path -LiteralPath $bundledNpm) {
                & node $bundledNpm install
            } else {
                & npm.cmd install
            }
            if ($LASTEXITCODE -ne 0) { throw 'Frontend dependency installation failed.' }
        } finally { Pop-Location }
    }
    & dotnet build (Join-Path $root 'TamzaBackend/TamzaBackend.csproj')
    if ($LASTEXITCODE -ne 0) { throw 'Backend build failed.' }
    & docker compose -p tamza-local -f $composeFile up -d --wait --wait-timeout 120 db
    $dbStarted = $true
    if ($LASTEXITCODE -ne 0) { throw 'Database startup failed.' }

    # Environment is inherited by the backend; restore the caller environment afterwards.
    $oldEnvironment = $env:ASPNETCORE_ENVIRONMENT
    $oldConnection = $env:ConnectionStrings__DefaultConnection
    try {
        $env:ASPNETCORE_ENVIRONMENT = 'Development'
        $env:ConnectionStrings__DefaultConnection = 'Host=localhost;Port=5432;Database=tamza;Username=tamza;Password=tamza_local'
        $backend = Start-Process dotnet -ArgumentList 'run --no-build --no-launch-profile --urls http://localhost:5049' -WorkingDirectory (Join-Path $root 'TamzaBackend') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $stateDir 'backend.log') -RedirectStandardError (Join-Path $stateDir 'backend.error.log')
        $started += @{ Id = $backend.Id; Started = $backend.StartTime.ToUniversalTime().ToString('o') }
        $started | ConvertTo-Json | Set-Content -LiteralPath $stateFile
    } finally {
        $env:ASPNETCORE_ENVIRONMENT = $oldEnvironment
        $env:ConnectionStrings__DefaultConnection = $oldConnection
    }
    $vite = Start-Process node -ArgumentList "node_modules/vite/bin/vite.js --host localhost --port $FrontendPort --strictPort" -WorkingDirectory $frontend -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $stateDir 'frontend.log') -RedirectStandardError (Join-Path $stateDir 'frontend.error.log')
    $started += @{ Id = $vite.Id; Started = $vite.StartTime.ToUniversalTime().ToString('o') }
    $started | ConvertTo-Json | Set-Content -LiteralPath $stateFile
    $deadline = (Get-Date).AddSeconds(60)
    foreach ($url in @('http://localhost:5049/swagger/index.html', "http://localhost:$FrontendPort")) {
        do {
            foreach ($entry in $started) {
                if (-not (Get-Process -Id $entry.Id -ErrorAction SilentlyContinue)) { throw "An app exited. Check logs in $stateDir" }
            }
            try { $null = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 2; break } catch {
                if ((Get-Date) -ge $deadline) { throw "Startup timed out at $url. Check logs in $stateDir" }
                Start-Sleep -Seconds 1
            }
        } while ($true)
    }
    Write-Host "Frontend: http://localhost:$FrontendPort"
    Write-Host 'Backend:  http://localhost:5049/swagger'
    Write-Host "Logs: $stateDir"
    Write-Host 'Stop with: ./tasks/stop.ps1'
} catch {
    $startupFailure = $_
    foreach ($logName in @('backend.error.log', 'frontend.error.log')) {
        $logPath = Join-Path $stateDir $logName
        if (Test-Path -LiteralPath $logPath) {
            $details = Get-Content -LiteralPath $logPath -Tail 20
            if ($details) { Write-Host "${logName}:`n$($details -join "`n")" -ForegroundColor Red }
        }
    }
    if ($started.Count -gt 0 -or $dbStarted) { & (Join-Path $PSScriptRoot 'stop.ps1') }
    Write-Error $startupFailure -ErrorAction Continue
    exit 1
}
