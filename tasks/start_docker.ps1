# Starts both Tamza services through Docker Compose.
[CmdletBinding()]
param(
    [ValidateRange(10, 600)]
    [int]$DockerTimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$composeFile = Join-Path $PSScriptRoot '../docker-compose.yaml'

try {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker is not installed or is missing from PATH. Install Docker Desktop, then reopen PowerShell.'
    }
    if (-not (Test-Path -LiteralPath $composeFile)) {
        throw "Compose configuration not found: $composeFile"
    }

    & docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        $desktopCandidates = @(
            (Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe')
            (Join-Path $env:LOCALAPPDATA 'Docker\Docker Desktop.exe')
        )
        $desktop = $desktopCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($desktop) {
            Write-Host 'Starting Docker Desktop...'
            Start-Process -FilePath $desktop -WindowStyle Hidden
        } else {
            Write-Host 'Waiting for Docker. Start your Docker engine if it is not already starting.'
        }

        $deadline = (Get-Date).AddSeconds($DockerTimeoutSeconds)
        do {
            Start-Sleep -Seconds 2
            & docker info *> $null
            $dockerReady = $LASTEXITCODE -eq 0
        } until ($dockerReady -or (Get-Date) -ge $deadline)
        if (-not $dockerReady) {
            throw "Docker did not become ready within $DockerTimeoutSeconds seconds. Check Docker Desktop and try again."
        }
    }

    & docker compose version
    if ($LASTEXITCODE -ne 0) { throw 'Docker Compose v2 is required. Update Docker Desktop.' }

    $engineType = & docker info --format '{{.OSType}}'
    if ($LASTEXITCODE -ne 0) { throw 'Could not determine the Docker engine type.' }
    if ($engineType -ne 'linux') { throw 'Tamza needs Linux containers. Switch Docker Desktop to Linux containers.' }

    Write-Host 'Building and starting the frontend and backend...'
    & docker compose --project-name tamza --file $composeFile up --build --detach --wait --wait-timeout 120
    if ($LASTEXITCODE -ne 0) {
        throw 'Startup failed. Check Docker output above. Port 80 must be available. View logs with: docker compose -p tamza logs'
    }

    & docker compose --project-name tamza --file $composeFile ps
    if ($LASTEXITCODE -ne 0) { throw 'Could not read service status.' }
    Write-Host ''
    Write-Host 'Tamza is started.' -ForegroundColor Green
    Write-Host 'Frontend:         http://localhost/'
    Write-Host 'Backend API:      http://localhost/backend/api/Memo'
    Write-Host 'Backend test:     http://localhost/backend/api/Memo/test'
    Write-Host 'The backend is accessible through the frontend Nginx proxy.'
    Write-Host "Stop both services with: & `"$(Join-Path $PSScriptRoot 'stop_docker.ps1')`""
} catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}

