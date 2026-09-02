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

> Los números #11–#14 pertenecen a la **Ruta C** (más abajo). La numeración es global para que
> las referencias cruzadas de este documento no se rompan al añadir casos.

15. **El instalador de Node.js falla si el usuario no es administrador — y da igual.** (Visto 2026-09-01, máquina `ahim`.) El wizard ofrece instalar Node LTS (opción `1`) y el MSI muere con *"Node.js Setup Wizard was interrupted. Your system has not been modified"*, porque escribe en `Program Files`. Comprobación: `[bool](whoami /groups | Select-String "S-1-5-32-544")` → `False`. **El script continúa y la instalación funciona igual**: cada release trae su propio runtime en `...\server\runtime\node.exe` (aquí `v22.22.2`) y el config apunta a ése, no al Node del sistema — el instalador lo reporta como `[+] Bundled Node.js runtime`. Todo el plugin cae bajo `%APPDATA%\Roaming\Autodesk\Revit\Addins\`, que es perfil de usuario. → **La Ruta A no necesita permisos de IT.** El Node del sistema solo hace falta para la Ruta C, que usa `npx`.

16. **Otro add-in de Revit escuchando en un puerto vecino falsea el diagnóstico del 8080.** (Visto 2026-09-01, máquina `ahim`; costó tres rondas.) Antes de pulsar *Open Server*, el proceso Revit ya escuchaba en `127.0.0.1:55000` y `127.0.0.1:8088` — de otros add-ins de la misma cinta (Bluebeam, eTransmit, Cost-it, conversor a FormIt). Ver un puerto "casi correcto" hace concluir que el plugin arrancó en 8088 y manda a buscar un ajuste de puerto que no existe: el `index.js` **no contiene ningún literal de puerto** (una regex sobre el bundle devuelve vacío) y el plugin no trae archivo de settings con ese dato. → **Mide los puertos de Revit ANTES y DESPUÉS de pulsar Open Server**; el que aparece nuevo es el del MCP. Aquí el `8080` apareció como tercera fila al encenderlo:
    ```powershell
    $ids = (Get-Process Revit -EA SilentlyContinue).Id
    Get-NetTCPConnection -State Listen -EA SilentlyContinue |
      Where-Object { $ids -contains $_.OwningProcess } |
      Select-Object LocalAddress, LocalPort | Format-Table -AutoSize
    ```

17. **Leer `main.log` sin marca de tiempo hace diagnosticar el arranque equivocado.** (Visto 2026-09-01.) Las líneas `[localMcpBridge] no stdio servers connected` se acumulan de arranques anteriores; un `Select-String` sin filtrar devuelve la de hace horas y parece que el arranque actual falló — con el config correcto y el puerto escuchando. → Anota la hora justo después del `Stop-Process` y compárala con los timestamps del log. Además de `Connected to revit-mcp (N tools)`, la señal inequívoca de éxito es una **lista enorme de nombres `revit-mcp__*`** en el log (`revit-mcp__get_project_info`, `revit-mcp__tag_all_walls`, `revit-mcp__export_to_excel`…).

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

⚠️ **Que sea un proyecto `.rvt`, no una familia `.rfa`.** (Visto 2026-09-01.) Si Revit está en el
Editor de familias, no hay niveles ni paredes ni información de proyecto: las respuestas salen
vacías y parece un fallo del puente cuando el problema es el documento abierto. Los proyectos de
muestra están en `C:\ProgramData\Autodesk\RVT 20*\Samples\*.rvt`.

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

- **2026-09-01** — máquina `ahim` de Mallol (RDP con control total, asistido desde macOS): Plugin `v2.2.1` · Node **empaquetado** `v22.22.2` (el MSI del sistema falló, gotcha #15) · **Revit 2022 / 2023 / 2024 / 2025 instalados**, plugin en 2023/2024/2025 ("3 version(s) installed") · **Claude Desktop de Microsoft Store `1.15962.1.0`** · usuario **sin permisos de administrador** · PowerShell 5.1, Windows build 26100. Instalador corrido **sin `-RevitVersion`**: su `[ValidateSet('2023'..'2027')]` y `$REVIT_YEARS = 2023..2027` descartan Revit 2022 solos, así que no hay riesgo de meter el add-in en una versión no soportada. Los gotchas #8 y #9 **no aparecieron** por respetar el orden (0 procesos de Claude antes de instalar): el instalador resolvió la ruta MSIX y escribió `revit-mcp` a la primera. El tiempo se fue en los gotchas #16 y #17, ambos de diagnóstico, no de instalación. Verificado end-to-end en un chat normal, con el Switch encendido y `127.0.0.1:8080` en escucha por el proceso Revit.

- **2026-09-01 (tarde)** — máquina `CHIM`, **Ruta C completa y funcionando en Cowork**: túnel con nombre
  `revit-mcp-chim.mallolarquitectos.com` gestionado desde el panel de Cloudflare de Mallol, gateway
  propio en `127.0.0.1:8000` con token en la ruta, watchdog cada 2 min, usuario **sin admin**.
  Verificado end-to-end: `401` sin token desde fuera de la red (6 sondeos estables), `200` con token
  con datos reales del modelo, respuesta **SSE** con `event: message`, y Cowork respondiendo en el
  chat. Lo que costó la jornada: el gotcha #22 (SSE) al final, y antes el #24 (token transcrito mal
  desde una captura) que disparó el #23 (veredicto de auth grabado al crear el conector).

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

14. ~~**El conector de ORGANIZACIÓN fuerza "Inicio de sesión por navegador" y el toggle no se puede
    apagar.**~~ **CORREGIDO — verificado el 2026-09-01.** El diálogo de creación ya ofrece
    *Autenticación → **Ninguno*** también en conectores de organización, y con eso el conector
    funciona. Dos matices que sí siguen vigentes:
    - En **Team/Enterprise sólo un Owner o Primary Owner** puede añadir conectores personalizados
      (**Organization settings → Connectors → Add → Custom → Web**); los miembros no tienen esa
      opción, sólo *Customize → Connectors → Connect* sobre los ya publicados. El "créalo personal"
      del consejo antiguo **no aplica** a cuentas de organización.
    - Tras guardarlo, la pestaña *Configuración* puede seguir mostrando **"Inicio de sesión por
      navegador" encendido y bloqueado**. Es cosmético: si la pestaña *Detalles* dice
      *Autenticación: Ninguno*, el conector funciona. Verificado con Cowork respondiendo con datos
      del modelo.

### Las cuatro trampas del túnel con nombre (2026-09-01, máquina `CHIM`)

Ninguna estaba documentada; entre las cuatro se fue la tarde. **El código HTTP dice en qué tramo
está el fallo** — esta tabla es el diagnóstico más rápido que existe para la Ruta C:

| Código | Significa | Dónde está el fallo |
|---|---|---|
| `530` + `error code: 1033` | Hostname publicado, **ningún conector activo** | `cloudflared` no corre, murió, o su token es de otro túnel |
| `502` | Conector conectado, **origen inalcanzable** | del túnel al gateway: puerto, IP o gateway caído |
| `401` con `{"error":"unauthorized"}` | **Llegó al gateway** y aplicó auth | correcto; ya solo falta el token |
| `200` con datos del modelo | camino completo | verificado |

18. **`localhost` en el Public Hostname resuelve a `::1` y da 502 eterno.** El gateway escucha solo
    en `127.0.0.1` (a propósito, para no exponerse en la LAN). Con el servicio configurado como
    `http://localhost:8000`, Windows resuelve IPv6 primero y el log de `cloudflared` lo dice literal:
    `dial tcp [::1]:8000: connectex: ... denegó expresamente dicha conexión`. → En el panel, el
    Service debe ser **`http://127.0.0.1:8000`**, nunca `localhost`. Arreglo de un campo, se propaga
    en segundos sin reiniciar el conector. La alternativa —bindear el gateway a todas las
    interfaces— amplía la superficie expuesta y no hace falta.

