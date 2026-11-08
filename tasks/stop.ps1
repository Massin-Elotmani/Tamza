# Stops tracked local apps and the local database; preserves database data.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$stateFile = Join-Path $PSScriptRoot '.local/processes.json'
$composeFile = Join-Path $PSScriptRoot '../docker-compose.local.yaml'
try {
    if (Test-Path -LiteralPath $stateFile) {
        # Assign first so Windows PowerShell 5.1 enumerates JSON arrays per process.
        $entries = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
        foreach ($entry in $entries) {
            $process = Get-Process -Id $entry.Id -ErrorAction SilentlyContinue
            if ($process -and $process.StartTime.ToUniversalTime().ToString('o') -eq $entry.Started) {
                & taskkill /PID $entry.Id /T /F
                if ($LASTEXITCODE -ne 0 -and (Get-Process -Id $entry.Id -ErrorAction SilentlyContinue)) { throw "Could not stop process $($entry.Id)." }
            }
        }
        Remove-Item -LiteralPath $stateFile
    }
    & docker compose -p tamza-local -f $composeFile stop --timeout 30 db
    if ($LASTEXITCODE -ne 0) { throw 'Could not stop the database. Check Docker Desktop and retry.' }
    Write-Host 'Local apps and database stopped. Database data is preserved.'
} catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
