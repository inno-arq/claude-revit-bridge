# Guía: Conectar Claude a Revit (MCP)

> Runbook paso a paso para instalar el puente **Claude Desktop ↔ Autodesk Revit** en una máquina Windows.
> Probado el 2026-06-01 (máquina `lmarin`) y 2026-06-26 (máquina `jsalvador`, por RDP) en Mallol. Tiempo estimado: 15–25 min.
> Plugin usado: [`LuDattilo/revit-mcp-server`](https://github.com/LuDattilo/revit-mcp-server) (add-in C# + instalador de un clic).

---

## 0. Antes de empezar — entiende el cableado

Revit **solo corre en Windows** y su API solo funciona *dentro* de Revit. Por eso todo se instala **en la máquina Windows que tiene Revit**:

```
Claude Desktop  →  MCP server (Node)  →  add-in C# en Revit  →  Revit API
        (todo esto vive en la misma máquina Windows)
```

La instalación la hace el área de **IT** directamente sobre el **equipo Windows del usuario**, o **en remoto por RDP desde otra Windows**. Todos los comandos de abajo se ejecutan en el **PowerShell de esa máquina Windows**.

### Requisitos previos
- [ ] **Revit** instalado (2023, 2024, 2025, 2026 o 2027).
- [ ] **Claude Desktop** instalado y con sesión iniciada.
- [ ] Conexión a internet en la Windows.
- [ ] Node.js **no** es necesario instalarlo antes: el propio instalador lo ofrece.

---

## 1. Instalar el plugin

Abre **Windows PowerShell** en la máquina con Revit.

> ⚠️ **No corras el comando desde `C:\WINDOWS\System32`** (PowerShell suele abrir ahí y no te deja escribir el archivo → error *"Access is denied"*). Muévete primero a tu carpeta de Descargas.

```powershell
cd $env:USERPROFILE\Downloads
irm https://raw.githubusercontent.com/LuDattilo/revit-mcp-server/main/scripts/install.ps1 -OutFile install.ps1
notepad install.ps1
```

Revisa el script en el Bloc de notas (que de verdad descargue el plugin de Revit y configure Claude). Cuando te parezca bien, ejecútalo:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Durante el wizard:
- En **Node.js** → escribe **`1`** (Install Node.js LTS now). Sigue el asistente de Node y vuelve a PowerShell.
- El instalador **detecta automáticamente** tus versiones de Revit, descarga el release ya compilado, verifica los archivos y **configura Claude Desktop** solo.

Al final debe decir `Installation complete!`.

> 💡 **Cierra Revit antes de este paso** si está abierto. Si lo dejaste abierto, el instalador avisa que los DLLs quedarán bloqueados — soluciónalo en el paso 2.

---

## 2. (Solo si Revit estaba abierto) Desbloquear los DLLs

Cierra Revit por completo y corre (ajusta `2023` a tu versión):

```powershell
Get-ChildItem "$env:APPDATA\Autodesk\Revit\Addins\2023\revit_mcp_plugin" -Recurse | Unblock-File
```

---

## 3. Encender el puente dentro de Revit

1. Abre **Revit** y **abre un modelo** (uno de prueba, o crea un proyecto nuevo en blanco).
   - Si aparece el aviso **"Security - Unsigned Add-In"**, elige **Always Load**.
2. Ve a la pestaña **Add-Ins** → aparece el panel **Revit MCP Plugin** (botones: *Revit MCP Switch*, *MCP Panel*, *Settings*).
3. Clic en **Revit MCP Switch** → se abre el diálogo **`mcp-servers-for-revit · revitMCP`** → pulsa **Open Server** (NO "Cerrar"). Eso arranca el server en `localhost:8080`; para apagarlo, el botón pasa a **Close Server**.

> ⚠️ **El Switch NO "se pone verde" solo** — abre ese diálogo. Si solo lo cierras con *Cerrar*, el puente **no arranca** (y Claude no recibirá datos aunque marque `revit-mcp` como `running`).
> ⚠️ **Si el botón Switch está gris:** es porque **no hay un modelo abierto**. Abre cualquier proyecto y se activa.
> **El puente solo vive con el modelo abierto y el server (Open Server) encendido.** Si cierras el modelo, se corta.

---

## 4. Conectar Claude Desktop

El instalador ya dejó la config lista, pero **hay que reiniciar Claude de verdad**.

> ⚠️ La **X NO cierra Claude** — lo manda a la bandeja y NO relee la config. Hay que matar el proceso.

```powershell
Get-Process Claude | Stop-Process -Force
```

Espera a que desaparezca la ventana y **abre Claude Desktop de nuevo desde el menú Inicio**.

Verifica: **Settings (⚙) → Developer** → debe aparecer **`revit-mcp`**.

---

## 5. Probar

En Claude Desktop, con un **modelo de prueba** abierto en Revit y el Switch encendido, escribe:

> *"¿Qué información general tiene este modelo de Revit?"*
> *"Lista los niveles y cuántas paredes hay en cada uno."*

Si responde con datos reales del modelo → **listo, está conectado.** 🎯

---

## Solución de problemas

| Síntoma | Causa | Solución |
|---|---|---|
| `irm ... : Access to the path '...install.ps1' is denied` | Estás en `System32`, sin permiso de escritura | `cd $env:USERPROFILE\Downloads` y repite |
| El botón **Revit MCP Switch** está gris | No hay un modelo abierto en Revit | Abre/crea un proyecto |
| Sigue gris **con** modelo abierto | DLLs bloqueados / add-in no cargó | Cierra Revit → `Unblock-File` (paso 2) → reabre y *Always Load* |
| En Revit solo sale *Switch*, no el *Panel* | Instalación incompleta / DLLs bloqueados | Igual que arriba |
| **Settings → Developer vacío**, solo *Edit Config* | Claude no se reinició de verdad | `Get-Process Claude \| Stop-Process -Force` → reabrir |
| `Test-Path` da `Illegal characters in path` y `False` | La ruta larga se partió al pegar en el terminal remoto | Usa rutas cortas con `$env:APPDATA` o variables (ver abajo). El `False` es falso, no significa que falte el archivo |
| Claude reinició pero no ve la tool | El server no arranca | Pruébalo a mano (ver "Diagnóstico avanzado") y revisa logs |
| Pulsé el Switch pero no pasa nada / no sé qué hacer | El Switch abre un diálogo, no "se pone verde" | En el modal `mcp-servers-for-revit · revitMCP` pulsa **Open Server** (no "Cerrar") |
| `revit-mcp` aparece `running` pero Claude no devuelve datos del modelo | No pulsaste **Open Server**, o el modelo está cerrado | Abre el modelo, pulsa **Open Server** en Revit; `running` solo dice que Claude levantó el Node, no que el add-in escuche |
| El server no levanta en `localhost:8080` | Puerto `8080` ocupado por otra app | Libera el puerto 8080 |

### Diagnóstico avanzado

**Confirmar que los archivos del server existen** (rutas cortas que no se parten):
```powershell
Test-Path "$env:APPDATA\Autodesk\Revit\Addins\2023\revit_mcp_plugin"
Get-ChildItem "$env:APPDATA\Autodesk\Revit\Addins\2023" -Recurse -Filter index.js | Select-Object FullName
Get-ChildItem "$env:APPDATA\Autodesk\Revit\Addins\2023" -Recurse -Filter node.exe | Select-Object FullName
```

**Levantar el server manualmente** (aísla si el problema es Claude o el server):
```powershell
$p = "$env:APPDATA\Autodesk\Revit\Addins\2023\revit_mcp_plugin"
$node = "$p\Commands\RevitMCPCommandSet\server\runtime\node.exe"
$idx  = "$p\Commands\RevitMCPCommandSet\server\build\index.js"
& $node $idx
```
- Se queda esperando sin error → server sano, el problema es Claude (sal con **Ctrl+C**).
- Error rojo y vuelve al prompt → ahí está la causa.

**Logs de Claude Desktop**:
```powershell
Get-ChildItem "$env:APPDATA\Claude\logs" | Sort-Object LastWriteTime -Descending | Select-Object -First 8 Name
Get-Content "$env:APPDATA\Claude\logs\mcp.log" -Tail 40
```

**Revisar la config** (Settings → Developer → *Edit Config*). Debe contener:
```json
{
  "mcpServers": {
    "revit-mcp": {
      "command": "C:\\Users\\<usuario>\\AppData\\Roaming\\Autodesk\\Revit\\Addins\\2023\\revit_mcp_plugin\\Commands\\RevitMCPCommandSet\\server\\runtime\\node.exe",
      "args": ["C:\\Users\\<usuario>\\AppData\\Roaming\\Autodesk\\Revit\\Addins\\2023\\revit_mcp_plugin\\Commands\\RevitMCPCommandSet\\server\\build\\index.js"]
    }
  }
}
```
> El MCP server es solo el puente: se conecta por `localhost:8080` a *cualquier* Revit con el Switch encendido. Las rutas pueden apuntar a la carpeta de otra versión de Revit (ej. 2025) y funcionar igual con Revit 2023.

---

## ⚠️ Buenas prácticas de uso

- **Empieza con un modelo de prueba**, nunca con un proyecto real.
- Usa **consulta/QA (read-only)** unos días antes de pedir crear o modificar elementos.
- La IA ejecuta operaciones **directo** y **no agrupa el undo** — deshacer cambios masivos es tedioso.
- Para categorías usa los `BuiltInCategory` (ej. `OST_Walls`); los nombres de parámetros dependen del idioma de la UI de Revit.

### Al pedir a Claude que CREE geometría (visto romperse en builds reales)

- **Nada de `time.sleep()` ni `RefreshActiveView()` dentro de loops de transacciones.**
- **Activar family symbols en su propia transacción** antes de colocar instancias.
- **Un tool call fallido puede haber commiteado la transacción igual** — verifica el estado del modelo antes de reintentar, o duplicas elementos.

---

## Anexo: Ruta B — pyRevit Routes + MCP server Python

Alternativa al plugin C# de LuDattilo. Úsala si el instalador de la ruta A falla, la oficina ya usa **pyRevit**, o necesitas sus tools exclusivas (`launch_revit`, `list_revit_installations`, `execute_revit_code` con IronPython directo).

```
Claude Desktop → main.py (MCP server, uv/FastMCP) → pyRevit Routes (localhost:48884) → Revit API
```

**Versiones**: 2025 y 2026 son los targets seguros (verificado en 2025). **Revit 2027 requiere pyRevit 6.4.0+** y aún es inmaduro: en algunos builds pyRevit carga pero el motor IronPython (del que depende este puente) nunca arranca. Antes de contar con 2027, confirma el health-check del paso B3.

### B1. Instalar pyRevit y activar Routes

1. Instala [pyRevit](https://github.com/pyrevitlabs/pyRevit) 6.4.0+ si no está.
2. En Revit: pestaña **pyRevit → Settings → Routes → activar "Routes Server"**. Levanta un REST local en el puerto `48884`. **Sin esto, Claude no tiene cómo llegar a Revit.**

### B2. Instalar la extensión MCP

**Fácil (desde pyRevit):** pestaña pyRevit → **Extensions** → "MCP Server for Revit Python Extension" → **Install extension** (default: `%APPDATA%\pyRevit\Extensions`) → habilitar y dejar recargar pyRevit (reinicia Revit si hace falta).

**Manual:**
```powershell
git clone https://github.com/mcp-servers-for-revit/mcp-server-for-revit-python
```
Renombra la carpeta para que termine en `.extension`, agrégala en pyRevit → Settings → **Custom Extensions**, y recarga pyRevit / reinicia Revit.

### B3. Health-check (el diagnóstico #1 de esta ruta)

Con Revit abierto, visita en un navegador de esa Windows:
```
http://localhost:48884/revit_mcp/status/
```
Debe devolver `{"status": "active", "health": "healthy", "revit_available": true, ...}`. Si no responde: Routes no está activado (B1) o la extensión no cargó (B2).

### B4. Instalar uv y configurar Claude Desktop

Instala [uv](https://docs.astral.sh/uv/getting-started/installation/) y agrega en `claude_desktop_config.json` (Settings → Developer → Edit Config):
```json
{
  "mcpServers": {
    "Revit Connector": {
      "command": "uv",
      "args": ["run", "--with", "mcp[cli]", "mcp", "run", "C:/ruta/absoluta/a/la/extension/main.py"]
    }
  }
}
```
`main.py` está en la raíz de la carpeta `.extension`. Usa forward slashes o backslashes escapados.

### B5. Reiniciar Claude Desktop y verificar

Mismo reinicio "de verdad" del paso 4 de la ruta A (`Get-Process Claude | Stop-Process -Force` → reabrir). Con un modelo abierto en Revit, pide a Claude el estado de Revit: debe devolver nombre del documento y health.

> ⚠️ pyRevit Routes está **en draft y sin autenticación** — es solo `localhost`; no expongas el puerto 48884 fuera de la máquina.

### Atajo: delegar B2 + B4 a Claude Code

Si la máquina tiene Claude Code, pégale un prompt que le pida: clonar el repo en `%APPDATA%\pyRevit\Extensions` renombrando a `.extension`, instalar uv si falta, y editar `claude_desktop_config.json` con el bloque de B4 — y que te diga qué queda manual (Routes en B1, reinicio en B5). No intentará (ni debe) automatizar la UI de Revit.

---

*Referencias: [revit-mcp-server (LuDattilo)](https://github.com/LuDattilo/revit-mcp-server) · [mcp-server-for-revit-python](https://github.com/mcp-servers-for-revit/mcp-server-for-revit-python) · [revit-mcp (proyecto base)](https://github.com/revit-mcp/revit-mcp) · [Use MCP In Revit — Autodesk AEC](https://forums.autodesk.com/t5/community-blog-aec-english/use-mcp-in-revit/ba-p/13678311) · Guía "Revit x Claude: MCP Connection" (@arch_ai_lab, Notion)*
