# ruta-a-terminal.ps1 — Ruta A (plugin LuDattilo + Claude Desktop) 100 % por terminal.
# Uso: quien asiste está en OTRA máquina; la persona en la Windows pega UN bloque a la vez en
# PowerShell 5.1 y devuelve la salida. Entre bloques hay una compuerta (ver SKILL.md, «Flujo 100 %
# por terminal»). Cada bloque empieza con un comentario a propósito: la consola remota se come el
# primer carácter al pegar (gotcha #21). Probado el 2026-09-09 en M4TEC-EVEZGA (sin admin, Claude
# de Microsoft Store, Revit 2023/2025/2026).
#
# Compuertas:
#   1 -> 2 : decidir si hay que matar Revit/Claude y si el config es MSIX
#   2 -> 3 : "claude despues" = 0  Y  hash igual al del install.ps1 revisado en la máquina del que asiste
#   3 -> 4 : "Installation complete! (N version(s) installed)"
#   4 -> 4b: todo True, Claude sigue en 0 (PowerShell no ve la BOM: eso lo prueba el 4b, gotcha #29)
#   4b -> 5: "escrito sin BOM", "config despues: bytes 123,...   node: OK", "revit-mcp en config despues: True"
#            (bloque 4b añadido el 2026-09-14 en M4MEP-LZUANICH)
#   5 -> 6 : Revit con modelo abierto, Revit MCP Switch pulsado UNA vez y el aviso "Open Server" CERRADO
#            (único paso con mouse; con el aviso abierto Claude recibe timeouts, gotcha #6)
#   6 -> 7 : "8080 escucha por: Revit" y "Connected to revit-mcp (N tools)" con hora POSTERIOR al arranque
#   7 -> fin: "revit-mcp sigue en config: True"; después la pregunta en un chat normal de Claude Desktop

# --- bloque 1: reconocimiento revit-mcp (solo lectura, no cambia nada) ---
"host: $env:COMPUTERNAME  user: $env:USERNAME  ps: $($PSVersionTable.PSVersion)  build: $([Environment]::OSVersion.Version.Build)"
"admin: " + [bool](whoami /groups | Select-String "S-1-5-32-544")
"procesos revit: " + (Get-Process Revit -EA SilentlyContinue | Measure-Object).Count
"procesos claude: " + (Get-Process Claude -EA SilentlyContinue | Measure-Object).Count
"revit instalado: " + ((Get-ChildItem "C:\Program Files\Autodesk" -Directory -EA SilentlyContinue | Where-Object Name -like "Revit 20*" | ForEach-Object Name) -join ", ")
"addins de usuario: " + ((Get-ChildItem "$env:APPDATA\Autodesk\Revit\Addins" -Directory -EA SilentlyContinue | ForEach-Object Name) -join ", ")
"plugin ya presente: " + ((Get-ChildItem "$env:APPDATA\Autodesk\Revit\Addins" -Recurse -Directory -Filter revit_mcp_plugin -EA SilentlyContinue | ForEach-Object FullName) -join "; ")
$pkg = (Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter "Claude_*" -EA SilentlyContinue | Select-Object -First 1).FullName
"claude store: $pkg"
"claude clasico: " + (Test-Path "$env:LOCALAPPDATA\AnthropicClaude")
"claude exe: " + (Get-Process Claude -EA SilentlyContinue | Select-Object -First 1 -ExpandProperty Path)
$cfgA = "$env:APPDATA\Claude\claude_desktop_config.json"
$cfgS = if ($pkg) { "$pkg\LocalCache\Roaming\Claude\claude_desktop_config.json" } else { "" }
"cfg appdata: " + (Test-Path $cfgA) + "   cfg store: " + [bool]($cfgS -and (Test-Path $cfgS))
foreach ($c in @($cfgA, $cfgS)) { if ($c -and (Test-Path $c)) { "--- $c"; Get-Content $c -Raw } }
"node sistema: " + $(if (Get-Command node -EA SilentlyContinue) { node -v } else { "no" })
$ids = @((Get-Process Revit -EA SilentlyContinue).Id)
"puertos revit antes: " + ((Get-NetTCPConnection -State Listen -EA SilentlyContinue | Where-Object { $ids -contains $_.OwningProcess } | ForEach-Object { "$($_.LocalAddress):$($_.LocalPort)" }) -join ", ")
"--- fin reconocimiento ---"

