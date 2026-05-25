# Stops the docker compose stack (Postgres + MinIO). Backend and Flutter run in
# their own windows — close those manually or Ctrl+C inside them.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\scripts\dev-down.ps1
#
# Flags:
#   -Volumes    also delete pdd_postgres_data and pdd_minio_data (DESTRUCTIVE)

[CmdletBinding()]
param(
    [switch]$Volumes
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Compose  = "$RepoRoot\ops\docker-compose.yml"

if ($Volumes) {
    Write-Host "==> docker compose down -v  (volumes will be deleted)" -ForegroundColor Yellow
    docker compose -f $Compose down -v
} else {
    Write-Host "==> docker compose down" -ForegroundColor Cyan
    docker compose -f $Compose down
}
