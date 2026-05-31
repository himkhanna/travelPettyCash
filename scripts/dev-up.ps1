# Brings up the full local dev stack for PDD Delegation Expenses.
#
#   1. Postgres + MinIO via ops/docker-compose.yml (background)
#   2. Spring Boot backend in a new PowerShell window (profile=local, seeds demo data)
#   3. Flutter Web app in a new PowerShell window on http://localhost:5173
#
# Usage (from repo root or anywhere):
#   powershell -ExecutionPolicy Bypass -File .\scripts\dev-up.ps1
#
# Flags:
#   -SkipDocker     don't touch docker compose (assume it's already up)
#   -SkipBackend    don't spawn the backend window
#   -SkipMobile     don't spawn the Flutter window
#   -FakeBackend    launch Flutter with --dart-define=PDD_BACKEND=fake (no API needed)

[CmdletBinding()]
param(
    [switch]$SkipDocker,
    [switch]$SkipBackend,
    [switch]$SkipMobile,
    [switch]$FakeBackend,
    [switch]$WebServer  # use -d web-server instead of -d chrome (avoids
                        # the DWDS-to-Chrome attach failure when a previous
                        # session left a stale Chrome window around)
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

# Spawned PowerShell windows don't always inherit User PATH (depends on how the
# parent process was launched). Force-refresh PATH from the registry in every
# spawned window so flutter / gradle / docker resolve consistently.
$RefreshPath = '$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User");'

# Helper: spawn a new PowerShell window running $cmd. Uses -EncodedCommand to
# bypass the inner-quote-stripping that Start-Process does when passing -Command
# through CreateProcess.
function Start-DevWindow([string]$cmd) {
    $bytes   = [System.Text.Encoding]::Unicode.GetBytes($cmd)
    $encoded = [Convert]::ToBase64String($bytes)
    Start-Process powershell -ArgumentList '-NoExit', '-EncodedCommand', $encoded | Out-Null
}

Write-Host "==> Repo root: $RepoRoot" -ForegroundColor Cyan

# --- 1. Docker stack ----------------------------------------------------------
if (-not $SkipDocker) {
    Write-Host "==> Starting Postgres + MinIO (docker compose)" -ForegroundColor Cyan
    docker compose -f "$RepoRoot\ops\docker-compose.yml" up -d
    if ($LASTEXITCODE -ne 0) {
        Write-Host "docker compose failed. Is Docker Desktop running?" -ForegroundColor Red
        exit 1
    }
    Write-Host "    Postgres : localhost:5432  (db=pdd_petty_cash user=pdd pass=pdd)"
    Write-Host "    MinIO S3 : localhost:9100  (console: http://localhost:9101  pdd / pdd-minio-secret)"
}

# --- 2. Backend (Spring Boot) -------------------------------------------------
if (-not $SkipBackend) {
    Write-Host "==> Spawning backend window (gradle bootRun, profile=local)" -ForegroundColor Cyan
    # Load backend/.env into the spawned window's environment so the JVM
    # picks up secrets like PDD_SMARTDUBAI_CLIENT_SECRET without ever
    # committing them. Lines of the form KEY=VALUE are exported; blank
    # lines and # comments are ignored. backend/.env is gitignored.
    $loadEnv = @"
`$envFile = '$RepoRoot\backend\.env'
if (Test-Path `$envFile) {
    Get-Content `$envFile | ForEach-Object {
        if (`$_ -match '^\s*#') { return }
        if (`$_ -match '^\s*$') { return }
        if (`$_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            `$k = `$matches[1]
            `$v = `$matches[2].Trim('"').Trim("'")
            Set-Item -Path "Env:`$k" -Value `$v
        }
    }
    Write-Host '    (loaded backend/.env)' -ForegroundColor DarkGray
}
"@
    $backendCmd = $RefreshPath + $loadEnv +
                  "Set-Location '$RepoRoot\backend'; " +
                  "Write-Host 'PDD backend - Ctrl+C to stop' -ForegroundColor Green; " +
                  "if (-not (Get-Command gradle -ErrorAction SilentlyContinue)) { Write-Host 'ERROR: gradle not on PATH' -ForegroundColor Red; return }; " +
                  "gradle bootRun --args='--spring.profiles.active=local'"
    Start-DevWindow $backendCmd
    Write-Host "    API     : http://localhost:8080/api/v1"
    Write-Host "    Swagger : http://localhost:8080/swagger-ui.html"
}

# --- 3. Mobile (Flutter Web) --------------------------------------------------
if (-not $SkipMobile) {
    $device = if ($WebServer) { 'web-server' } else { 'chrome' }
    Write-Host "==> Spawning Flutter Web window ($device, port 5173)" -ForegroundColor Cyan
    $flutterArgs = "run -d $device --web-port 5173"
    if ($FakeBackend) {
        $flutterArgs += " --dart-define=PDD_BACKEND=fake"
        Write-Host "    Mode    : FAKE (no backend calls)" -ForegroundColor Yellow
    } else {
        $flutterArgs += " --dart-define=PDD_API_BASE=http://localhost:8080"
        Write-Host "    Mode    : API -> http://localhost:8080"
    }
    $mobileCmd = $RefreshPath +
                 "Set-Location '$RepoRoot\mobile'; " +
                 "Write-Host 'PDD mobile - Ctrl+C to stop, R to hot-reload' -ForegroundColor Green; " +
                 "if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { Write-Host 'ERROR: flutter not on PATH' -ForegroundColor Red; return }; " +
                 "flutter pub get; if (`$LASTEXITCODE -eq 0) { flutter $flutterArgs }"
    Start-DevWindow $mobileCmd
    Write-Host "    App     : http://localhost:5173"
}

Write-Host ""
Write-Host "==> Demo logins (password: demo1234)" -ForegroundColor Green
Write-Host "      khalid   ADMIN        -> /portal"
Write-Host "      fatima   LEADER       -> /app"
Write-Host "      layla    MEMBER       -> /app"
Write-Host "      ahmed    MEMBER       -> /app"
Write-Host ""
Write-Host "==> Stop everything later with: .\scripts\dev-down.ps1" -ForegroundColor Cyan
