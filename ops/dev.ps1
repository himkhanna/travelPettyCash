# Dev loop helper for the PDD Petty Cash backend (PowerShell / Windows).
# Mirror of ops/dev.sh. Subcommands: up | down | nuke | restart | build | status | logs | smoke | help
# Default with no args = restart.
#
# Run from PowerShell:
#   .\ops\dev.ps1 restart
# Or from any directory:
#   pwsh path\to\ops\dev.ps1 up

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('up', 'down', 'nuke', 'restart', 'build', 'status', 'logs', 'smoke', 'help', '-h', '--help')]
    [string]$Command = 'restart'
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
$RepoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ComposeFile  = Join-Path $RepoRoot 'ops\docker-compose.yml'
$BackendDir   = Join-Path $RepoRoot 'backend'
$LogFile      = if ($env:PETTYCASH_LOG) { $env:PETTYCASH_LOG } else { Join-Path $env:TEMP 'pettycash-backend.log' }
$Port         = if ($env:PETTYCASH_PORT) { [int]$env:PETTYCASH_PORT } else { 8080 }
$SpringProfile = if ($env:PETTYCASH_PROFILE) { $env:PETTYCASH_PROFILE } else { 'local' }
$BootTimeout  = if ($env:PETTYCASH_BOOT_TIMEOUT) { [int]$env:PETTYCASH_BOOT_TIMEOUT } else { 180 }
$DbTimeout    = if ($env:PETTYCASH_DB_TIMEOUT)   { [int]$env:PETTYCASH_DB_TIMEOUT }   else { 60 }

function Log  ([string]$m) { Write-Host "==> $m" -ForegroundColor Blue }
function Ok   ([string]$m) { Write-Host "OK  $m" -ForegroundColor Green }
function Warn ([string]$m) { Write-Host "!!  $m" -ForegroundColor Yellow }
function Err  ([string]$m) { Write-Host "XX  $m" -ForegroundColor Red }

# ---------------------------------------------------------------------------
# Probes
# ---------------------------------------------------------------------------
function Get-BackendProcess {
    # Find the running Spring Boot JVM by its main class, not the gradle wrapper.
    Get-CimInstance Win32_Process -Filter "Name = 'java.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -match 'ae\.gov\.pdd\.pettycash\.PettyCashApplication' } |
        Select-Object -First 1
}

function Get-PortListenerPids {
    Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique
}

function Test-ComposeHealthy {
    try {
        $pg    = (docker inspect -f '{{.State.Health.Status}}' travelpettycash-postgres 2>$null)
        $minio = (docker inspect -f '{{.State.Health.Status}}' travelpettycash-minio    2>$null)
        return ($pg -eq 'healthy' -and $minio -eq 'healthy')
    } catch { return $false }
}

# Container says healthy != host port is bound. On Windows Docker Desktop the
# port-publishing layer can lag the container's own healthcheck, so we also
# probe the host-side TCP listener before declaring victory.
function Test-HostPortReady {
    param([int]$TcpPort)
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect('127.0.0.1', $TcpPort, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(500)
        if (-not $ok) { $c.Close(); return $false }
        $c.EndConnect($iar)
        $c.Close()
        return $true
    } catch { return $false }
}

function Test-BackendResponding {
    try {
        $null = Invoke-RestMethod -Uri "http://localhost:$Port/health" -TimeoutSec 2 -ErrorAction Stop
        return $true
    } catch { return $false }
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------
function Ensure-Compose {
    if (Test-ComposeHealthy) {
        Ok "Postgres + MinIO already healthy"
        return
    }
    Log "Starting Postgres + MinIO ($ComposeFile)"
    docker compose -f $ComposeFile up -d | Out-Null
    Log "Waiting up to ${DbTimeout}s for healthy"
    $deadline = (Get-Date).AddSeconds($DbTimeout)
    while (-not (Test-ComposeHealthy)) {
        if ((Get-Date) -ge $deadline) {
            Err "Postgres / MinIO did not become healthy in ${DbTimeout}s"
            docker ps --format 'table {{.Names}}\t{{.Status}}' | Select-String travelpettycash
            exit 1
        }
        Start-Sleep -Seconds 2
    }
    Log "Waiting for host TCP ports (5432, 9100)"
    while ($true) {
        if ((Test-HostPortReady -TcpPort 5432) -and (Test-HostPortReady -TcpPort 9100)) { break }
        if ((Get-Date) -ge $deadline) {
            Err "Host ports 5432/9100 not reachable in ${DbTimeout}s"
            exit 1
        }
        Start-Sleep -Seconds 1
    }
    Ok "Postgres + MinIO healthy"
}

function Stop-Backend {
    $proc = Get-BackendProcess
    if ($proc) {
        Log "Stopping backend (pid $($proc.ProcessId))"
        Stop-Process -Id $proc.ProcessId -ErrorAction SilentlyContinue
        # Wait up to 10s for graceful shutdown.
        for ($i = 0; $i -lt 10; $i++) {
            if (-not (Get-Process -Id $proc.ProcessId -ErrorAction SilentlyContinue)) { break }
            Start-Sleep -Seconds 1
        }
        if (Get-Process -Id $proc.ProcessId -ErrorAction SilentlyContinue) {
            Warn "Backend did not exit in 10s - forcing"
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
        }
    } else {
        Log "No running backend"
    }
    # Kill any gradle wrappers still squatting.
    Get-CimInstance Win32_Process -Filter "Name = 'java.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -match 'GradleWrapperMain.*bootRun' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    # Kill anything still listening on the port.
    $listeners = Get-PortListenerPids
    if ($listeners) {
        Warn "Killing stale listeners on port ${Port}: $($listeners -join ', ')"
        $listeners | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }
    }
    Ok "Backend stopped"
}

