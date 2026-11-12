<#
.SYNOPSIS
    Instalador silencioso de Revit Bridge - conecta Revit con Claude
.DESCRIPTION
    Este script se ejecuta desde el instalador .exe y hace todo automaticamente:
    1. Instala el plugin de Revit
    2. Descarga cloudflared
    3. Configura el tunel como servicio
    4. Registra el equipo en el hub
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Email,

    [string]$HubUrl = "https://revit-hub-476812260498.us-central1.run.app"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# --- Configuracion ---
$BridgeDir = "$env:LOCALAPPDATA\RevitBridge"
$LogFile = "$BridgeDir\install.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
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

# --- Crear directorio ---
New-Item -ItemType Directory -Force -Path $BridgeDir | Out-Null
Write-Log "Iniciando instalacion silenciosa"
Write-Log "Email: $Email"

# --- Verificar Revit ---
$revitYear = Test-RevitInstalled
if (-not $revitYear) {
    Write-Log "Revit no encontrado (2023-2027)" "ERROR"
    throw "Revit no esta instalado. Instala Revit primero."
}
Write-Log "Revit $revitYear detectado"

# --- Cerrar Revit si esta abierto ---
$revitProc = Get-Process Revit -ErrorAction SilentlyContinue
if ($revitProc) {
    Write-Log "Cerrando Revit para instalar el plugin"
    $revitProc | Stop-Process -Force
    Start-Sleep -Seconds 3
}

# --- Paso 1: Instalar plugin de Revit ---
Write-Log "Descargando plugin de Revit..."
$installerUrl = "https://raw.githubusercontent.com/LuDattilo/revit-mcp-server/main/scripts/install.ps1"
$installerPath = "$BridgeDir\install-plugin.ps1"

Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing

Write-Log "Instalando plugin..."
& powershell -ExecutionPolicy Bypass -File $installerPath -SkipNodeCheck 2>&1 | Out-File "$BridgeDir\plugin-install.log"

# Verificar instalacion
$pluginDir = "$env:APPDATA\Autodesk\Revit\Addins\$revitYear\revit_mcp_plugin"
if (-not (Test-Path $pluginDir)) {
    Write-Log "Plugin no instalado" "ERROR"
    throw "Error instalando el plugin de Revit"
}
Write-Log "Plugin instalado en $pluginDir"

# --- Paso 2: Descargar cloudflared ---
Write-Log "Descargando cloudflared..."
$cloudflaredPath = "$BridgeDir\cloudflared.exe"

if (-not (Test-Path $cloudflaredPath)) {
    $cloudflaredUrl = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
    Invoke-WebRequest -Uri $cloudflaredUrl -OutFile $cloudflaredPath -UseBasicParsing
}
Write-Log "cloudflared descargado"

# --- Paso 3: Crear script de inicio del tunel ---
$startScript = @"
`$ErrorActionPreference = "SilentlyContinue"
`$BridgeDir = "$BridgeDir"
`$LogFile = "`$BridgeDir\tunnel.log"
`$HubUrl = "$HubUrl"
`$Email = "$Email"

# Esperar a que Revit abra el puerto 8080
`$maxWait = 120
`$waited = 0
while (`$waited -lt `$maxWait) {
    `$port = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
    if (`$port) { break }
    Start-Sleep -Seconds 5
    `$waited += 5
}

if (-not `$port) {
    Add-Content -Path `$LogFile -Value "[`$(Get-Date)] Revit MCP no detectado en puerto 8080"
    exit 1
}

Add-Content -Path `$LogFile -Value "[`$(Get-Date)] Revit MCP detectado, iniciando tunel..."

# Iniciar quick tunnel
`$tunnelProc = Start-Process -FilePath "`$BridgeDir\cloudflared.exe" ``
    -ArgumentList "tunnel","--url","http://localhost:8080" ``
    -WindowStyle Hidden -PassThru ``
    -RedirectStandardError "`$BridgeDir\tunnel-stderr.log"

# Esperar URL del tunel
`$tunnelUrl = `$null
for (`$i = 0; `$i -lt 30; `$i++) {
    Start-Sleep -Seconds 1
    `$log = Get-Content "`$BridgeDir\tunnel-stderr.log" -Raw -ErrorAction SilentlyContinue
    if (`$log -match "https://[a-z0-9-]+\.trycloudflare\.com") {
        `$tunnelUrl = `$Matches[0]
        break
    }
}

if (-not `$tunnelUrl) {
    Add-Content -Path `$LogFile -Value "[`$(Get-Date)] No se pudo obtener URL del tunel"
    exit 1
}

Add-Content -Path `$LogFile -Value "[`$(Get-Date)] Tunel activo: `$tunnelUrl"

# Registrar en hub
`$body = @{
    tunnelUrl = `$tunnelUrl
    email = `$Email
    metadata = @{
        deviceName = `$env:COMPUTERNAME
        revitYear = (Get-ChildItem "C:\Program Files\Autodesk" -Directory -Filter "Revit*" | Select-Object -First 1).Name -replace "Revit ",""
        installedAt = (Get-Date -Format "o")
    }
} | ConvertTo-Json

try {
    `$response = Invoke-RestMethod -Uri "`$HubUrl/register" -Method POST -Body `$body -ContentType "application/json"
    Add-Content -Path `$LogFile -Value "[`$(Get-Date)] Registrado en hub: `$(`$response.deviceId)"
} catch {
    Add-Content -Path `$LogFile -Value "[`$(Get-Date)] Error registrando en hub: `$_"
}

# Mantener proceso vivo
Wait-Process -Id `$tunnelProc.Id
"@

Set-Content -Path "$BridgeDir\start-tunnel.ps1" -Value $startScript -Encoding UTF8
Write-Log "Script de tunel creado"

# --- Paso 4: Crear tarea programada para iniciar con Windows ---
$taskName = "RevitBridge"
$taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($taskExists) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$BridgeDir\start-tunnel.ps1`""

$trigger = New-ScheduledTaskTrigger -AtLogon

$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Limited

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null
Write-Log "Tarea programada creada: $taskName"

# --- Paso 5: Guardar configuracion ---
$config = @{
    email = $Email
    hubUrl = $HubUrl
    revitYear = $revitYear
    installedAt = (Get-Date -Format "o")
} | ConvertTo-Json

Set-Content -Path "$BridgeDir\config.json" -Value $config -Encoding UTF8
Write-Log "Configuracion guardada"

# --- Crear acceso directo en escritorio ---
$shortcutPath = [Environment]::GetFolderPath('Desktop') + "\Revit Bridge.lnk"
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$BridgeDir\start-tunnel.ps1`""
$shortcut.IconLocation = "C:\Program Files\Autodesk\Revit $revitYear\Revit.exe,0"
$shortcut.Description = "Conecta Revit con Claude"
$shortcut.Save()
Write-Log "Acceso directo creado en escritorio"

Write-Log "Instalacion completada exitosamente"

# Mostrar mensaje de exito
Write-Host @"

====================================
   REVIT BRIDGE INSTALADO
====================================

Tu Revit esta conectado a Claude con el email:
  $Email

SIGUIENTE PASO:
1. Abre Revit con un modelo (.rvt)
2. Ve a Add-Ins > Revit MCP Switch > clic
3. En Claude, pregunta: "Que archivo de Revit tengo abierto?"

El tunel se iniciara automaticamente cuando abras Revit.

"@
