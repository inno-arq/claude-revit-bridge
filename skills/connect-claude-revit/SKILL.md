---
name: connect-claude-revit
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

0. **Cierra Revit Y Claude Desktop antes de empezar** (`Get-Process Revit,Claude | Stop-Process -Force`, verificando que el conteo baja a 0). Revit abierto bloquea DLLs (gotcha #2); Claude Desktop abierto **borra el bloque `revit-mcp` del config** (gotcha #9). Los dos fallos se ven "instalados correctamente" y aparecen después.
1. **Prerrequisitos**: Revit instalado; Claude Desktop instalado **y abierto al menos una vez con sesión iniciada** (si nunca se abrió, su carpeta de config no existe y el instalador reporta "Claude Desktop not found" — ver gotcha #8). Node.js lo ofrece el propio instalador (elige `1`).
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

8. **Claude Desktop instalado desde Microsoft Store: el config NO está en `%APPDATA%\Claude`.** (Visto 2026-08-31, máquina `CHIM`.) La variante MSIX virtualiza el sistema de archivos: la app cree que escribe en `%APPDATA%\Claude` (los logs lo dicen así) pero Windows lo redirige. `Test-Path "$env:APPDATA\Claude"` devuelve **False** aunque Claude esté corriendo, y el instalador reporta *"Claude Desktop not found — skipping automatic configuration"*. La ruta real:
   ```powershell
   $pkg = (Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter "Claude_*" | Select-Object -First 1).FullName
   $cfg = "$pkg\LocalCache\Roaming\Claude\claude_desktop_config.json"
   ```
   El instalador **sí** conoce esa ruta (`Get-ClaudeDesktopDir` la busca), pero solo la encuentra si la carpeta ya existe — o sea, si Claude Desktop **se ha abierto al menos una vez**. Para distinguir "no instalado" de "instalado y nunca abierto": `Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter "Claude_*"` y `Get-Process Claude | Select Id, Path` (la variante Store corre desde `C:\Program Files\WindowsApps\Claude_*`).

9. **Claude Desktop reescribe `claude_desktop_config.json` y BORRA el bloque `revit-mcp`.** (Visto 2026-08-31.) Es el fallo más traicionero de todos porque el archivo se verifica correcto y minutos después está vacío sin que nadie lo toque. La app vuelca su config en memoria al arrancar y al cerrarse — en `main.log` se ve como una ráfaga de `Config file written` con timestamps consecutivos. Si el instalador escribe mientras Claude corre, **gana la última escritura de la app** y el bloque desaparece. Síntoma: Settings → Desarrollador muestra "No se han agregado servidores" y **ningún log menciona `revit`** (un JSON ilegible dejaría error de parseo; aquí no hay error porque no hay nada que leer). → El orden importa: **matar Claude y verificar 0 procesos ANTES de escribir el config.**
   ```powershell
   "antes: "  + (Get-Process Claude -EA SilentlyContinue | Measure-Object).Count
   Get-Process Claude -EA SilentlyContinue | Stop-Process -Force
   Start-Sleep -Seconds 6
   "después: " + (Get-Process Claude -EA SilentlyContinue | Measure-Object).Count   # DEBE ser 0
   # y recién entonces reejecutar el instalador o escribir el bloque a mano
   ```
   Comprobación clave: con Claude muerto, mirar si `mcpServers.'revit-mcp'` sigue en el archivo. Si está vacío, la app lo pisó.

10. **Los MCP locales NO existen en Cowork ni en chats de la nube — solo en un chat local.** (Visto 2026-08-31; el fallo final que costó más tiempo.) Con todo correctamente instalado y `revit-mcp` conectado (138 tools en el log, puerto 8080 escuchando por Revit), Claude responde *"No encuentro un servidor MCP llamado revit-mcp conectado en esta sesión"* y lista solo conectores web (Drive, Gmail, Box…), añadiendo *"no hay ninguna computadora enlazada a esta sesión en la nube"*. Un server MCP por stdio vive dentro del proceso de Claude Desktop; una sesión en la nube no puede alcanzarlo. → Señales de que estás en el chat equivocado: panel **Progreso / Salidas / Contexto** a la derecha, selector de modo (*Manual*) y de modelo en el compositor. **Abre un chat normal** y las `revit-mcp__*` aparecen. La instalación no tiene nada de malo.

    **No hay forma de habilitarlo en Cowork** (verificado en docs de Anthropic, 2026-08-31): los MCP locales —tanto los de `claude_desktop_config.json` como las extensiones de escritorio— solo están disponibles en **Desktop y Claude Code**; solo los **conectores remotos** (MCP por URL pública) llegan a todas las superficies. Ver [When to use desktop and web connectors](https://support.claude.com/en/articles/11725091-when-to-use-desktop-and-web-connectors). El `[warn] Extension revit-mcp not found in installed extensions` del log es justamente ese chequeo. Si alguien pide Revit en Cowork, las salidas son: (a) envolverlo en un MCP remoto con URL pública y auth propia —proyecto en sí, porque el add-in escucha en localhost **sin autenticación** y habría que exponer un puesto de trabajo—, o (b) usar **Claude Code** en esa misma Windows, que sí lee MCP locales.

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

- **2026-08-31** — máquina `CHIM` (asistencia remota desde macOS, no RDP): Plugin `v2.2.1` · Node `v24.20.0` LTS · **Revit 2023** · **Claude Desktop de Microsoft Store `1.15962.1.0`** · PowerShell 5.1, Windows build 26100. Instalador anclado con `-RevitVersion 2023`. La instalación en sí fue trivial; **las 3 horas se fueron en los gotchas #8, #9 y #10**, todos nuevos y todos ajenos al plugin: config en ruta virtualizada MSIX, la app pisando el bloque `revit-mcp`, y el chat de Cowork que no ve MCP locales. Verificado end-to-end: `Connected to revit-mcp (138 tools)` en `main.log` + `127.0.0.1:8080` con `OwningProcess` = proceso `Revit` + respuesta con datos del modelo en un chat normal.

### Verificadores rápidos (ejecutar en la Windows)

Los dos que más aíslan, porque no dependen uno del otro:

```powershell
# ¿Claude levantó el server? (mitad Claude -> node)
$pkg = (Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter "Claude_*" | Select-Object -First 1).FullName
Select-String -Path "$pkg\LocalCache\Roaming\Claude\logs\main.log" -Pattern 'revit','localMcpBridge' | Select-Object -Last 8 | ForEach-Object { $_.Line }
# esperado: "Connected to revit-mcp (N tools)"

# ¿Revit está escuchando? (mitad node -> add-in) -- independiente de Claude
Get-NetTCPConnection -LocalPort 8080 -State Listen -EA SilentlyContinue | Select-Object LocalAddress, LocalPort, OwningProcess
Get-Process -Id (Get-NetTCPConnection -LocalPort 8080 -State Listen -EA SilentlyContinue).OwningProcess | Select-Object Id, ProcessName
# esperado: 127.0.0.1:8080 con ProcessName = Revit
```

`no stdio servers connected` en el log **sin ninguna mención de `revit`** = la config no llegó (gotcha #8 o #9), no un fallo del server.

---

## Ruta C — Revit en Claude Cowork (conector MCP remoto)

**Logrado el 2026-08-31 en la máquina `CHIM` de Mallol.** Nada de esto está en la documentación
oficial ni en el repo del plugin; se descubrió depurando, y cada tropiezo costó una ronda.

Un MCP **local** (stdio) nunca llega a Cowork: las sesiones corren en la nube de Anthropic. Pero un
conector **personalizado por MCP remoto** sí — es la única vía, y funciona.

```
[Cowork / claude.ai / móvil]
        ↓ HTTPS pública (rangos de IP de Anthropic)
[Cloudflare Tunnel]  ← conexión SALIENTE, no hay que abrir puertos en el firewall
        ↓ :8000
[gateway propio en Node: valida token, stateless]
        ↓ stdio
[index.js del plugin]
        ↓ localhost:8080
[add-in C# dentro de Revit]  ← modelo abierto, Open Server pulsado
```

### Las cuatro trampas, en el orden en que aparecen

11. **`supergateway --stateful` rompe el conector.** Es tentador porque el modo por defecto
    (stateless) deja **un `node.exe` huérfano por cada petición HTTP**. Pero en stateful el servidor
    exige `Mcp-Session-Id` y el conector de Claude falla:
    ```
    tools/list SIN session id -> 400  {"code":-32000,"message":"No valid session ID provided"}
    tools/list CON session id -> 200
    ```
    → Solución real: **sustituir supergateway por un gateway propio** que abra el proceso stdio
    **una sola vez al arrancar** y sea stateless de verdad. Resuelve la fuga y la compatibilidad a la vez.

12. **`WWW-Authenticate: Bearer` en el 401 dispara el flujo OAuth y mata la conexión.** Si el gateway
    protege con token y devuelve esa cabecera, el conector obedece el protocolo MCP, busca
    `/.well-known/oauth-protected-resource`, recibe 404 y falla con:
    > *"No se pudo registrar con el servicio de inicio de sesión. …comparte esta referencia con el soporte: ofid_…"*

    → El 401 debe ir **pelado**, sin `WWW-Authenticate` ni ninguna otra pista de OAuth. Verificar con
    `curl -D - -o /dev/null -X POST <url>/mcp` que no aparece esa cabecera.

13. **Los nombres de encabezado personalizados requieren aprobación de Anthropic.** El formulario los
    acepta pero avisa: *"Los nombres de encabezado personalizados necesitan la aprobación de Anthropic…
    un nombre no aprobado muestra un error"*. `X-MCP-Token` **no** está aprobado, y `Authorization`
    no aparece en el desplegable (lo reserva el OAuth del propio conector).
    → **Poner el token en la RUTA**: `https://…/mcp/<token>`. El gateway valida el último segmento.
    Se pega solo la URL, sin encabezados. Trátala como contraseña: quien vea la URL entra.

14. **El conector de ORGANIZACIÓN fuerza "Inicio de sesión por navegador" y el toggle no se puede
    apagar.** Queda pidiendo login contra un servidor que no tiene login, y nunca aparece disponible
    para los miembros. → Para probar, **crear el conector personal** (Configuración personal →
    Conectores → Agregar), donde sí se puede elegir *Ninguno*. El de organización solo sirve cuando
    el servidor implemente OAuth de verdad.

### Comandos (en la Windows con Revit)

```powershell
# Node del sistema — el empaquetado del plugin NO trae npx
winget install OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements
# cerrar y reabrir PowerShell

# túnel de salida
winget install --id Cloudflare.cloudflared -e
cloudflared tunnel --url http://localhost:8000     # imprime la URL pública
```

Lo demás (gateway con token, stateless, sin `WWW-Authenticate`) es más rápido delegárselo a
**Claude Code en esa máquina** con un prompt que incluya el criterio de éxito. Así se hizo.

### Verificador — correr desde FUERA de la red, no desde la máquina

Es el único que vale: comprueba el camino real del cliente.

```bash
B=https://<sub>.trycloudflare.com ; T=<token>
H='Content-Type: application/json'; A='Accept: application/json, text/event-stream'
L='{"jsonrpc":"2.0","id":1,"method":"tools/list"}'

curl -s -o /dev/null -w "sin token: %{http_code}\n"  -X POST "$B/mcp"     -H "$H" -H "$A" -d "$L"  # 401
curl -s -o /dev/null -w "token malo: %{http_code}\n" -X POST "$B/mcp/xx"  -H "$H" -H "$A" -d "$L"  # 401
curl -s -o /dev/null -w "con token: %{http_code}\n"  -X POST "$B/mcp/$T"  -H "$H" -H "$A" -d "$L"  # 200
curl -s -D - -o /dev/null -X POST "$B/mcp" -H "$H" -d "$L" | grep -i www-authenticate               # NADA
curl -s -X POST "$B/mcp/$T" -H "$H" -H "$A" \
  -d '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"analyze_model_statistics","arguments":{}}}'
```

El último debe devolver el nombre real del proyecto. Si eso responde, Cowork responderá.

### Limitación pendiente

`trycloudflare` es un **quick tunnel**: la URL muere al cerrar cloudflared o reiniciar el equipo, y
la siguiente es distinta — hay que reeditar el conector. Para dejarlo estable hace falta un **túnel
con nombre** y dominio propio. El token sobrevive al reinicio; la URL no.

### Coste real

Instalar el plugin: 20 min. Llegar a Cowork: ~3 h, casi todas en los gotchas #8 a #14. Con este
runbook debería ser menos de una hora.
