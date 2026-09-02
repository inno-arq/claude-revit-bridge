<#
.SYNOPSIS
    Despliega el puente Revit -> Cowork (Ruta C) en un equipo Windows.

.DESCRIPTION
    Deja funcionando: gateway HTTP stateless + tunel Cloudflare con nombre + watchdog.
    No requiere permisos de administrador. Escribe todo bajo el perfil del usuario.

    Requisitos previos (Ruta A ya instalada):
      - Revit con el add-in revit_mcp_plugin y "Open Server" pulsado.
      - Claude Desktop abierto al menos una vez, con el bloque mcpServers."revit-mcp".
      - Node.js del sistema (el empaquetado del plugin no basta para este gateway).
      - Un tunel creado en el panel de Cloudflare por quien administre el dominio,
        con Public Hostname apuntando a http://127.0.0.1:8000  (NUNCA localhost: gotcha #18).

.PARAMETER PublicHostname
    Hostname publico del tunel. Ej: revit-mcp-chim.mallolarquitectos.com

.PARAMETER SkipTunnel
    Solo configura el gateway local, sin cloudflared.

.EXAMPLE
    .\deploy-revit-bridge.ps1 -PublicHostname revit-mcp-pc07.mallolarquitectos.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $PublicHostname,
    [switch] $SkipTunnel
)

$ErrorActionPreference = 'Stop'
$dst   = "$env:USERPROFILE\revit-gateway"
$tools = "$env:USERPROFILE\tools"
$cf    = "$tools\cloudflared.exe"

function Paso($m) { Write-Host "`n[*] $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  [+] $m" -ForegroundColor Green }
function Aviso($m){ Write-Host "  [!] $m" -ForegroundColor Yellow }
function Alto($m) { Write-Host "  [-] $m" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------- 0) requisitos
Paso "Comprobando requisitos"

$nodeVer = (cmd /c "node -v 2>nul")
if (-not $nodeVer) { Alto "Falta Node.js del sistema. Instalalo (winget install OpenJS.NodeJS.LTS) y reabre PowerShell." }
Ok "Node del sistema: $nodeVer"

$cfgPath = $null
$pkg = Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter "Claude_*" -EA SilentlyContinue | Select-Object -First 1
if ($pkg) { $cfgPath = Join-Path $pkg.FullName "LocalCache\Roaming\Claude\claude_desktop_config.json" }
if (-not (Test-Path $cfgPath)) { $cfgPath = "$env:APPDATA\Claude\claude_desktop_config.json" }
if (-not (Test-Path $cfgPath)) { Alto "No encuentro claude_desktop_config.json. Abre Claude Desktop una vez e instala la Ruta A primero." }

$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
if (-not $cfg.mcpServers.'revit-mcp'.command) { Alto "El config no tiene el bloque revit-mcp. Instala la Ruta A antes de esto." }
Ok "Config de Claude localizado y con revit-mcp"

$ids = (Get-Process Revit -EA SilentlyContinue).Id
$addin = [bool](Get-NetTCPConnection -LocalPort 8080 -State Listen -EA SilentlyContinue | Where-Object { $ids -contains $_.OwningProcess })
if ($addin) { Ok "Add-in escuchando en 8080" } else { Aviso "El add-in NO escucha en 8080: abre Revit con un modelo y pulsa Add-Ins > Revit MCP Switch > Open Server" }

# ------------------------------------------------------------------ 1) archivos
Paso "Instalando archivos en $dst"
New-Item -ItemType Directory -Force -Path $dst, $tools | Out-Null

$src = Split-Path -Parent $MyInvocation.MyCommand.Path
foreach ($f in @('gateway.js', 'watchdog.ps1')) {
    if (-not (Test-Path "$src\$f")) { Alto "Falta $f junto a este script." }
    Copy-Item "$src\$f" "$dst\$f" -Force
}
& node --check "$dst\gateway.js"
if (-not $?) { Alto "gateway.js no pasa node --check" }
Ok "gateway.js y watchdog.ps1 instalados"

# -------------------------------------------------------------------- 2) tokens
Paso "Token del gateway"
if (Test-Path "$dst\token.txt") {
    Ok "Ya existia, se conserva"
} else {
    $b = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
    $tok = [Convert]::ToBase64String($b).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    Set-Content -Path "$dst\token.txt" -Value $tok -NoNewline -Encoding ascii
    Ok "Generado ($($tok.Length) caracteres)"
}

if (-not $SkipTunnel) {
    Paso "Token del tunel"
    if (Test-Path "$dst\tunnel-token.txt") {
        Ok "Ya existia, se conserva"
    } else {
        Write-Host "  Pega el token del tunel (Zero Trust > Networks > Tunnels). No se vera al pegar."
        $sec  = Read-Host "  Token" -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        $raw  = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

        # tolera que se pegue el comando completo del panel (gotcha #19)
        if ($raw -match '--token\s+(\S+)') { $tt = $Matches[1] } else { $tt = $raw }
        $tt = $tt.Trim().Trim([char]34, [char]39)

        if ($tt -notmatch '^eyJ') { Alto "El token no empieza por eyJ" }
        if ($tt -match '\s')      { Alto "El token contiene espacios" }
        if ($tt.Length -lt 120)   { Alto "Longitud sospechosa ($($tt.Length))" }

        Set-Content -Path "$dst\tunnel-token.txt" -Value $tt -NoNewline -Encoding ascii
        Ok "Guardado ($($tt.Length) caracteres)"
    }

    if (-not (Test-Path $cf)) {
        Paso "Descargando cloudflared (portable, sin admin)"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe" -OutFile $cf
        Ok (& $cf --version)
    } else {
        Ok "cloudflared ya presente"
    }
}

