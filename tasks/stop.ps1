# Stops both Tamza services, preserving containers and their recorded audio.
[CmdletBinding()]
param()

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
        throw 'Docker is not reachable. Open Docker Desktop and retry so the Tamza containers can be stopped.'
    }
    & docker compose version
    if ($LASTEXITCODE -ne 0) { throw 'Docker Compose v2 is required. Update Docker Desktop.' }

    Write-Host 'Stopping the frontend and backend...'
    & docker compose --project-name tamza --file $composeFile stop --timeout 30
    if ($LASTEXITCODE -ne 0) { throw 'Could not stop Tamza. Check Docker output above.' }
    Write-Host 'Both Tamza services are stopped. Docker Desktop is left running.'
} catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