function Build-Backend {
    Log "Building backend (gradlew build -x test)"
    Push-Location $BackendDir
    try {
        & .\gradlew.bat --console=plain -q build -x test
        if ($LASTEXITCODE -ne 0) { Err "Build failed"; exit 1 }
    } finally { Pop-Location }
    Ok "Build succeeded"
}

function Start-Backend {
    if (Get-BackendProcess) {
        Warn "Backend already running (pid $((Get-BackendProcess).ProcessId))"
        return
    }
    Log "Starting backend (profile=$SpringProfile, log=$LogFile)"
    # Start-Process on Windows PowerShell 5.1 refuses the same file for both
    # streams, so stderr goes to a sibling file and the wait loop greps both.
    $LogFileErr = "$LogFile.err"
    # Truncate so the readiness scan below isn't fooled by an old run.
    Set-Content -Path $LogFile    -Value '' -Encoding UTF8
    Set-Content -Path $LogFileErr -Value '' -Encoding UTF8
    Start-Process -FilePath (Join-Path $BackendDir 'gradlew.bat') `
                  -ArgumentList @('--console=plain', '-q', 'bootRun', "--args=--spring.profiles.active=$SpringProfile") `
                  -WorkingDirectory $BackendDir `
                  -RedirectStandardOutput $LogFile `
                  -RedirectStandardError  $LogFileErr `
                  -WindowStyle Hidden | Out-Null
    Log "Waiting up to ${BootTimeout}s for 'Started PettyCashApplication'"
    $deadline = (Get-Date).AddSeconds($BootTimeout)
    $pattern  = 'Started PettyCashApplication|APPLICATION FAILED|BUILD FAILED|Application run failed|Web server failed to start'
    while ($true) {
        $hit = $false
        foreach ($f in @($LogFile, $LogFileErr)) {
            if (Test-Path $f) {
                if (Select-String -Path $f -Pattern $pattern -Quiet -ErrorAction SilentlyContinue) {
                    $hit = $true; break
                }
            }
        }
        if ($hit) { break }
        if ((Get-Date) -ge $deadline) {
            Err "Backend did not signal readiness in ${BootTimeout}s"
            if (Test-Path $LogFile)    { Get-Content $LogFile    -Tail 20 | Write-Host }
            if (Test-Path $LogFileErr) { Get-Content $LogFileErr -Tail 20 | Write-Host }
            exit 1
        }
        Start-Sleep -Seconds 2
    }
    $bad = 'APPLICATION FAILED|BUILD FAILED|Application run failed|Web server failed to start'
    foreach ($f in @($LogFile, $LogFileErr)) {
        if ((Test-Path $f) -and (Select-String -Path $f -Pattern $bad -Quiet -ErrorAction SilentlyContinue)) {
            Err "Backend failed to start. Last 30 lines from $f"
            Get-Content $f -Tail 30 | Write-Host
            exit 1
        }
    }
    Ok "Backend up on http://localhost:$Port"
}

function Invoke-Smoke {
    Log "Smoke test"
    if (-not (Test-BackendResponding)) {
        Err "/health is not reachable on port $Port"
        return $false
    }
    Ok "/health responds"

    try {
        $login = Invoke-RestMethod -Uri "http://localhost:$Port/api/v1/auth/login" `
                                   -Method Post -ContentType 'application/json' `
                                   -Body '{"provider":"PDD_SSO","code":"any"}' -ErrorAction Stop
        $token = $login.accessToken
    } catch { Err "Login failed: $($_.Exception.Message)"; return $false }
    if (-not $token) { Err "Login did not return an accessToken"; return $false }
    Ok "Login OK (PDD_SSO -> JWT issued)"

    $h = @{ Authorization = "Bearer $token" }
    try {
        $me = Invoke-RestMethod -Uri "http://localhost:$Port/api/v1/me" -Headers $h -ErrorAction Stop
        Ok "/me -> $($me.username) role=$($me.role)"
    } catch { Err "/me failed"; return $false }

    try {
        $trips = Invoke-RestMethod -Uri "http://localhost:$Port/api/v1/trips?status=ACTIVE" -Headers $h -ErrorAction Stop
        Ok "/trips -> $($trips.Count) active trip(s)"
    } catch { Err "/trips failed"; return $false }

    # OCR scan smoke - synth a tiny "image" payload (the mock OCR keys on sha256 mod 4).
    $tmpImg = Join-Path $env:TEMP 'pettycash-smoke.jpg'
    'smoke' | Set-Content -Path $tmpImg -Encoding ASCII
    try {
        # PowerShell 6+ supports -Form; on Windows PowerShell 5.1 fall back to curl.exe (ships with Win10+).
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $scan = Invoke-RestMethod -Uri "http://localhost:$Port/api/v1/receipts/scan" `
                                      -Method Post -Headers $h `
                                      -Form @{ file = Get-Item $tmpImg } -ErrorAction Stop
        } else {
            $raw = & curl.exe -fsS -X POST "http://localhost:$Port/api/v1/receipts/scan" `
                              -H "Authorization: Bearer $token" `
                              -F "file=@$tmpImg;type=image/jpeg"
            if ($LASTEXITCODE -ne 0) { throw "curl returned $LASTEXITCODE" }
            $scan = $raw | ConvertFrom-Json
        }
        Ok "/receipts/scan -> $($scan.vendor) / conf=$($scan.confidence)"
    } catch { Err "/receipts/scan failed: $($_.Exception.Message)"; return $false }

    Ok "All smoke checks passed"
    return $true
}

function Show-Status {
    Log "Compose"
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' |
        Select-String -Pattern 'travelpettycash|NAMES'
    Write-Host ''
    Log "Backend process"
    $proc = Get-BackendProcess
    if ($proc) {
        Ok "Running (pid $($proc.ProcessId))"
        if (Test-BackendResponding) {
            Ok "/health responding on port $Port"
        } else {
            Warn "Process running but /health not responding yet"
        }
    } else {
        Warn "Not running"
    }
    Write-Host ''
    Log "Port $Port listeners"
    $listeners = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($listeners) {
        $listeners | Format-Table LocalAddress, LocalPort, OwningProcess -AutoSize | Out-String | Write-Host
    } else {
        Write-Host "  (none)"
    }
    Write-Host ''
    Log "Last 5 lines of $LogFile"
    if (Test-Path $LogFile) {
        Get-Content $LogFile -Tail 5 | Write-Host
    } else {
        Write-Host "  (no log yet)"
    }
}

function Tail-Logs {
    if (-not (Test-Path $LogFile)) {
        Err "No log at $LogFile"
        exit 1
    }
    Get-Content $LogFile -Wait -Tail 50
}

function Show-Help {
    @"
Usage: .\ops\dev.ps1 [command]

Commands:
  up         Bring up compose + backend, then smoke test.
  down       Stop the backend (compose stays up).
  nuke       Stop the backend AND stop/remove the compose stack and volumes.
  restart    Stop -> build -> start -> smoke test. (default)
  build      Just rebuild the backend jar.
  status     Show what's running.
  logs       Tail the backend log.
  smoke      Run the smoke test against whatever is already running.
  help       This message.

Environment:
  PETTYCASH_PORT          (default 8080)
  PETTYCASH_PROFILE       (default local)
  PETTYCASH_LOG           (default %TEMP%\pettycash-backend.log)
  PETTYCASH_BOOT_TIMEOUT  (default 180 seconds)
  PETTYCASH_DB_TIMEOUT    (default 60 seconds)
"@ | Write-Host
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
switch ($Command) {
    'up'      { Ensure-Compose; Start-Backend; if (-not (Invoke-Smoke)) { exit 1 } }
    'down'    { Stop-Backend }
    'nuke'    {
        Stop-Backend
        Log "Removing compose stack + volumes"
        docker compose -f $ComposeFile down -v | Out-Null
        Ok "Compose stack removed"
    }
    'restart' { Stop-Backend; Ensure-Compose; Build-Backend; Start-Backend; if (-not (Invoke-Smoke)) { exit 1 } }
    'build'   { Build-Backend }
    'status'  { Show-Status }
    'logs'    { Tail-Logs }
    'smoke'   { if (-not (Invoke-Smoke)) { exit 1 } }
    default   { Show-Help }
}
