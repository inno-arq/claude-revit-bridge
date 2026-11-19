# Revit Bridge

<img alt="Versión" src="https://img.shields.io/badge/plugin-2.0.0-informational">
<img alt="Visibilidad" src="https://img.shields.io/badge/repo-uso%20interno%20Mallol-lightgrey">
<img alt="Revit" src="https://img.shields.io/badge/Revit-2023--2027-0696D7?logo=autodesk&logoColor=white">
<img alt="Node.js" src="https://img.shields.io/badge/Node.js-22-339933?logo=nodedotjs&logoColor=white">
<img alt="Cloud Run" src="https://img.shields.io/badge/Google%20Cloud%20Run-4285F4?logo=googlecloud&logoColor=white">
<img alt="Licencia" src="https://img.shields.io/badge/licencia-MIT-blue">

Connect Claude to Autodesk Revit. Query your models, analyze elements, check quality, and make modifications - all through natural conversation.

## Quick Start

### 1. Install on your Windows PC with Revit

Open PowerShell and run:

```powershell
irm https://raw.githubusercontent.com/inno-arq/claude-revit-bridge/main/installer/setup-revit-bridge.ps1 | iex
```

The installer will:
- Install the Revit MCP plugin
- Set up the connection tunnel
- Register your device
- Display your **Device ID** and **API Key**

### 2. Activate in Revit

1. Open Revit with a project file (.rvt)
2. Go to **Add-Ins** tab
3. Click **Revit MCP Switch**
4. **Close** the "Open Server" dialog (important!)

### 3. Connect in Claude

In Claude, ask: *"Connect to my Revit"*

Provide your Device ID and API Key when prompted.

## What You Can Do

### Query Your Model
- "How many walls are in this model?"
- "List all rooms with their areas"
- "Show me the levels and their elevations"
- "What doors are on Level 2?"

### Analyze Quality
- "Run a model health check"
- "Are there any unplaced rooms?"
- "Find duplicate door marks"
- "Check for model warnings"

### Export Data
- "Export a schedule of all windows"
- "List all structural columns with sizes"
- "Create a room data report"

### Modify (with caution)
- "Place a door in wall 12345"
- "Change the mark of room 101 to 'Office A'"
- "Tag all walls on Level 1"

## Supported Versions

- Revit 2023
- Revit 2024
- Revit 2025
- Revit 2026
- Revit 2027

## Architecture

```
Claude (Cowork/Desktop)
    │
    │ HTTPS
    ▼
Revit Hub (https://revit-hub-476812260498.us-central1.run.app)
    │
    │ Cloudflare Tunnel
    ▼
Your Windows PC
    │
    ├── Gateway (Node.js)
    │       │
    │       │ stdio
    │       ▼
    ├── revit-mcp-server
    │       │
    │       │ localhost:8080
    │       ▼
    └── Revit Plugin (C#)
            │
            ▼
        Revit API
```

## Troubleshooting

### Connection Issues

**"Device not found"**
- Your PC may have restarted. Run the watchdog:
  ```powershell
  & "$env:USERPROFILE\revit-bridge\watchdog.ps1"
  ```

**"Device unreachable" (502)**
- Is Revit open with a model?
- Did you click the MCP Switch?
- Is cloudflared running? Check: `Get-Process cloudflared`

**Timeouts**
- The "Open Server" dialog must be CLOSED, not just open
- Check for other modal dialogs in Revit

### Reinstalling

To completely reinstall:
```powershell
Remove-Item -Recurse -Force "$env:USERPROFILE\revit-bridge"
# Then run the installer again
```

## For IT Administrators

### Named Tunnels

For persistent, branded URLs, use Cloudflare named tunnels:

1. Create a tunnel in Cloudflare Zero Trust
2. Configure the Public Hostname to point to `http://127.0.0.1:8000`
3. Run the installer with the tunnel token:
   ```powershell
   .\setup-revit-bridge.ps1 -TunnelToken "eyJ..."
   ```

### Self-Hosted Hub

To run your own Revit Hub instead of using Mallol's:

```bash
cd hub
docker build -t revit-hub .
docker run -p 8080:8080 -e HUB_SECRET=your-admin-secret revit-hub
```

Then point installers to your hub:
```powershell
.\setup-revit-bridge.ps1 -HubUrl "https://your-hub.example.com"
```

## Security

- All traffic is encrypted (HTTPS/TLS)
- Each device has a unique API key
- The gateway only listens on localhost
- Cloudflare Tunnel means no open firewall ports
- No Revit files are uploaded - only API commands

## Credits

- Plugin: [LuDattilo/revit-mcp-server](https://github.com/LuDattilo/revit-mcp-server)
- Tunnel: [Cloudflare](https://www.cloudflare.com/products/tunnel/)
- Developed by [Mallol Arquitectos](https://mallol.com)

## License

MIT

## Estructura del repositorio

```
.claude-plugin/  manifiesto del plugin y del marketplace
skills/          skills de Claude: connect-claude-revit, revit-connect, revit-diagnose, revit-install, revit-modify, revit-query
installer/       instalador para Windows (PowerShell, .bat y Inno Setup)
hub/             Revit Hub: registro y enrutador de dispositivos (Node.js, Cloud Run)
docs/            página de documentación
```

## Stack

Node.js 22 (hub y gateway) · PowerShell (instalador) · plugin C# de Revit de terceros · Cloudflare Tunnel · Google Cloud Run + Cloud Build (hub).

## Configuración

Variables de entorno del hub: `HUB_SECRET` y `PORT`. El gateway lee `PORT`, `MCP_COMMAND`, `MCP_ARGS`, `MCP_TOKEN` y `RPC_TIMEOUT_MS`. Solo nombres; los valores no van en el repo.

## Documentación

Procedimiento detallado e imprimible para IT: [`skills/connect-claude-revit/RUNBOOK.md`](skills/connect-claude-revit/RUNBOOK.md).

## Propietario

Oficina de Innovación de Mallol.