19. **El token del túnel se pega con el comando entero delante.** El panel de Cloudflare ofrece
    *"cloudflared tunnel run --token eyJ…"* para copiar de un tirón, y acaba dentro del archivo:
    `longitud 215`, `empieza por: cloudflared`. Luego `tunnel run --token <ese contenido>` recibe un
    token inválido y nunca se registra → `530`. → Verificador: **el token debe empezar por `eyJ` y no
    contener espacios**. Vale la pena leerlo con `Read-Host -AsSecureString` (no se ve, no queda en
    el historial ni en capturas) y extraer con `if ($raw -match '--token\s+(\S+)') { $Matches[1] }`.

20. **El gateway lanzado con `Start-Process` desnudo muere sin dejar rastro.** Cayó tres veces en una
    tarde y cada caída se manifestó como un 502 indistinguible de un problema de red. → Lanzarlo
    **siempre** con `-RedirectStandardOutput` / `-RedirectStandardError` a archivos y
    `-WindowStyle Hidden`: así no depende de una ventana que se puede cerrar y la causa queda escrita.
    Señal de arranque sano en el log de stderr: `[gateway] initialize ok: {"name":"mcp-server-for-revit",…}`.

21. **Un `$` al principio de línea se pierde al pegar en la consola remota.** `$dst = "..."` llega como
    `dst = "..."` → *"El término 'dst' no se reconoce"* y, peor, la variable queda sin definir y el
    comando siguiente usa una URL sin token. Es primo del gotcha #5. → Empezar los bloques pegados con
    una línea de comentario (`# ---`), que absorbe el carácter perdido.

