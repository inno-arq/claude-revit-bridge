# ruta-a-dos-pegados.ps1 — Ruta A en DOS pegados, con las compuertas del runbook automaticas.
# Nacio el 2026-09-18 en MMAS-MDH-120 (usuario aalzamora, Chrome Remote Desktop desde la Mac) porque
# los 7 bloques con ida y vuelta por cada uno eran lentos. Cada paso se salta lo que sigue si una
# compuerta falla, y termina con un resumen que cabe en una captura.
#
#   PASO 1 (Revit cerrado): cierra Claude, respalda el config, descarga install.ps1 y lo compara por
#     hash con el revisado en la Mac, instala con -SkipNodeCheck -Force, verifica, quita la BOM
#     (gotcha #29), rearma revit-mcp si falta y abre Revit con una muestra.
#     Compuerta: "LISTO PARA OPEN SERVER: True".
#   MOUSE: Always Load (si aparece) -> Add-Ins -> Revit MCP Switch UNA vez -> CERRAR el aviso
#     "Open Server" (gotcha #6: abierto, Claude recibe timeouts).
#   PASO 2: 8080, reinicio real de Claude y lectura de los logs nuevos en las DOS carpetas posibles
#     (gotcha #30). Compuerta: "8080 escucha por: Revit", "CONECTADO en este arranque: True",
#     "revit-mcp sigue en config: True". Luego la pregunta en un chat NORMAL de Claude Desktop.
#
# Estado: el paso 1 y la version anterior del paso 2 corrieron en MMAS-MDH-120 y la pregunta en el chat
# devolvio datos del modelo. Este paso 2 (cierra Claude y lee las dos carpetas de logs) y la busqueda
# de muestras en Program Files se anadieron despues: SIN correr en una Windows.
# Antes de usarlo: el hash esperado es el del install.ps1 de main revisado en la Mac; si cambia, revisalo.
# Lineas en ASCII y sin tabuladores a proposito: se pegan en la consola, que ejecuta linea por linea.