# --- bloque 2: cerrar Claude, respaldar config, descargar instalador ---
"claude antes: " + (Get-Process Claude -EA SilentlyContinue | Measure-Object).Count
Get-Process Claude -EA SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 6
"claude despues (debe ser 0): " + (Get-Process Claude -EA SilentlyContinue | Measure-Object).Count
$pkg = (Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter "Claude_*" | Select-Object -First 1).FullName
$cfg = "$pkg\LocalCache\Roaming\Claude\claude_desktop_config.json"
Copy-Item $cfg "$cfg.pre-revit-mcp.bak" -Force
"backup: " + (Test-Path "$cfg.pre-revit-mcp.bak")
"mcpServers antes: " + (((Get-Content $cfg -Raw | ConvertFrom-Json).mcpServers.PSObject.Properties.Name) -join ", ")
cd $env:USERPROFILE\Downloads
irm https://raw.githubusercontent.com/LuDattilo/revit-mcp-server/main/scripts/install.ps1 -OutFile install.ps1
"hash: " + (Get-FileHash .\install.ps1 -Algorithm SHA256).Hash
"--- fin bloque 2 ---"
# En la máquina del que asiste:  curl -sSL -o install.ps1 <misma URL> && shasum -a 256 install.ps1
# El 2026-09-09 (main) era cc00cd86376e53c548d642b295adc63f7af93d784a7104aa6ab9402dc7a49b77.

# --- bloque 3: instalar (Revit y Claude siguen cerrados) ---
cd $env:USERPROFILE\Downloads
powershell -ExecutionPolicy Bypass -File .\install.ps1 -SkipNodeCheck
# -SkipNodeCheck: sin admin no hay MSI que falle ni pregunta [1/2/3]; el STEP 7 usa el node.exe
# empaquetado igual (gotcha #27). Si la máquina ya tuviera el plugin, preguntará [R/s/a].

# --- bloque 4: verificar instalacion (solo lectura) ---
"claude procs (debe seguir 0): " + (Get-Process Claude -EA SilentlyContinue | Measure-Object).Count
Get-ChildItem "$env:APPDATA\Autodesk\Revit\Addins" -Directory | ForEach-Object { "$($_.Name): addin=" + ((Get-ChildItem $_.FullName -Filter *.addin -EA SilentlyContinue | ForEach-Object Name) -join ",") + "  plugin=" + (Test-Path "$($_.FullName)\revit_mcp_plugin") }
$pkg = (Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter "Claude_*" | Select-Object -First 1).FullName
$cfg = "$pkg\LocalCache\Roaming\Claude\claude_desktop_config.json"
$e = (Get-Content $cfg -Raw | ConvertFrom-Json).mcpServers.'revit-mcp'
"command: $($e.command)  existe=" + (Test-Path "$($e.command)")
"args0: $($e.args[0])  existe=" + (Test-Path "$($e.args[0])")
"node empaquetado: " + (& "$($e.command)" -v)
"--- fin bloque 4 ---"
# Esperado: command/args0 bajo la carpeta del AÑO MÁS ALTO instalado (el instalador ordena descendente).

# --- bloque 4b: quitar el BOM del config de Claude y verificar con JSON.parse (gotcha #29) ---
"claude antes: " + (Get-Process Claude -EA SilentlyContinue | Measure-Object).Count + "   exe: " + (Get-Process Claude -EA SilentlyContinue | Select-Object -First 1 -ExpandProperty Path)
Get-Process Claude -EA SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 6
"claude despues (debe ser 0): " + (Get-Process Claude -EA SilentlyContinue | Measure-Object).Count
$pkg = (Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter "Claude_*" | Select-Object -First 1).FullName
$cfg = "$pkg\LocalCache\Roaming\Claude\claude_desktop_config.json"
$bak = "$cfg.pre-revit-mcp.bak"
$srv = "$env:APPDATA\Autodesk\Revit\Addins\2026\revit_mcp_plugin\Commands\RevitMCPCommandSet\server"
$node = "$srv\runtime\node.exe"
$js = "try{JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));console.log('OK')}catch(e){console.log('FALLA: '+e.message)}"
"config antes: bytes " + (([IO.File]::ReadAllBytes($cfg))[0..2] -join ",") + "   node: " + (& $node -e $js $cfg)
"backup:       bytes " + (([IO.File]::ReadAllBytes($bak))[0..2] -join ",") + "   node: " + (& $node -e $js $bak)
$txt = [IO.File]::ReadAllText($cfg).TrimStart([char]0xFEFF)
$tiene = [bool](($txt | ConvertFrom-Json).mcpServers.'revit-mcp')
"revit-mcp en config antes: $tiene"
if (-not $tiene) { $o = [IO.File]::ReadAllText($bak).TrimStart([char]0xFEFF) | ConvertFrom-Json; if (-not $o.mcpServers) { $o | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([PSCustomObject]@{}) }; $o.mcpServers | Add-Member -NotePropertyName 'revit-mcp' -NotePropertyValue ([PSCustomObject]@{ command = $node; args = @("$srv\build\index.js") }) -Force; $txt = $o | ConvertTo-Json -Depth 10; "reconstruido desde el backup + revit-mcp" }
if ((Get-Process Claude -EA SilentlyContinue | Measure-Object).Count -eq 0) { Copy-Item $cfg "$cfg.con-bom.bak" -Force; [IO.File]::WriteAllText($cfg, $txt, (New-Object System.Text.UTF8Encoding $false)); "escrito sin BOM" } else { "NO escrito: Claude sigue abierto" }
"config despues: bytes " + (([IO.File]::ReadAllBytes($cfg))[0..2] -join ",") + "   node: " + (& $node -e $js $cfg)
"revit-mcp en config despues: " + [bool](([IO.File]::ReadAllText($cfg) | ConvertFrom-Json).mcpServers.'revit-mcp')
"--- fin bloque 4b ---"
# Esperado: "escrito sin BOM", "config despues: bytes 123,...   node: OK" y "revit-mcp en config despues: True".
# "config antes: bytes 239,187,191" confirma la BOM; "123" = sin BOM. Ajusta el año de $srv al Revit mas alto (gotcha #27).
# Corrido en M4MEP-LZUANICH el 2026-09-14 por la rama de recuperacion: Claude ya habia borrado la entrada.

