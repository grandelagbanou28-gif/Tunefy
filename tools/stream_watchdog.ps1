<#
.SYNOPSIS
  Garde le resolveur de flux local en vie (port 9877).

.DESCRIPTION
  Le serveur se fait tuer sans trace (aucune exception, aucune trace dans le
  log) — il se killait en pleine requete, ce qui coupait la connexion avant
  l'envoi des en-tetes et faisait echouer silencieusement le titre en cours.
  Consequence cote app : "Connection closed before full header was received".

  Cette boucle verifie /health et relance le serveur quand le port ne repond
  plus. Elle se lance une seule fois : le fichier de PID evite d'accumuler les
  boucles si le script de demarrage est relance plusieurs fois.
#>
[CmdletBinding()]
param(
  [int]$Port = 9877,
  [string]$Python = 'C:\Users\grand\miniforge3\python.exe',
  # Chemin du log de demarrage, pour diagnostiquer une boucle qui ne demarre pas.
  [string]$StateFile = "$env:TEMP\tunefy_stream_watchdog.pid"
)

$ErrorActionPreference = 'Continue'
$projectRoot = Split-Path -Parent $PSScriptRoot
$serverScript = Join-Path $projectRoot 'backend\local_stream_server.py'

function Test-ServerUp {
  try {
    $r = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 6
    return ($r.ok -eq $true)
  } catch {
    return $false
  }
}

function Start-Server {
  if (-not (Test-Path -LiteralPath $Python)) { return }
  Start-Process -FilePath $Python `
    -ArgumentList "`"$serverScript`" --port $Port" `
    -WindowStyle Hidden | Out-Null
}

while ($true) {
  if (-not (Test-ServerUp)) {
    Start-Server
    # Attente pollée : au démarrage le serveur copie ffmpeg, ce qui prend plus
    # d'une seconde. On ne relance pas en boucle si le démarrage est lent.
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline -and -not (Test-ServerUp)) {
      Start-Sleep -Milliseconds 700
    }
  }
  Start-Sleep -Seconds 10
}