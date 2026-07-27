---
description: Diagnóstico del puente Claude Desktop ↔ Revit cuando ya está instalado pero no funciona. Úsalo cuando digan "Claude no ve Revit", "revit-mcp no aparece", "no devuelve datos del modelo", "el MCP de Revit dejó de funcionar", o tras una instalación cuya verificación falló. Triage ordenado por frecuencia real de causas (Mallol, 2 instalaciones).
---

# revit-diagnose — Triage del puente Claude ↔ Revit

Contexto completo en `${CLAUDE_PLUGIN_ROOT}/skills/connect-claude-revit/SKILL.md` (gotchas numerados) y la tabla de solución de problemas del `${CLAUDE_PLUGIN_ROOT}/skills/connect-claude-revit/RUNBOOK.md`.

## Antes de nada: ¿qué ruta usa esta máquina?

- **Ruta A** (add-in C#): panel "Revit MCP Plugin" en la pestaña Add-Ins de Revit; server en `localhost:8080`; config de Claude apunta a `node.exe` + `build\index.js` bajo `%APPDATA%\Autodesk\Revit\Addins\<año>\revit_mcp_plugin`.
- **Ruta B** (pyRevit): pestaña pyRevit presente; server Routes en `localhost:48884`; config de Claude usa `uv ... main.py`.

Míralo en Claude Desktop → Settings → Developer → Edit Config. No asumas.

## Triage en orden de frecuencia (parar en el primer hit)

1. **¿Claude Desktop se reinició DE VERDAD?** — Causa #1 histórica. La X solo manda a bandeja y no relee config. Si Settings → Developer está vacío o no lista el server:
   ```powershell
   Get-Process Claude | Stop-Process -Force
   ```
   y reabrir desde el menú Inicio.

2. **¿El puente está encendido en Revit?**
   - Ruta A: pulsar **Revit MCP Switch** abre un diálogo — hay que pulsar **Open Server** (cerrarlo con "Cerrar" NO arranca nada, aunque Claude marque `revit-mcp` como `running`).
   - Ruta B: pyRevit → Settings → Routes → "Routes Server" activado. Health-check en navegador: `http://localhost:48884/revit_mcp/status/` debe devolver `healthy`.

3. **¿Hay un modelo abierto?** — Sin modelo, el Switch está gris (A) y no hay documento que consultar (B). El puente muere al cerrar el modelo.

4. **¿El add-in cargó?** (Ruta A) — Si solo aparece *Switch* sin *Panel*, o nada: DLLs bloqueados por instalar con Revit abierto:
   ```powershell
   Get-ChildItem "$env:APPDATA\Autodesk\Revit\Addins\<año>\revit_mcp_plugin" -Recurse | Unblock-File
   ```
   Reabrir Revit → "Always Load".

5. **¿La config apunta a archivos que existen?** — Comparar rutas de la config con las reales. Usa rutas cortas con `$env:APPDATA` (las largas se parten al pegar por RDP y dan falsos `False` en `Test-Path` con "Illegal characters in path").

6. **¿El server arranca a mano?** — Aísla Claude vs server:
   - Ruta A: `& $node $idx` (variables del SKILL de conocimiento). Se queda esperando = server sano, culpa de Claude. Error rojo = ahí está la causa.
   - Ruta B: `uv run --with "mcp[cli]" mcp run <ruta a main.py>`.

7. **Logs de Claude Desktop**:
   ```powershell
   Get-Content "$env:APPDATA\Claude\logs\mcp.log" -Tail 40
   ```

8. **Puertos** — 8080 (A) o 48884 (B) ocupados por otra app: `Get-NetTCPConnection -LocalPort 8080,48884`.

## Cierre

Resuelto el hallazgo, repite SIEMPRE la verificación end-to-end (pregunta de niveles/paredes sobre un modelo de prueba en Claude Desktop) antes de declararlo funcionando, y anota el caso nuevo en los gotchas del SKILL de conocimiento si no estaba.