22. **Cowork pide `text/event-stream` y un gateway que responde JSON plano cuelga en `tools/call`.**
    Es el fallo final de la Ruta C, y engaña porque **`initialize` y `tools/list` sí funcionan** —el
    chat dice *"herramientas cargadas"*— y sólo mueren las llamadas a herramientas, con *timeout* en
    los tres intentos. El diagnóstico apunta a Revit (diálogo modal, documento ocupado) cuando Revit
    está perfecto: el mismo `tools/call` por `curl` devuelve datos en 0,67 s. → El gateway debe
    responder **SSE cuando el `Accept` lo pida**, con el JSON-RPC dentro de un único evento:
    ```js
    const sse = /text\/event-stream/i.test(req.headers['accept'] || '');
    res.writeHead(200, sse
      ? { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', 'Connection': 'keep-alive' }
      : { 'Content-Type': 'application/json' });
    res.end(sse ? ('event: message\ndata: ' + JSON.stringify(out) + '\n\n') : JSON.stringify(out));
    ```
    Ya viene en [assets/gateway.js](./assets/gateway.js). Verificador antes de tocar Cowork:
    `curl -H "Accept: text/event-stream"` debe devolver `event: message` + `data: {...}`.

23. **El conector graba el veredicto de autenticación en el momento de crearlo.** Si al añadirlo el
    servidor está caído (`530`) o devuelve `401` —por ejemplo porque el token de la URL está mal—,
    queda marcado *"Siempre requerido — Detectado"* y el interruptor de inicio de sesión **no se
    deja apagar**. Editarlo no lo arregla. → **Levanta el servidor y comprueba que responde `200`
    ANTES de crear el conector**; si ya quedó mal, **bórralo y créalo de nuevo** (fila del conector
    → *Quitar*, o el menú de tres puntos).

24. **Nunca transcribir un token desde una captura de pantalla.** Pasó el 2026-09-01: se leyó
    `wCwnls…` donde decía `cWcnls…` —dos letras invertidas en 43 caracteres— y el conector quedó
    apuntando a una URL que devolvía `401`, lo que disparó el gotcha #23 y costó varias rondas de
    diagnóstico equivocado. → La URL se copia **del archivo**, nunca de una imagen o del chat:
    `Set-Clipboard -Value (Get-Content "$dst\url-conector.txt" -Raw).Trim()`. Para confirmar que se
    pegó bien, comparar sólo los **últimos 4-6 caracteres**, que no revelan el secreto.

