# watchdog.ps1 - mantiene vivos el gateway y el tunel del puente Revit MCP.
# Pensado para correr cada 2 minutos desde una tarea de schtasks (no requiere admin).
# Ver gotchas #25 y #26 del skill connect-claude-revit.

$dst = "$env:USERPROFILE\revit-gateway"
$cf  = "$env:USERPROFILE\tools\cloudflared.exe"
$log = "$dst\watchdog.log"

if (-not (Get-NetTCPConnection -LocalPort 8000 -State Listen -EA SilentlyContinue)) {
  $env:MCP_TOKEN = (Get-Content "$dst\token.txt" -Raw).Trim()
  Start-Process node -ArgumentList """$dst\gateway.js""" -WorkingDirectory $dst `
    -RedirectStandardOutput "$dst\gw.out.log" -RedirectStandardError "$dst\gw.err.log" -WindowStyle Hidden
  Add-Content $log ((Get-Date).ToString('s') + "  relance gateway")
}

if (-not (Get-Process cloudflared -EA SilentlyContinue)) {
  if (Test-Path "$dst\tunnel-token.txt") {
    $tok = (Get-Content "$dst\tunnel-token.txt" -Raw).Trim()
    Start-Process $cf -ArgumentList "--loglevel","info","--logfile","$dst\cloudflared.log","tunnel","run","--token",$tok -WindowStyle Hidden
    Add-Content $log ((Get-Date).ToString('s') + "  relance tunel")
  } else {
    Add-Content $log ((Get-Date).ToString('s') + "  FALTA tunnel-token.txt")
  }
}
