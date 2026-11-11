<#
.SYNOPSIS
    Instalador de un click para Revit Bridge - conecta tu Revit con Claude

.DESCRIPTION
    Este script:
    1. Instala el plugin de Revit (LuDattilo/revit-mcp-server)
    2. Descarga cloudflared (portable, sin admin)
    3. Configura el gateway y watchdog
    4. Crea un tunel de Cloudflare
    5. Registra el equipo en Revit Hub
    6. Muestra las credenciales para conectar desde Claude

.PARAMETER HubUrl
    URL del Revit Hub. Default: https://revit-hub-xxxxx.run.app

.PARAMETER TunnelToken
    Token de tunel con nombre (opcional). Si no se provee, usa quick tunnel.

.PARAMETER DeviceName
    Nombre amigable del equipo (opcional). Default: nombre del PC.

.EXAMPLE
    irm https://revit.mallol.dev/install | iex

.EXAMPLE
    .\setup-revit-bridge.ps1 -DeviceName "PC-Arquitectura-01"
#>

param(
    [string]$HubUrl = "https://revit-hub-476812260498.us-central1.run.app",
    [string]$TunnelToken = "",
    [string]$DeviceName = $env:COMPUTERNAME,
    [string]$Email = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"  # Faster downloads

# --- Configuration ---
$BridgeDir = "$env:USERPROFILE\revit-bridge"
$LogFile = "$BridgeDir\setup.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Write-Host $line -ForegroundColor $(if ($Level -eq "ERROR") { "Red" } elseif ($Level -eq "WARN") { "Yellow" } else { "White" })
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

function Test-RevitInstalled {
    $years = 2023..2027
    foreach ($y in $years) {
        $path = "C:\Program Files\Autodesk\Revit $y\Revit.exe"
        if (Test-Path $path) { return $y }
    }
    return $null
}

# --- Pre-flight checks ---
Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "   REVIT BRIDGE - Setup Wizard" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Get user email if not provided
if (-not $Email) {
    Write-Host "Para conectar tu Revit con Claude, necesito tu email." -ForegroundColor Yellow
    Write-Host "(Usa el mismo email con el que accedes a Claude)" -ForegroundColor Gray
    Write-Host ""
    $Email = Read-Host "Tu email"

    if (-not $Email -or $Email -notmatch "^[\w\.-]+@[\w\.-]+\.\w+$") {
        Write-Host "Email invalido. Vuelve a ejecutar el instalador." -ForegroundColor Red
        exit 1
    }
}
Write-Host ""

New-Item -ItemType Directory -Force -Path $BridgeDir | Out-Null
Write-Log "Iniciando instalacion en $BridgeDir"

# Check Revit
$revitYear = Test-RevitInstalled
if (-not $revitYear) {
    Write-Log "No se encontro Revit instalado (2023-2027)" "ERROR"
    Write-Host ""
    Write-Host "Este script requiere Autodesk Revit instalado." -ForegroundColor Red
    Write-Host "Versiones soportadas: 2023, 2024, 2025, 2026, 2027" -ForegroundColor Red
    exit 1
}
Write-Log "Revit $revitYear detectado"

# Check if Revit is running
$revitProc = Get-Process Revit -ErrorAction SilentlyContinue
if ($revitProc) {
    Write-Log "Revit esta corriendo - cerrando para instalar el plugin" "WARN"
    Write-Host ""
    Write-Host "Revit debe cerrarse para instalar el plugin." -ForegroundColor Yellow
    $confirm = Read-Host "Cerrar Revit ahora? (S/N)"
    if ($confirm -match "^[SsYy]") {
        $revitProc | Stop-Process -Force
        Start-Sleep -Seconds 3
    } else {
        Write-Host "Cierra Revit manualmente y vuelve a ejecutar el instalador." -ForegroundColor Yellow
        exit 1
    }
}

# --- Step 1: Install Revit MCP Plugin ---
Write-Host ""
Write-Host "[1/5] Instalando plugin de Revit..." -ForegroundColor Green

$installerPath = "$BridgeDir\install-revit-mcp.ps1"
$installerUrl = "https://raw.githubusercontent.com/LuDattilo/revit-mcp-server/main/scripts/install.ps1"

Write-Log "Descargando instalador desde $installerUrl"
Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing

# Run installer with SkipNodeCheck (uses bundled Node)
Write-Log "Ejecutando instalador del plugin"
& powershell -ExecutionPolicy Bypass -File $installerPath -SkipNodeCheck 2>&1 | Tee-Object -FilePath "$BridgeDir\plugin-install.log"

# Verify installation
$pluginDir = "$env:APPDATA\Autodesk\Revit\Addins\$revitYear\revit_mcp_plugin"
if (-not (Test-Path $pluginDir)) {
    Write-Log "Plugin no instalado correctamente" "ERROR"
    exit 1
}
Write-Log "Plugin instalado en $pluginDir"

# --- Step 2: Download cloudflared ---
Write-Host ""
Write-Host "[2/5] Descargando cloudflared..." -ForegroundColor Green

$cloudflaredPath = "$BridgeDir\cloudflared.exe"
if (-not (Test-Path $cloudflaredPath)) {
    $cloudflaredUrl = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
    Write-Log "Descargando cloudflared"
    Invoke-WebRequest -Uri $cloudflaredUrl -OutFile $cloudflaredPath -UseBasicParsing
}
Write-Log "cloudflared listo en $cloudflaredPath"

# --- Step 3: Setup Gateway ---
Write-Host ""
Write-Host "[3/5] Configurando gateway..." -ForegroundColor Green

# Generate local MCP token
$mcpToken = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 32 | ForEach-Object { [char]$_ })