# --- paso 1: preparar, instalar, verificar, quitar BOM y abrir Revit ---
$ok = $true; $r = @()
$pkg = (Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter "Claude_*" -EA SilentlyContinue | Select-Object -First 1).FullName
$root = if ($pkg -and (Test-Path "$pkg\LocalCache\Roaming\Claude\claude_desktop_config.json")) { "$pkg\LocalCache\Roaming\Claude" } else { "$env:APPDATA\Claude" }
$cfg = "$root\claude_desktop_config.json"
$n = (Get-Process Revit -EA SilentlyContinue | Measure-Object).Count; $r += "revit abierto (debe ser 0): $n"; if ($n -gt 0) { $ok = $false }
Get-Process Claude -EA SilentlyContinue | Stop-Process -Force; Start-Sleep -Seconds 6
$n = (Get-Process Claude -EA SilentlyContinue | Measure-Object).Count; $r += "claude (debe ser 0): $n"; if ($n -gt 0) { $ok = $false }
$r += "config: $cfg  existe: " + (Test-Path $cfg); if (-not (Test-Path $cfg)) { $ok = $false }
if ($ok -and -not (Test-Path "$cfg.pre-revit-mcp.bak")) { Copy-Item $cfg "$cfg.pre-revit-mcp.bak" }
$r += "backup: " + (Test-Path "$cfg.pre-revit-mcp.bak")
cd $env:USERPROFILE\Downloads
irm https://raw.githubusercontent.com/LuDattilo/revit-mcp-server/main/scripts/install.ps1 -OutFile install.ps1
$h = (Get-FileHash .\install.ps1 -Algorithm SHA256).Hash -eq "CC00CD86376E53C548D642B295ADC63F7AF93D784A7104AA6AB9402DC7A49B77"; $r += "hash igual al de la Mac: $h"; if (-not $h) { $ok = $false }
if ($ok) { powershell -ExecutionPolicy Bypass -File .\install.ps1 -SkipNodeCheck -Force; $r += "instalador exit: $LASTEXITCODE"; if ($LASTEXITCODE -ne 0) { $ok = $false } } else { $r += "NO se instalo: revisa las lineas de arriba" }
$srv = (Get-Item "$env:APPDATA\Autodesk\Revit\Addins\20*\revit_mcp_plugin\Commands\RevitMCPCommandSet\server" -EA SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1).FullName
$year = if ($srv) { ($srv -split '\\Addins\\')[1].Substring(0,4) } else { "" }
$node = "$srv\runtime\node.exe"; $idx = "$srv\build\index.js"
$r += "plugin: Revit $year  node: " + (Test-Path $node) + "  index: " + (Test-Path $idx); if (-not ($srv -and (Test-Path $node) -and (Test-Path $idx))) { $ok = $false }
$js = "try{JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));console.log('OK')}catch(e){console.log('FALLA: '+e.message)}"
if ($ok) { $txt = [IO.File]::ReadAllText($cfg).TrimStart([char]0xFEFF); $o = $txt | ConvertFrom-Json; $e = $o.mcpServers.'revit-mcp'; if (-not ($e -and (Test-Path "$($e.command)") -and (Test-Path "$($e.args[0])"))) { if (-not $o.mcpServers) { $o | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([PSCustomObject]@{}) }; $o.mcpServers | Add-Member -NotePropertyName 'revit-mcp' -NotePropertyValue ([PSCustomObject]@{ command = $node; args = @($idx) }) -Force; $txt = $o | ConvertTo-Json -Depth 20; $r += "revit-mcp rearmado en el config" } }
if ($ok -and (Get-Process Claude -EA SilentlyContinue | Measure-Object).Count -eq 0) { [IO.File]::WriteAllText($cfg, $txt, (New-Object System.Text.UTF8Encoding $false)) }
if ($ok) { $b = ([IO.File]::ReadAllBytes($cfg))[0..2] -join ","; $p = & $node -e $js $cfg; $has = [bool](([IO.File]::ReadAllText($cfg) | ConvertFrom-Json).mcpServers.'revit-mcp'); $r += "config: bytes $b  JSON.parse: $p  revit-mcp: $has"; if (-not ($b -like "123*" -and $p -eq "OK" -and $has)) { $ok = $false } }
if ($ok) { $f = Get-Item "C:\ProgramData\Autodesk\RVT $year\Samples\*.rvt", "C:\Program Files\Autodesk\Revit $year\Samples\*.rvt" -EA SilentlyContinue | Where-Object Name -notlike "*family*" | Select-Object -First 1 -ExpandProperty FullName; $r += "muestra: $f"; if ($f) { Start-Process "C:\Program Files\Autodesk\Revit $year\Revit.exe" -ArgumentList "`"$f`"" } else { Start-Process "C:\Program Files\Autodesk\Revit $year\Revit.exe" } }
""; "===== RESUMEN PASO 1 ====="; $r; "LISTO PARA OPEN SERVER: $ok"; "--- fin paso 1 ---"

# --- paso 2: SOLO despues de pulsar el Switch UNA vez y CERRAR el aviso "Open Server" ---
$p8 = Get-NetTCPConnection -LocalPort 8080 -State Listen -EA SilentlyContinue | Select-Object -First 1
"8080 escucha por: " + $(if ($p8) { (Get-Process -Id $p8.OwningProcess).ProcessName } else { "NADIE" })
$pkg = (Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter "Claude_*" -EA SilentlyContinue | Select-Object -First 1).FullName
$root = if ($pkg -and (Test-Path "$pkg\LocalCache\Roaming\Claude\claude_desktop_config.json")) { "$pkg\LocalCache\Roaming\Claude" } else { "$env:APPDATA\Claude" }
$cfg = "$root\claude_desktop_config.json"
Get-Process Claude -EA SilentlyContinue | Stop-Process -Force; Start-Sleep -Seconds 6
"claude tras cerrar (debe ser 0): " + (Get-Process Claude -EA SilentlyContinue | Measure-Object).Count
$dirs = @("$env:APPDATA\Claude\logs", "$pkg\LocalCache\Roaming\Claude\logs") | Where-Object { Test-Path $_ }; "carpetas de logs: " + ($dirs -join "; ")
$before = @{}; Get-ChildItem $dirs -Filter *.log | ForEach-Object { $before[$_.FullName] = $_.Length }
$app = (Get-StartApps | Where-Object { $_.AppID -like "Claude_*" -or $_.Name -eq "Claude" } | Select-Object -First 1).AppID; "app: $app"
Start-Process explorer.exe "shell:AppsFolder\$app"; Start-Sleep -Seconds 40
"claude procs: " + (Get-Process Claude -EA SilentlyContinue | Measure-Object).Count
$all = ""; Get-ChildItem $dirs -Filter *.log | Where-Object { $_.Length -ne $before[$_.FullName] } | ForEach-Object { $o = [int64]$before[$_.FullName]; if ($o -gt $_.Length) { $o = 0 }; $fs = [IO.File]::Open($_.FullName, 'Open', 'Read', 'ReadWrite'); [void]$fs.Seek($o, 'Begin'); $all += (New-Object IO.StreamReader($fs)).ReadToEnd(); $fs.Close() }
($all -split "`n") | Where-Object { $_ -match 'Connected to revit-mcp|localMcpBridge|not valid JSON' } | Select-Object -Last 6
"CONECTADO en este arranque: " + ($all -match 'Connected to revit-mcp \(\d+ tools\)')
"revit-mcp sigue en config: " + [bool](([IO.File]::ReadAllText($cfg).TrimStart([char]0xFEFF) | ConvertFrom-Json).mcpServers.'revit-mcp')
"--- fin paso 2 ---"
