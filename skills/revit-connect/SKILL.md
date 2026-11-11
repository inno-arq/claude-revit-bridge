---
name: revit-connect
description: Connect Claude to your Revit instance. Use when users say "connect to Revit", "setup Revit", "I want to use Revit with Claude", or ask how to link their Revit model.
tools: []
---

# Connect Claude to Revit

Guide users through connecting their Revit installation to Claude via Revit Bridge.

## Overview

Revit Bridge allows Claude to interact with Autodesk Revit running on Windows. The connection requires:
1. A Windows PC with Revit installed
2. The Revit Bridge installer (one-time setup)
3. Revit open with a model and the MCP switch activated

## Installation Steps

### For the user to run on their Windows PC:

**Option A: One-liner install (recommended)**
```powershell
irm https://raw.githubusercontent.com/inno-arq/claude-revit-bridge/main/installer/setup-revit-bridge.ps1 | iex
```

**Option B: Download and review first**
```powershell
cd $env:USERPROFILE\Downloads
irm https://raw.githubusercontent.com/inno-arq/claude-revit-bridge/main/installer/setup-revit-bridge.ps1 -OutFile setup.ps1
notepad setup.ps1
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

### After installation:

The installer will display:
- **Device ID**: A short identifier for this PC
- **API Key**: A secret key for authentication

The user needs to:
1. Open Revit with a project file (.rvt)
2. Go to **Add-Ins** tab → **Revit MCP Switch** → Click it
3. **Close** the "Open Server" dialog (don't leave it open!)
4. Come back to Claude and provide their Device ID and API Key

## Setting up the connection in Claude

Once the user has their credentials:

1. Ask them for their Device ID and API Key
2. Build the connector URL: `https://revit-hub-476812260498.us-central1.run.app/mcp/{deviceId}/{apiKey}`
3. Guide them to add the connector:
   - **In Cowork**: Settings → Connectors → Add → Custom MCP → paste URL → No authentication
   - **In Claude Desktop**: Add to `claude_desktop_config.json` under `mcpServers`
   
4. Once added, the `revit-hub` tools will appear and you can query their model

## Troubleshooting

### "Device not found"
- The Windows PC may have restarted. Ask user to run the watchdog: `powershell -File "$env:USERPROFILE\revit-bridge\watchdog.ps1"`

### "Device unreachable" (502)
- Check that Revit is open with a model
- Check that the MCP Switch was activated (and the dialog closed)
- Check that cloudflared is running: `Get-Process cloudflared`

### Timeout on tool calls
- The "Open Server" dialog may still be open in Revit - must be closed
- Check for other modal dialogs in Revit

## Supported Revit Versions

- Revit 2023
- Revit 2024
- Revit 2025
- Revit 2026
- Revit 2027

## What you can do once connected

With Revit connected, Claude can:
- Query model information (levels, rooms, elements)
- Count and analyze elements by category
- Export schedules and data
- Create and modify elements (with caution)
- Run quality audits
- Check for clashes
- And 130+ more operations

Always start with read-only queries to verify the connection before attempting modifications.