25. **Sin admin, la persistencia va con `schtasks`, no con `Register-ScheduledTask`.** El cmdlet
    falla con `-RepetitionDuration ([TimeSpan]::MaxValue)`: *"El archivo XML de tarea contiene un
    valor con formato incorrecto o que está fuera de intervalo"*. → Usar la herramienta clásica, que
    no necesita privilegios para tareas del propio usuario:
    ```powershell
    schtasks /Create /TN "revit-bridge-watchdog" /TR "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"%USERPROFILE%\revit-gateway\watchdog.ps1\"" /SC MINUTE /MO 2 /F
    ```

26. **El gateway y el túnel se mueren solos: hace falta un vigilante, no reinicios manuales.** En una
    tarde cayeron cuatro veces, y cada caída se manifestó como un error distinto (`530` si murió el
    túnel, `502` si murió el gateway), lo que hace perseguir causas inexistentes. → Instalar
    [assets/watchdog.ps1](./assets/watchdog.ps1) con la tarea del punto #25: comprueba cada 2 minutos
    y relanza lo que falte, dejando traza en `watchdog.log`. Es lo que convierte el montaje en algo
    utilizable a diario.

**Rotar el token si aparece en una captura.** Pasó el 2026-09-01: el token del túnel quedó legible en
pantalla al guardarlo. Contiene accountTag, tunnelID y secreto: con él se levanta un conector que
suplanta ese hostname desde otra máquina. Rotación: Zero Trust → el túnel → **Refresh token**;
el anterior queda inservible al instante.

### Comandos (en la Windows con Revit)

```powershell
# Node del sistema — el empaquetado del plugin NO trae npx (winget requiere admin)
winget install OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements

# cloudflared: portable, funciona SIN admin
$dir = "$env:USERPROFILE\tools"; New-Item -ItemType Directory -Force -Path $dir | Out-Null
irm https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe -OutFile "$dir\cloudflared.exe"

# quick tunnel (URL desechable, muere al reiniciar)
& "$dir\cloudflared.exe" tunnel --url http://localhost:8000
# túnel con nombre gestionado desde el panel: solo hace falta el token, sin `tunnel login`
& "$dir\cloudflared.exe" tunnel run --token <TOKEN>
```

**Túnel con nombre en la infraestructura del cliente (camino recomendado).** Evita el `tunnel login`
interactivo y deja la propiedad donde debe estar: quien administre Cloudflare crea el túnel en
Zero Trust → Networks → Tunnels, publica el *Public Hostname* apuntando a **`HTTP://localhost:8000`**
—al gateway, nunca al 8080 del add-in, que no tiene autenticación— y entrega **solo el token**.
Requisito: la zona del cliente ya delegada a Cloudflare (`dig +short NS <dominio>` debe devolver
`*.ns.cloudflare.com`).

El gateway ya no se improvisa: está versionado en **[assets/gateway.js](./assets/gateway.js)**
(SHA-256 `786dfd66…efce27b6`). Node puro, sin dependencias, y **lee el `command`/`args` del
`claude_desktop_config.json`** —incluida la ruta MSIX— así que no hay rutas que codificar a mano.
Variables: `MCP_TOKEN` (obligatoria), `PORT` (8000), `MCP_COMMAND`/`MCP_ARGS` para forzar el server.

**Cómo llevarlo a la Windows sin red compartida** (2026-09-01): pegar 200 líneas de JS por RDP se
corrompe. En su lugar, `base64` del archivo troceado a **2800 caracteres por línea** —por debajo del
límite de entrada de la consola—, concatenar las partes, `[IO.File]::WriteAllBytes` y **verificar con
`Get-FileHash -Algorithm SHA256` contra el hash de origen**. Si el hash no coincide, un trozo se pegó
mal: repetirlo, nunca seguir adelante.

**Sin admin** (caso `CHIM`): `cloudflared` no se instala con winget sino como binario portable
(`irm https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe`)
y la persistencia va por acceso directo en `[Environment]::GetFolderPath('Startup')`, no por servicio
de Windows.

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

### ~~Limitación pendiente~~ → RESUELTA con túnel con nombre (2026-09-01)