# --- bloque 5: abrir Revit con una muestra (ajusta el año del Revit.exe) ---
$f = Get-ChildItem "C:\ProgramData\Autodesk\RVT 20*\Samples" -Filter *.rvt -EA SilentlyContinue | Where-Object Name -notlike "*family*" | Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
"muestra: $f"
Start-Process "C:\Program Files\Autodesk\Revit 2026\Revit.exe" -ArgumentList "`"$f`""
# Luego, con mouse: Always Load (si aparece) -> Add-Ins -> Revit MCP Switch -> cerrar el aviso "Open Server".

# --- bloque 6: puerto 8080, arrancar Claude, leer log ---
$ids = @((Get-Process Revit -EA SilentlyContinue).Id)
"procesos revit: " + $ids.Count
"puertos revit despues: " + ((Get-NetTCPConnection -State Listen -EA SilentlyContinue | Where-Object { $ids -contains $_.OwningProcess } | ForEach-Object { "$($_.LocalAddress):$($_.LocalPort)" }) -join ", ")
$p = Get-NetTCPConnection -LocalPort 8080 -State Listen -EA SilentlyContinue | Select-Object -First 1
"8080 escucha por: " + $(if ($p) { (Get-Process -Id $p.OwningProcess).ProcessName } else { "NADIE" })
$t0 = Get-Date
"arranque claude local: " + $t0.ToString("HH:mm:ss") + "   utc: " + $t0.ToUniversalTime().ToString("HH:mm:ss")
$app = (Get-StartApps | Where-Object { $_.AppID -like "Claude_*" } | Select-Object -First 1).AppID
"app: $app"
Start-Process explorer.exe "shell:AppsFolder\$app"
Start-Sleep -Seconds 30
"claude procs: " + (Get-Process Claude -EA SilentlyContinue | Measure-Object).Count
$pkg = (Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter "Claude_*" | Select-Object -First 1).FullName
$cfg = "$pkg\LocalCache\Roaming\Claude\claude_desktop_config.json"
"revit-mcp sigue en config: " + [bool]((Get-Content $cfg -Raw | ConvertFrom-Json).mcpServers.'revit-mcp')
Get-Content "$pkg\LocalCache\Roaming\Claude\logs\main.log" -Tail 400 | Where-Object { $_ -match 'revit|localMcpBridge' } | Select-Object -Last 12
"--- fin bloque 6 ---"

# --- bloque 7: config tras arranque ---
$pkg = (Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter "Claude_*" | Select-Object -First 1).FullName
"revit-mcp sigue en config: " + [bool]((Get-Content "$pkg\LocalCache\Roaming\Claude\claude_desktop_config.json" -Raw | ConvertFrom-Json).mcpServers.'revit-mcp')
# Verificación final (fuera de la terminal, en un chat NORMAL de Claude Desktop):
#   "¿Qué información general tiene este modelo de Revit? Lista los niveles y cuántas paredes hay en cada uno."