# Download gateway.js
$gatewayUrl = "https://raw.githubusercontent.com/inno-arq/claude-revit-bridge/main/skills/connect-claude-revit/assets/gateway.js"
$gatewayPath = "$BridgeDir\gateway.js"
Write-Log "Descargando gateway"
Invoke-WebRequest -Uri $gatewayUrl -OutFile $gatewayPath -UseBasicParsing

# Download watchdog.ps1
$watchdogUrl = "https://raw.githubusercontent.com/inno-arq/claude-revit-bridge/main/skills/connect-claude-revit/assets/watchdog.ps1"
$watchdogPath = "$BridgeDir\watchdog.ps1"
Write-Log "Descargando watchdog"
Invoke-WebRequest -Uri $watchdogUrl -OutFile $watchdogPath -UseBasicParsing

# Find bundled Node from the plugin
$nodePath = Get-ChildItem "$pluginDir" -Recurse -Filter "node.exe" | Select-Object -First 1 -ExpandProperty FullName
if (-not $nodePath) {
    Write-Log "No se encontro node.exe en el plugin" "ERROR"
    exit 1
}
Write-Log "Node encontrado: $nodePath"

# --- Step 4: Create Tunnel ---
Write-Host ""
Write-Host "[4/5] Creando tunel de Cloudflare..." -ForegroundColor Green

# Start gateway first
$env:MCP_TOKEN = $mcpToken
$env:PORT = "8000"

$gatewayProc = Start-Process -FilePath $nodePath -ArgumentList $gatewayPath `
    -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput "$BridgeDir\gateway.log" `
    -RedirectStandardError "$BridgeDir\gateway-err.log"

Start-Sleep -Seconds 2
if ($gatewayProc.HasExited) {
    Write-Log "Gateway fallo al iniciar" "ERROR"
    Get-Content "$BridgeDir\gateway-err.log" | Write-Host -ForegroundColor Red
    exit 1
}
Write-Log "Gateway iniciado (PID: $($gatewayProc.Id))"

