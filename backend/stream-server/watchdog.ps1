# Watchdog for the local stream server (port 9877).
#
# The server used to die silently and every song stopped resolving until
# someone noticed. This loop checks the port every few seconds and restarts
# the server whenever it is no longer listening, so it stays up on its own.
$serverDir = "C:\flutter\s_potify\Muzo-v4\backend\stream-server"
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) { $node = "node" }

while ($true) {
  $up = $false
  try {
    $c = New-Object System.Net.Sockets.TcpClient
    $iar = $c.BeginConnect("127.0.0.1", 9877, $null, $null)
    if ($iar.AsyncWaitHandle.WaitOne(1500)) {
      $c.EndConnect($iar)
      $up = $true
    }
    $c.Close()
  } catch { $up = $false }

  if (-not $up) {
    Start-Process -FilePath $node -ArgumentList "server.js" -WorkingDirectory $serverDir -WindowStyle Hidden
  }
  Start-Sleep -Seconds 8
}
