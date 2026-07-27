---
description: Conectar Claude Desktop a Autodesk Revit vía MCP. Ruta A (default) usa el plugin revit-mcp-server de LuDattilo (C#, instalador de un clic, Revit 2023–2027); Ruta B (alternativa) usa pyRevit Routes + mcp-server-for-revit-python (puerto 48884). Úsalo cuando el usuario diga "conectar Claude a Revit", "MCP de Revit", "controlar Revit con IA", "revit-mcp", "pyRevit Routes", "instalar el puente Claude-Revit", o pida depurar por qué Claude no ve Revit. Toda la instalación ocurre en el equipo Windows del usuario (directo o en remoto por RDP desde otra Windows; normalmente lo ejecuta IT).
---

# connect-claude-revit — Puente Claude ↔ Autodesk Revit (MCP)

Procedimiento probado (2026-06-01, Mallol, máquina del compañero `lmarin`) para conectar **Claude Desktop** a **Revit** por MCP. Documento detallado e imprimible: ver [RUNBOOK.md](./RUNBOOK.md).

## Restricción que condiciona TODO

Revit **solo existe en Windows** y su API solo es accesible *dentro* del proceso de Revit. La cadena es:

```
Claude Desktop (cliente MCP) → MCP server (Node) → add-in C# dentro de Revit → Revit API
```

**El MCP server y el add-in viven en la misma máquina Windows donde corre Revit.** La instalación la hace IT sobre el **equipo Windows del usuario**, directamente o **en remoto por RDP desde otra Windows**. El método de acceso no influye en el cableado — todo es `localhost` en esa Windows.

## Stack elegido (y por qué)

**Ruta A (default): `LuDattilo/revit-mcp-server`** — add-in **C#** + MCP server TypeScript con **Node empaquetado**, instalador PowerShell de un solo comando.

- Soporta **Revit 2023, 2024, 2025, 2026, 2027** (2023 = .NET Framework 4.8, "fully tested").
- Auto-configura `claude_desktop_config.json`.
- 124 tools (QA, CRUD de elementos, export, clashes) + panel de chat opcional dentro de Revit.
- Se eligió sobre el stack pyRevit porque **pyRevit no confirma soporte 2023** y tiene más pasos. Para "que simplemente funcione" en la máquina de un compañero, el instalador 1-clic gana.

**Ruta B (alternativa): pyRevit Routes + `mcp-servers-for-revit/mcp-server-for-revit-python`** — ver sección abajo. Úsala si el instalador de LuDattilo falla, si la oficina ya usa pyRevit, o si hacen falta sus tools exclusivas (`launch_revit`, `execute_revit_code` con IronPython directo).

## Flujo de instalación (resumen)

Todo en PowerShell **dentro de la Windows**:

1. **Prerrequisitos**: Revit instalado; Claude Desktop instalado y con sesión iniciada. Node.js lo ofrece el propio instalador (elige `1`).
2. **Descargar y revisar** el script (no `irm | iex` a ciegas en una máquina de empresa), **desde una carpeta con permiso de escritura** (Downloads, NO `System32`):
   ```powershell
   cd $env:USERPROFILE\Downloads
   irm https://raw.githubusercontent.com/LuDattilo/revit-mcp-server/main/scripts/install.ps1 -OutFile install.ps1
   notepad install.ps1
   powershell -ExecutionPolicy Bypass -File .\install.ps1
   ```
   En el wizard: `1` para instalar Node.js LTS. El instalador detecta las versiones de Revit, descarga el release y configura Claude Desktop.
3. **Encender el puente en Revit**: abre Revit **con un modelo abierto** → pestaña **Add-Ins** → panel **Revit MCP Plugin** → **Revit MCP Switch**. Esto abre el diálogo **`mcp-servers-for-revit · revitMCP`** → pulsa **Open Server** (NO "Cerrar") para arrancar el server en `localhost:8080`. Ver gotcha #6.
4. **Reiniciar Claude Desktop DE VERDAD** (ver gotcha #4) y verificar en **Settings → Developer** que aparece `revit-mcp`.

### Instalación asistida con Claude Code (cualquier ruta)

Si la Windows tiene **Claude Code**, la parte automatizable (descargar/clonar, editar `claude_desktop_config.json`) se le puede delegar pegando un prompt tipo: *"Instala el MCP server de Revit desde <repo>. Haz el clone/descarga y edita mi claude_desktop_config.json. Dime qué me queda por hacer a mano dentro de Revit y NO intentes automatizar la UI de Revit ni el reinicio de Claude Desktop."* Los pasos de UI (Switch/Open Server en Ruta A; activar Routes en Ruta B; reinicio real de Claude Desktop) siempre son manuales.

## Ruta B — pyRevit Routes + MCP server Python

Fuente: guía "Revit x Claude: MCP Connection" (@arch_ai_lab) + README del repo [`mcp-servers-for-revit/mcp-server-for-revit-python`](https://github.com/mcp-servers-for-revit/mcp-server-for-revit-python) (activo, verificado 2026-07-27). Detalle paso a paso en el anexo "Ruta B" de [RUNBOOK.md](./RUNBOOK.md).

Cadena: `Claude Desktop → main.py (MCP, FastMCP/uv) → pyRevit Routes (localhost:48884) → Revit API`. Claude manda **IronPython** que pyRevit ejecuta dentro de la sesión viva de Revit.

1. **pyRevit 6.4.0+** instalado → pyRevit tab → Settings → **Routes → activar Routes Server** (REST en puerto `48884`; sin esto Claude no llega a Revit).
2. **Extensión**: pyRevit tab → Extensions → "MCP Server for Revit Python Extension" → Install (queda en `%APPDATA%\pyRevit\Extensions`). Manual: `git clone` del repo, renombrar la carpeta para que termine en `.extension`, agregarla en Settings → Custom Extensions, recargar pyRevit.
3. **Health-check** (con Revit abierto): `http://localhost:48884/revit_mcp/status/` debe devolver `{"status": "active", "health": "healthy", ...}`. Este endpoint es el diagnóstico #1 de la ruta B.
4. **uv** instalado, y en `claude_desktop_config.json`:
   ```json
   { "mcpServers": { "Revit Connector": { "command": "uv", "args": ["run", "--with", "mcp[cli]", "mcp", "run", "/ruta/absoluta/a/main.py"] } } }
   ```
   (`main.py` está en la raíz de la extensión clonada; forward slashes o backslashes escapados.)
5. Reiniciar Claude Desktop **de verdad** (mismo gotcha #4 de la ruta A).

**Versiones (ruta B)**: verificado en Revit 2025; **2025 y 2026 son los targets seguros**. **Revit 2027 necesita pyRevit 6.4.0+** (.NET 10) y su soporte aún es inmaduro — en algunos builds pyRevit carga pero el motor IronPython nunca arranca (y este puente corre sobre ese motor). Antes de comprometerse con 2027: abrir Revit y confirmar que el endpoint de status devuelve `healthy`. Routes **no tiene autenticación** — es solo-localhost, no exponer el puerto.

## GOTCHAS (esto es lo valioso — todos vistos hoy)

1. **`irm -OutFile` falla con "Access is denied" en `System32`.** PowerShell suele abrir en `C:\WINDOWS\System32`, donde el usuario no puede escribir. → `cd $env:USERPROFILE\Downloads` primero.

2. **DLLs bloqueados si Revit estaba abierto durante la instalación.** El add-in no carga, o solo aparece el botón *Switch* sin el *Panel*. → Cierra Revit por completo y desbloquea:
   ```powershell
   Get-ChildItem "$env:APPDATA\Autodesk\Revit\Addins\2023\revit_mcp_plugin" -Recurse | Unblock-File
   ```
   Reabre Revit y, en el aviso *"Security - Unsigned Add-In"*, elige **Always Load**.

3. **El botón "Revit MCP Switch" se ve gris.** Casi siempre es porque **no hay un modelo abierto** — Revit desactiva casi toda la cinta en la pantalla de inicio. → Abre/crea cualquier proyecto y el botón se activa. (Si sigue gris *con* modelo abierto → DLLs no cargados, ver gotcha #2.)

4. **Claude Desktop no muestra el MCP tras "reiniciar".** Es EL problema final más común: la **X solo lo manda a la bandeja**, el proceso sigue vivo y no relee la config. → Mátalo de verdad y reábrelo desde el menú Inicio:
   ```powershell
   Get-Process Claude | Stop-Process -Force
   ```
   Luego **Settings → Developer** debe listar `revit-mcp`. Si Developer está vacío y solo muestra *Edit Config*, es esto.

5. **Rutas largas se parten al pegar en el terminal remoto** → error `Illegal characters in path` (la ruta se corta en dos líneas con `>>` e inserta un carácter ilegal). Los `False` de `Test-Path` así son **falsos negativos**, no significan que falte el archivo. → Usa rutas cortas con `$env:APPDATA` o variables:
   ```powershell
   $p = "$env:APPDATA\Autodesk\Revit\Addins\2023\revit_mcp_plugin"
   $node = "$p\Commands\RevitMCPCommandSet\server\runtime\node.exe"
   $idx  = "$p\Commands\RevitMCPCommandSet\server\build\index.js"
   ```

6. **El "Revit MCP Switch" NO "se pone verde" solo: abre un diálogo y hay que pulsar "Open Server".** (Plugin v2.2.1, visto 2026-06-26.) Pulsar *Revit MCP Switch* abre el modal **`mcp-servers-for-revit · revitMCP`** con un botón **Open Server** (y "Cerrar"). Hay que pulsar **Open Server** para levantar el server en `localhost:8080`; para apagarlo, el botón pasa a **Close Server**. ⚠️ Si solo cierras el modal con *Cerrar*, **el puente no arranca** y Claude no recibe datos del modelo aunque Settings → Developer muestre `revit-mcp` como `running` (ese `running` solo confirma que Claude levantó el Node, no que el add-in esté escuchando).

7. **Con varias versiones de Revit instaladas, el instalador las configura todas pero Claude apunta a UNA.** (Visto 2026-06-26: detectó e instaló en **2023, 2024 y 2026** — "3 version(s) installed".) El add-in queda en las tres carpetas, pero `claude_desktop_config.json` apunta al `node.exe`/`index.js` de **una sola** versión. **No importa cuál** ni que coincida con la que abras: el server se conecta por `localhost:8080` a *cualquier* Revit con el Switch encendido. → Para diagnosticar, no asumas el año: mira la ruta **real** en Settings → Developer y úsala en los comandos de abajo.

## Diagnóstico (en orden)

1. **¿Existen los archivos del server?** (sin pegar rutas largas)
   ```powershell
   Test-Path "$env:APPDATA\Autodesk\Revit\Addins\2023\revit_mcp_plugin"
   Get-ChildItem "$env:APPDATA\Autodesk\Revit\Addins\2023" -Recurse -Filter index.js | Select-Object FullName
   Get-ChildItem "$env:APPDATA\Autodesk\Revit\Addins\2023" -Recurse -Filter node.exe | Select-Object FullName
   ```
2. **¿La config tiene el server?** Claude Desktop → Settings → Developer → **Edit Config**. Debe contener un bloque `mcpServers.revit-mcp` con `command` = ese `node.exe` y `args[0]` = ese `build\index.js`. Las rutas de la config deben coincidir con las reales.
3. **Reinicio completo** (gotcha #4).
4. **Prueba el server a mano** (aísla si el problema es Claude o el server): con las variables `$node`/`$idx` de arriba, `& $node $idx`. Si **se queda esperando sin error** → server sano, culpa de Claude (Ctrl+C para salir). Si **escupe error rojo** → ahí está la causa.
5. **Logs de Claude**:
   ```powershell
   Get-ChildItem "$env:APPDATA\Claude\logs" | Sort-Object LastWriteTime -Descending | Select-Object -First 8 Name
   Get-Content "$env:APPDATA\Claude\logs\mcp.log" -Tail 40
   ```

## Verificación final

En Claude Desktop, con un **modelo de prueba** abierto en Revit y el Switch encendido:

> "¿Qué información general tiene este modelo de Revit?"
> "Lista los niveles y cuántas paredes hay en cada uno."

Si devuelve datos reales del modelo → conectado.

## Avisos de seguridad (entregar siempre al usuario)

- **Empezar con un modelo de prueba**, nunca un proyecto real al inicio.
- Quédate unos días en **consulta/QA (read-only)** antes de pedir crear/modificar: la IA escribe directo y **el undo no se agrupa**.
- El puente vive mientras el modelo esté abierto y el Switch encendido; cerrar el modelo lo corta.
- Para categorías usa `BuiltInCategory` (ej. `OST_Walls`) — los nombres de parámetros dependen del idioma de la UI de Revit.
- Puerto `localhost:8080` (ruta A) o `48884` (ruta B) debe estar libre.

## Gotchas al DIRIGIR Revit con Claude (cualquier ruta)

Vistos en builds reales (guía @arch_ai_lab). Pásalos como instrucciones al prompt cuando Claude vaya a crear geometría:

- **No llamar `time.sleep()` ni `RefreshActiveView()` dentro de un loop de transacciones** — cuelga o degrada la sesión.
- **Activar los family symbols en su propia transacción ANTES de colocar instancias** (`symbol.Activate()` separado del `Create.NewFamilyInstance`).
- **Un tool call fallido puede haber commiteado igual la transacción** — tras un error, verificar el estado real del modelo antes de reintentar, o se duplican elementos.

## Versiones de referencia (instalaciones que funcionaron)

- **2026-06-01** — máquina `lmarin`: Plugin `v2.2.1` (2026-04-09) · Node `v24.16.0` (LTS empaquetado) · Revit 2023/2024/2025 · Windows 11.
- **2026-06-26** — máquina `jsalvador` (RDP, "ordenador compartido"): Plugin `v2.2.1` · Node LTS empaquetado · **Revit 2023.1 / 2024 / 2026** detectados e instalados a la vez ("3 version(s) installed") · PowerShell 5.1, Windows build 26100. **Instalación limpia, sin gotchas de DLL** (Revit cerrado durante el install). Único punto de fricción: el diálogo **Open Server** (gotcha #6). Verificado end-to-end con el modelo de muestra `RST_basic_sample_project` (devolvió niveles y conteo de paredes en Claude Desktop).
