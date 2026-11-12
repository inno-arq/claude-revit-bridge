@echo off
chcp 65001 >nul
title Revit Bridge - Instalador

echo.
echo =====================================
echo    REVIT BRIDGE - Instalador
echo    Conecta tu Revit con Claude
echo =====================================
echo.

:: Pedir email
set /p EMAIL="Tu email de Claude: "

if "%EMAIL%"=="" (
    echo.
    echo ERROR: Debes ingresar tu email.
    pause
    exit /b 1
)

echo.
echo Instalando... esto puede tomar unos minutos.
echo.

:: Descargar y ejecutar el instalador silencioso
powershell -ExecutionPolicy Bypass -Command "& { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $script = (New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/inno-arq/claude-revit-bridge/main/installer/silent-install.ps1'); $scriptBlock = [scriptblock]::Create($script); & $scriptBlock -Email '%EMAIL%' }"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ERROR: La instalacion fallo. Revisa los mensajes arriba.
    pause
    exit /b 1
)

echo.
echo =====================================
echo    INSTALACION COMPLETADA
echo =====================================
echo.
echo Siguiente paso:
echo 1. Abre Revit con un modelo
echo 2. Add-Ins ^> Revit MCP Switch ^> clic
echo 3. En Claude: "Que archivo de Revit tengo?"
echo.
pause
