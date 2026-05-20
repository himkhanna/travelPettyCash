# Dev loop helper for the PDD Petty Cash Flutter app (PowerShell / Windows).
# Mirror of ops/dev-mobile.sh. Subcommands: up | pub | analyze | test | check | build | clean | help
# Default with no args = up.

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('up', 'pub', 'analyze', 'test', 'check', 'build', 'clean', 'help', '-h', '--help')]
    [string]$Command = 'up'
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
$RepoRoot  = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$MobileDir = Join-Path $RepoRoot 'mobile'
$Device    = if ($env:PETTYCASH_MOBILE_DEVICE)   { $env:PETTYCASH_MOBILE_DEVICE }   else { 'chrome' }
$WebPort   = $env:PETTYCASH_MOBILE_WEB_PORT
$ApiBase   = $env:PETTYCASH_API_BASE

function Log  ([string]$m) { Write-Host "==> $m" -ForegroundColor Blue }
function Ok   ([string]$m) { Write-Host "OK  $m" -ForegroundColor Green }
function Warn ([string]$m) { Write-Host "!!  $m" -ForegroundColor Yellow }
function Err  ([string]$m) { Write-Host "XX  $m" -ForegroundColor Red }

function Require-Flutter {
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        Err "flutter not found on PATH"
        Err "Install: https://docs.flutter.dev/get-started/install/windows"
        exit 127
    }
}

function Show-FlutterVersion {
    $v = (& flutter --version 2>$null | Select-Object -First 1)
    if ($v) { Log $v }
}

function Get-DartDefines {
    $flags = @()
    if ($ApiBase) { $flags += "--dart-define=API_BASE=$ApiBase" }
    return $flags
}

function Invoke-FlutterIn-Mobile {
    param([string[]]$Args)
    Push-Location $MobileDir
    try {
        & flutter @Args
        if ($LASTEXITCODE -ne 0) { throw "flutter $($Args -join ' ') exited $LASTEXITCODE" }
    } finally { Pop-Location }
}

function Invoke-PubGet {
    Log "flutter pub get"
    try { Invoke-FlutterIn-Mobile @('pub', 'get') } catch { Err $_.Exception.Message; exit 1 }
    Ok "Dependencies resolved"
}

function Invoke-Analyze {
    Log "flutter analyze --no-fatal-infos"
    try {
        Invoke-FlutterIn-Mobile @('analyze', '--no-fatal-infos')
        Ok "analyze clean"
    } catch { Err "analyze reported issues"; exit 1 }
}

function Invoke-Tests {
    Log "flutter test"
    try {
        Invoke-FlutterIn-Mobile @('test')
        Ok "tests passed"
    } catch { Err "tests failed"; exit 1 }
}

function Invoke-Check {
    Invoke-PubGet
    Invoke-Analyze
    Invoke-Tests
    Ok "All checks passed"
}

function Invoke-BuildWeb {
    Invoke-PubGet
    Log "flutter build web --release"
    $extra = Get-DartDefines
    try {
        Invoke-FlutterIn-Mobile (@('build', 'web', '--release') + $extra)
        Ok "Built mobile\build\web (deployable artifact)"
    } catch { Err "Web build failed"; exit 1 }
}

function Invoke-Clean {
    Log "flutter clean"
    Invoke-FlutterIn-Mobile @('clean') | Out-Null
    Ok "Cleaned mobile\.dart_tool + mobile\build"
}

function Invoke-Up {
    Invoke-PubGet
    Log "flutter run -d $Device"
    if ($ApiBase) {
        Log "Wiring real backend: API_BASE=$ApiBase"
    } else {
        Log "Running against fake repositories (no backend needed)"
        Log "Set PETTYCASH_API_BASE=http://localhost:8080 once the real-API switch lands"
    }
    $runArgs = @('run', '-d', $Device)
    if ($WebPort) { $runArgs += "--web-port=$WebPort" }
    $runArgs += Get-DartDefines
    Push-Location $MobileDir
    try {
        & flutter @runArgs
        # flutter run is interactive; exit code propagates back to PowerShell.
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    } finally { Pop-Location }
}

function Show-Help {
    @"
Usage: .\ops\dev-mobile.ps1 [command]

Commands:
  up         pub get, then flutter run -d <device> (blocking). Default.
  pub        flutter pub get only.
  analyze    flutter analyze --no-fatal-infos.
  test       flutter test.
  check      pub get + analyze + test (the CI parity loop).
  build      flutter build web --release. Output: mobile\build\web.
  clean      flutter clean.
  help       This message.

Environment:
  PETTYCASH_MOBILE_DEVICE    Target device id (default: chrome).
                             Try 'flutter devices' for what's available.
  PETTYCASH_MOBILE_WEB_PORT  Pin a fixed port for chrome (default: random).
  PETTYCASH_API_BASE         If set, passed as --dart-define=API_BASE=<value>.
                             Today the app always uses fakes; the env var is
                             wired now so the real-API switch is a Riverpod
                             override change later, not a script change.

Examples:
  .\ops\dev-mobile.ps1                                   # fake mode
  `$env:PETTYCASH_MOBILE_WEB_PORT='5000'; .\ops\dev-mobile.ps1 up
  `$env:PETTYCASH_API_BASE='http://localhost:8080'; .\ops\dev-mobile.ps1 up
  .\ops\dev-mobile.ps1 check                             # full pre-push gate
  .\ops\dev-mobile.ps1 build                             # for the Vercel preview
"@ | Write-Host
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
if ($Command -in @('help', '-h', '--help')) { Show-Help; return }
Require-Flutter
switch ($Command) {
    'up'      { Show-FlutterVersion; Invoke-Up }
    'pub'     { Show-FlutterVersion; Invoke-PubGet }
    'analyze' { Show-FlutterVersion; Invoke-Analyze }
    'test'    { Show-FlutterVersion; Invoke-Tests }
    'check'   { Show-FlutterVersion; Invoke-Check }
    'build'   { Show-FlutterVersion; Invoke-BuildWeb }
    'clean'   { Show-FlutterVersion; Invoke-Clean }
    default   { Show-Help }
}