`trycloudflare` es un **quick tunnel**: la URL muere al cerrar cloudflared o reiniciar el equipo.
Fue exactamente lo que mató el conector de agosto — semanas apuntando a un hostname que ya no
resolvía. **La solución es un túnel con nombre en la infraestructura del cliente**, y el camino
más limpio es el **gestionado desde el panel**: quien administre Cloudflare crea el túnel en
Zero Trust, publica el hostname y entrega **sólo el token**; en la máquina basta
`cloudflared tunnel run --token <TOKEN>`, sin `tunnel login` interactivo y sin admin.

Requisito: la zona del cliente delegada a Cloudflare. Compruébalo antes de prometer nada:
`dig +short NS <dominio>` debe devolver `*.ns.cloudflare.com`.

---

## Desplegar en más equipos

Todo lo aprendido está empaquetado en **[assets/deploy-revit-bridge.ps1](./assets/deploy-revit-bridge.ps1)**,
que en un equipo nuevo hace en un paso: comprobar requisitos, instalar `gateway.js` y `watchdog.ps1`,
generar el token, descargar `cloudflared` portable, pedir el token del túnel con entrada oculta,
registrar la tarea del watchdog, arrancar todo y **verificar los cinco códigos** (401/200 local,
401/200 público y SSE). No imprime la URL: la deja en archivo y portapapeles.

```powershell
.\deploy-revit-bridge.ps1 -PublicHostname revit-mcp-pc07.mallolarquitectos.com
```

### Lo que hay que decidir antes de escalar

- **Un hostname y un token por equipo.** El conector apunta a UNA máquina: N equipos son N túneles,
  N tokens y N conectores. Nómbralos por equipo (`revit-mcp-<pc>`) o nadie sabrá a cuál pregunta.
- **¿Estación central o puesto por arquitecto?** Un solo equipo compartido es más barato de operar
  (un túnel, un modelo abierto) pero todos ven y modifican el mismo documento. Un puesto por
  arquitecto multiplica el montaje y el mantenimiento.
- **El eslabón manual no desaparece.** Alguien tiene que abrir Revit con el modelo y pulsar
  *Open Server* en cada sesión. Si el equipo se reinicia de noche, el puente queda muerto aunque el
  túnel reviva: el watchdog cuida gateway y túnel, **no** el add-in.
- **Sólo un Owner puede publicar el conector** en Team/Enterprise (gotcha #14). Consigue esa
  disponibilidad antes de empezar, o el trabajo queda hecho y sin poder estrenarse.
- **Si lo que hace falta es sólo consultar datos** (métricas, cantidades, QA), evalúa antes ir por
  **APS/ACC** contra el modelo publicado: no necesita PC encendido, ni túnel, ni botón que pulsar, y
  da permisos por usuario en vez de un token compartido. El add-in gana cuando hay que **modificar
  el modelo abierto** en vivo. Ver el skill `desarrollo-apps-autodesk`.

### Orden de despliegue por equipo (~40 min)

1. **Ruta A** con `install.ps1` — sin admin, plugin en todas las versiones soportadas (~20 min).
2. Revit abierto, un `.rvt` de prueba, **Open Server** pulsado; comprobar `8080` en escucha.
3. Pedir a quien administre Cloudflare el túnel y el hostname, con Service **`http://127.0.0.1:8000`**.
4. `deploy-revit-bridge.ps1 -PublicHostname <host>` (~10 min, incluye su propia verificación).
5. Un Owner publica el conector: **Organization settings → Connectors → Add → Custom → Web**,
   autenticación **Ninguno**.
6. Probar en Cowork: *"¿qué archivo de Revit está abierto?"*.

### Coste real

- Ruta A sola: **20-30 min** con este runbook.
- Ruta C la primera vez: **~3 h en agosto** (gotchas #8-#14) y **otra jornada el 2026-09-01**
  (gotchas #15-#26, sobre todo el SSE del #22, que se disfraza de "Revit no responde").
- Ruta C con el instalador y estos gotchas: **menos de una hora**, y la mayor parte es esperar a IT.
