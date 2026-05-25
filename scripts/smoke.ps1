# Quick auth + /me smoke test against the running backend. Verifies the
# Spring Boot app is up, Flyway migrations ran, and the demo seed loaded.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\scripts\smoke.ps1
#   powershell -ExecutionPolicy Bypass -File .\scripts\smoke.ps1 -User layla

[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://localhost:8080',
    [string]$User    = 'fatima',
    [string]$Pass    = 'demo1234'
)

$ErrorActionPreference = 'Stop'

Write-Host "==> POST $BaseUrl/api/v1/auth/login  (user=$User)" -ForegroundColor Cyan
$loginBody = @{ username = $User; password = $Pass } | ConvertTo-Json
try {
    $login = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/v1/auth/login" `
        -ContentType 'application/json' -Body $loginBody
} catch {
    Write-Host "Login failed: $_" -ForegroundColor Red
    exit 1
}
$access = $login.tokens.accessToken
Write-Host "    access token: $($access.Substring(0,32))..." -ForegroundColor Green

Write-Host "==> GET  $BaseUrl/api/v1/me" -ForegroundColor Cyan
$me = Invoke-RestMethod -Uri "$BaseUrl/api/v1/me" `
    -Headers @{ Authorization = "Bearer $access" }
$me | ConvertTo-Json -Depth 6

Write-Host "==> GET  $BaseUrl/api/v1/trips?status=ACTIVE" -ForegroundColor Cyan
$trips = Invoke-RestMethod -Uri "$BaseUrl/api/v1/trips?status=ACTIVE" `
    -Headers @{ Authorization = "Bearer $access" }
Write-Host ("    {0} active trip(s)" -f @($trips).Count) -ForegroundColor Green
$trips | Select-Object id, name, currency, status | Format-Table
