---
description: Instalación guiada del puente Claude Desktop ↔ Revit (MCP), eligiendo la ruta correcta según la situación de la máquina. Úsalo cuando pidan "instalar el puente Claude-Revit", "conectar Claude a Revit en una máquina nueva", "instalar revit-mcp", o al preparar el equipo de un compañero (directo o por RDP). Detecta versiones de Revit, pyRevit y Claude Desktop, elige Ruta A (C#/instalador 1-clic) o Ruta B (pyRevit Routes + Python) y verifica end-to-end.
---

# revit-install — Instalación guiada por situación

Fuente de verdad: lee PRIMERO `${CLAUDE_PLUGIN_ROOT}/skills/connect-claude-revit/SKILL.md` (gotchas) y ten a mano `${CLAUDE_PLUGIN_ROOT}/skills/connect-claude-revit/RUNBOOK.md` (pasos exactos). Este skill solo decide QUÉ ruta seguir y en QUÉ modo; los pasos viven en el RUNBOOK.

## Paso 0 — Detecta el MODO de ejecución

| Situación | Modo |
|---|---|
| Claude Code corre EN la Windows que tiene Revit | **Ejecutor**: corre tú mismo los pasos automatizables (descarga/clone, config JSON, unblock de DLLs) y pide al humano solo la UI de Revit y el reinicio de Claude Desktop |
| Claude Code corre en otra máquina (macOS, o guiando a IT por RDP/teléfono) | **Copiloto**: entrega los comandos de PowerShell en bloques copiables, UNO por vez, y espera el output antes del siguiente. Rutas cortas siempre (gotcha #5: las rutas largas se parten al pegar en terminales remotos) |

## Paso 1 — Inventario de la máquina (PowerShell en la Windows)

```powershell
Get-ChildItem "C:\Program Files\Autodesk" -Directory -Filter "Revit*" | Select-Object Name
Test-Path "$env:APPDATA\pyRevit"
Test-Path "$env:LOCALAPPDATA\AnthropicClaude"   # Claude Desktop instalado
Get-NetTCPConnection -LocalPort 8080,48884 -ErrorAction SilentlyContinue | Select-Object LocalPort,State
```

Registra: versiones de Revit, ¿pyRevit presente?, ¿Claude Desktop instalado y con sesión?, ¿puertos libres?

## Paso 2 — Elige la ruta

**Default: Ruta A** (LuDattilo, instalador 1-clic) — es la probada en Mallol (2 instalaciones verificadas end-to-end).

Cambia a **Ruta B** (pyRevit Routes + Python) solo si aplica alguna:
- El instalador de la Ruta A falló y no se pudo resolver con los gotchas.
- La oficina ya usa pyRevit activamente y prefiere ese stack.
- Necesitan tools exclusivas de B: `launch_revit`, `list_revit_installations`, `execute_revit_code` (IronPython directo).

Reglas por versión de Revit:
- **Revit 2023** → solo Ruta A (pyRevit no confirma soporte 2023).
- **2024–2026** → cualquiera de las dos; A por default.
- **Revit 2027** → A lo declara soportado; B es inmadura (el motor IronPython a veces no arranca) — si eliges B, exige el health-check `http://localhost:48884/revit_mcp/status/` = `healthy` antes de continuar.
- **Varias versiones instaladas** → gotcha #7: el instalador A las configura todas pero la config de Claude apunta a UNA; no importa cuál.

Si hay dudas reales entre A y B, di cuál recomiendas y por qué en 2 líneas, y avanza con la recomendada salvo que el usuario frene.

## Paso 3 — Ejecuta según el RUNBOOK

- **Ruta A**: RUNBOOK pasos 1–5. Gotchas críticos en orden de aparición: no correr desde `System32` (#1), Revit cerrado durante el install (#2), Switch gris = falta modelo abierto (#3), el Switch abre un diálogo y hay que pulsar **Open Server** (#6), reinicio REAL de Claude Desktop con `Get-Process Claude | Stop-Process -Force` (#4).
- **Ruta B**: RUNBOOK anexo B1–B5. El health-check B3 es obligatorio antes de tocar la config de Claude.

## Paso 4 — Verificación end-to-end (OBLIGATORIA)

No digas "instalado" ni "listo" sin esto:

1. Modelo de PRUEBA abierto en Revit (nunca proyecto real) + puente encendido (A: Open Server / B: Routes activo).
2. En Claude Desktop: *"¿Qué información general tiene este modelo de Revit?"* y *"Lista los niveles y cuántas paredes hay en cada uno."*
3. Solo si devuelve datos reales del modelo → conectado. Registra fecha, máquina, versiones (plugin, Node/uv, Revit, Windows) en la sección "Versiones de referencia" del SKILL de conocimiento.
4. Entrega SIEMPRE los avisos de seguridad al usuario final (modelo de prueba, días en read-only, undo no agrupado, gotchas al crear geometría).

Si la verificación falla → invoca el skill `revit-diagnose` de este plugin.
