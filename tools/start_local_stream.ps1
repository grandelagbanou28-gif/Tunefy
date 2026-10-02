<#
.SYNOPSIS
  Lance le resolveur de flux local et ouvre le port vers le telephone.

.DESCRIPTION
  Le serveur local (backend/local_stream_server.py) est la seule source qui
  resout avec la bonne IP : le worker Vercel renvoie des liens YouTube lies a
  l'IP du serveur, donc le telephone recoit un 403. Sans ce serveur, rien ne se
  lit. Il se killait silencieusement en fin de session, ce qui donnait
  "Empty reply from server" sans rien indiquer.

  Ce script le relance s'il est mort, verifie /health, puis (re)fait
  adb reverse. A appeler apres chaque build debug.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\start_local_stream.ps1
  powershell -ExecutionPolicy Bypass -File tools\start_local_stream.ps1 -Check
#>
[CmdletBinding()]
param(
  # Verifie seulement l'etat, sans demarrer ni modifier quoi que ce soit.
  [switch]$Check,
  # Lance aussi la boucle de surveillance qui relance le serveur s'il meurt.
  # Actif par defaut : le serveur se fait tuer sans trace en session.
  [switch]$NoWatchdog
)

$ErrorActionPreference = 'Stop'
$port = 9877
$projectRoot = Split-Path -Parent $PSScriptRoot
$serverScript = Join-Path $projectRoot 'backend\local_stream_server.py'
$python = 'C:\Users\grand\miniforge3\python.exe'

function Test-LocalHealth {
  try {
    $r = Invoke-RestMethod -Uri "http://127.0.0.1:$port/health" -TimeoutSec 8
    return ($r.ok -eq $true)
  } catch {
    return $false
  }
}

$adbs = @(
  "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
  'C:\android-sdk\platform-tools\adb.exe'
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

function Get-DeviceId {
  if (-not $adbs) { return $null }
  $all = & $adbs devices 2>$null |
    Where-Object { $_ -match '\sdevice$' } |
    ForEach-Object { ($_ -split '\s+')[0] }
  # Prefer a plain wireless IP:port; fall back to the mDNS/TLS pairing, which is
  # often the only entry left once the phone changes network or port.
  $byIp = $all | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+:\d+$' } | Select-Object -First 1
  if ($byIp) { return $byIp }
  return ($all | Select-Object -First 1)
}

$serverUp = Test-LocalHealth
$device = Get-DeviceId

if ($Check) {
  [pscustomobject]@{
    ServerRunning = $serverUp
    Port = $port
    Device = $(if ($device) { $device } else { '(aucun)' })
    Adb = $(if ($adbs) { $adbs } else { '(introuvable)' })
  } | Format-List
  exit 0
}

if (-not $serverUp) {
  if (-not (Test-Path -LiteralPath $python)) {
    Write-Warning "Python introuvable : $python"
    exit 1
  }
  $proc = Start-Process -FilePath $python `
    -ArgumentList "`"$serverScript`" --port $port" `
    -WindowStyle Hidden -PassThru
  # Polled rather than a fixed sleep: on a cold start the server also copies
  # ffmpeg into place, which takes longer than a couple of seconds.
  $deadline = (Get-Date).AddSeconds(30)
  $serverUp = $false
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 700
    if (Test-LocalHealth) { $serverUp = $true; break }
  }
  if ($serverUp) {
    Write-Host "Resolveur local demarre (pid $($proc.Id), port $port)."
  } else {
    Write-Warning "Le serveur a demarre mais /health ne repond pas. Voir le log."
  }
} else {
  Write-Host "Resolveur local deja actif (port $port)."
}

if ($device -and $adbs) {
  & $adbs -s $device reverse "tcp:$port" "tcp:$port" | Out-Null
  $list = (& $adbs -s $device reverse --list) -join "`n"
  if ($list -match "tcp:$port") {
    Write-Host "Port ouvert vers $device."
  } else {
    Write-Warning "adb reverse n'a pas pris. Reconnecte le telephone puis relance."
  }
} else {
  Write-Warning "Aucun appareil ADB : le port n'est pas ouvert, rien ne se lira sur le telephone."
}

# Surveillance : sans elle, une mort silencieuse du serveur coupe la lecture
# jusqu'a une relance manuelle.
if (-not $NoWatchdog) {
  $watchdog = Join-Path $PSScriptRoot 'stream_watchdog.ps1'
  $stateFile = Join-Path $env:TEMP 'tunefy_stream_watchdog.pid'
  $running = $false
  if (Test-Path -LiteralPath $stateFile) {
    $oldPid = (Get-Content $stateFile -Raw -ErrorAction SilentlyContinue).Trim()
    if ($oldPid -match '^\d+$') {
      $running = $null -ne (Get-Process -Id ([int]$oldPid) -ErrorAction SilentlyContinue)
    }
  }
  if ($running) {
    Write-Host "Surveillance deja active (pid $oldPid)."
  } else {
    $w = Start-Process -FilePath 'powershell.exe' `
      -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', `
      '-File', "`"$watchdog`"", '-Port', $port `
      -WindowStyle Hidden -PassThru
    Set-Content -LiteralPath $stateFile -Value $w.Id
    Write-Host "Surveillance lancee (pid $($w.Id)) : le serveur relancera tout seul."
  }
}