# Start cloudflared tunnel
if ($TunnelToken) {
    # Named tunnel
    Write-Log "Usando tunel con nombre"
    $tunnelProc = Start-Process -FilePath $cloudflaredPath `
        -ArgumentList "tunnel","run","--token",$TunnelToken `
        -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput "$BridgeDir\tunnel.log" `
        -RedirectStandardError "$BridgeDir\tunnel-err.log"

    # For named tunnels, URL is predefined - user must provide it
    Write-Host ""
    Write-Host "Tunel con nombre iniciado." -ForegroundColor Green
    Write-Host "Ingresa la URL publica del tunel (ej: https://revit-pc01.ejemplo.com):" -ForegroundColor Yellow
    $tunnelUrl = Read-Host
} else {
    # Quick tunnel
    Write-Log "Creando quick tunnel"
    $tunnelProc = Start-Process -FilePath $cloudflaredPath `
        -ArgumentList "tunnel","--url","http://localhost:8000" `
        -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput "$BridgeDir\tunnel.log" `
        -RedirectStandardError "$BridgeDir\tunnel-err.log"

    # Wait for tunnel URL to appear in logs
    $maxWait = 30
    $tunnelUrl = $null
    for ($i = 0; $i -lt $maxWait; $i++) {
        Start-Sleep -Seconds 1
        $log = Get-Content "$BridgeDir\tunnel-err.log" -Raw -ErrorAction SilentlyContinue
        if ($log -match "https://[a-z0-9-]+\.trycloudflare\.com") {
            $tunnelUrl = $Matches[0]
            break
        }
    }

    if (-not $tunnelUrl) {
        Write-Log "No se pudo obtener la URL del tunel" "ERROR"
        Get-Content "$BridgeDir\tunnel-err.log" | Write-Host -ForegroundColor Red
        exit 1
    }
}

Write-Log "Tunel activo: $tunnelUrl"

# --- Step 5: Register with Hub ---
Write-Host ""
Write-Host "[5/5] Registrando en Revit Hub..." -ForegroundColor Green

$fullUrl = "$tunnelUrl/mcp/$mcpToken"
$registerBody = @{
    tunnelUrl = $fullUrl
    email = $Email
    metadata = @{
        deviceName = $DeviceName
        revitYear = $revitYear
        installedAt = (Get-Date -Format "o")
    }
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri "$HubUrl/register" -Method POST -Body $registerBody -ContentType "application/json"
    $deviceId = $response.deviceId
    $apiKey = $response.apiKey
    Write-Log "Registrado como dispositivo: $deviceId"
} catch {
    Write-Log "Error registrando en el hub: $_" "ERROR"
    Write-Host ""
    Write-Host "No se pudo registrar en el hub. Puedes usar la conexion directa:" -ForegroundColor Yellow
    $deviceId = "local"
    $apiKey = $mcpToken
}

# Save credentials
$creds = @{
    deviceId = $deviceId
    apiKey = $apiKey
    tunnelUrl = $tunnelUrl
    mcpToken = $mcpToken
    hubUrl = $HubUrl
    deviceName = $DeviceName
    revitYear = $revitYear
} | ConvertTo-Json

Set-Content -Path "$BridgeDir\credentials.json" -Value $creds -Encoding UTF8

# Setup auto-start on login
$startupPath = [Environment]::GetFolderPath('Startup')
$shortcutPath = "$startupPath\RevitBridge.lnk"
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$watchdogPath`""
$shortcut.WorkingDirectory = $BridgeDir
$shortcut.Save()
Write-Log "Auto-inicio configurado"

# --- Done! ---
Write-Host ""
Write-Host "=====================================" -ForegroundColor Green
Write-Host "   INSTALACION COMPLETADA!" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
Write-Host ""
Write-Host "Tu Revit esta conectado a Claude con el email:" -ForegroundColor White
Write-Host "  $Email" -ForegroundColor Cyan
Write-Host ""
Write-Host "SIGUIENTE PASO:" -ForegroundColor Green
Write-Host "1. Abre Revit con un modelo (.rvt)" -ForegroundColor White
Write-Host "2. Ve a Add-Ins > Revit MCP Switch > click" -ForegroundColor White
Write-Host "3. CIERRA el dialogo 'Open Server' (importante!)" -ForegroundColor White
Write-Host "4. En Claude, pregunta: 'Que archivo de Revit tengo abierto?'" -ForegroundColor White
Write-Host ""
Write-Host "Eso es todo. Claude detectara tu Revit automaticamente." -ForegroundColor Green
Write-Host ""
Write-Host "(Credenciales guardadas en: $BridgeDir\credentials.json)" -ForegroundColor Gray