# ------------------------------------------------------------------ 3) watchdog
Paso "Registrando watchdog (cada 2 minutos)"
$cmd = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"$dst\watchdog.ps1\""
schtasks /Create /TN "revit-bridge-watchdog" /TR $cmd /SC MINUTE /MO 2 /F | Out-Null
if ($?) { Ok "Tarea revit-bridge-watchdog registrada" } else { Aviso "No se pudo registrar la tarea; habra que arrancar a mano" }

# ------------------------------------------------------------------- 4) arrancar
Paso "Arrancando gateway y tunel"
Get-Process node -EA SilentlyContinue | Stop-Process -Force
if (-not $SkipTunnel) { Get-Process cloudflared -EA SilentlyContinue | Stop-Process -Force }
Start-Sleep -Seconds 2
& "$dst\watchdog.ps1"
Start-Sleep -Seconds 15

$gwUp = [bool](Get-NetTCPConnection -LocalPort 8000 -State Listen -EA SilentlyContinue)
if ($gwUp) { Ok "Gateway escuchando en 127.0.0.1:8000" } else { Alto "El gateway no arranco. Mira $dst\gw.err.log" }
if (-not $SkipTunnel) {
    $tunUp = [bool](Get-Process cloudflared -EA SilentlyContinue)
    if ($tunUp) { Ok "cloudflared corriendo" } else { Aviso "cloudflared no arranco. Mira $dst\cloudflared.log" }
}

# --------------------------------------------------------------- 5) verificacion
Paso "Verificando"
$T = (Get-Content "$dst\token.txt" -Raw).Trim()
'{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | Set-Content -Encoding ascii "$env:TEMP\_rb_list.json"
'{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"get_project_info","arguments":{}}}' | Set-Content -Encoding ascii "$env:TEMP\_rb_call.json"

$c1 = (curl.exe -s -o NUL -w "%{http_code}" -X POST "http://127.0.0.1:8000/mcp"     -H "Content-Type: application/json" --data-binary "@$env:TEMP\_rb_list.json")
$c2 = (curl.exe -s -o NUL -w "%{http_code}" -X POST "http://127.0.0.1:8000/mcp/$T"  -H "Content-Type: application/json" --data-binary "@$env:TEMP\_rb_list.json")
Write-Host "  local sin token : $c1   (esperado 401)"
Write-Host "  local con token : $c2   (esperado 200)"

if (-not $SkipTunnel) {
    $B  = "https://$PublicHostname"
    $c3 = (curl.exe -s -o NUL -w "%{http_code}" -m 30 -X POST "$B/mcp"    -H "Content-Type: application/json" --data-binary "@$env:TEMP\_rb_list.json")
    $c4 = (curl.exe -s -o NUL -w "%{http_code}" -m 60 -X POST "$B/mcp/$T" -H "Content-Type: application/json" --data-binary "@$env:TEMP\_rb_list.json")
    Write-Host "  publico sin token : $c3   (esperado 401)"
    Write-Host "  publico con token : $c4   (esperado 200; si es 530 el tunel no conecta, si es 502 revisa que el origen sea 127.0.0.1:8000)"

    # el modo que usa Cowork (gotcha #22)
    $sse = (curl.exe -s -m 60 -X POST "$B/mcp/$T" -H "Content-Type: application/json" -H "Accept: text/event-stream" --data-binary "@$env:TEMP\_rb_call.json")
    if ($sse -match 'event: message') { Ok "SSE correcto (es lo que usa Cowork)" } else { Aviso "El endpoint no devolvio SSE; Cowork daria timeout en tools/call" }
}

Remove-Item "$env:TEMP\_rb_list.json", "$env:TEMP\_rb_call.json" -EA SilentlyContinue

# --------------------------------------------------------------------- 6) salida
$url = "https://$PublicHostname/mcp/$T"
Set-Content -Path "$dst\url-conector.txt" -Value $url -NoNewline -Encoding ascii
try { Set-Clipboard -Value $url; $clip = "y copiada al portapapeles" } catch { $clip = "" }

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Green
Write-Host " LISTO. URL del conector guardada en $dst\url-conector.txt $clip" -ForegroundColor Green
Write-Host " Termina en ...$($T.Substring($T.Length-6))   <- compara esto al pegarla" -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green
Write-Host ""
Write-Host " Siguiente paso, en Claude (lo hace un Owner de la organizacion):"
Write-Host "   Organization settings > Connectors > Add > Custom > Web"
Write-Host "   URL: pegar con Ctrl+V     Autenticacion: Ninguno"
Write-Host ""
Write-Host " NO imprimas la URL en pantalla ni la pases por chat: lleva el token dentro."
