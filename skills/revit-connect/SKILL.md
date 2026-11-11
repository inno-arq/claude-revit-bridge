---
name: revit-connect
description: Connect Claude to Revit automatically. Use when users say "connect to Revit", "open my Revit", "I want to use Revit", or ask about their Revit model. Detects the user's device automatically by email.
tools: []
---

# Connect Claude to Revit

Revit Bridge connects Claude to Autodesk Revit running on Windows. Once installed, connection is automatic - no credentials to copy.

## How it works

1. User installs Revit Bridge on their Windows PC (one time)
2. User opens Revit and activates the MCP switch
3. Claude detects their device automatically by email

## Check if user has Revit Bridge installed

Make a request to the hub to check if this user has a registered device:

```
GET https://revit-hub-476812260498.us-central1.run.app/discover?email={user_email}
```

- If **200 with `online: true`**: User is ready, proceed to query their model
- If **200 with `online: false`**: Device registered but Revit not running. Ask user to open Revit and activate the switch.
- If **404**: User needs to install Revit Bridge first

## Installation instructions (for new users)

Tell the user to run this in PowerShell on their Windows PC:

```powershell
irm https://raw.githubusercontent.com/inno-arq/claude-revit-bridge/main/installer/setup-revit-bridge.ps1 | iex
```

The installer will:
1. Ask for their email (must match their Claude account)
2. Install the Revit plugin automatically
3. Set up the connection tunnel
4. Configure auto-start

After installation, they just need to:
1. Open Revit with a model
2. Click **Add-Ins → Revit MCP Switch**
3. **Close** the "Open Server" dialog

## Querying Revit (once connected)

To interact with the user's Revit, make POST requests to:

```
POST https://revit-hub-476812260498.us-central1.run.app/connect
Content-Type: application/json

{
  "_email": "{user_email}",
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/list"
}
```

The `_email` field routes the request to the correct device automatically.

### Common methods:

**List available tools:**
```json
{"_email": "user@example.com", "jsonrpc": "2.0", "id": 1, "method": "tools/list"}
```

**Call a tool:**
```json
{
  "_email": "user@example.com",
  "jsonrpc": "2.0", 
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "get_project_info",
    "arguments": {}
  }
}
```

### Useful tools:
- `get_project_info` - Model name, number, address
- `get_levels` - All levels with elevations
- `get_rooms` - Rooms with areas
- `get_walls` / `get_doors` / `get_windows` - Elements by category
- `get_model_stats` - Element counts
- `check_model_health` - Quality audit

## Troubleshooting

### "No device registered"
User needs to run the installer with the same email they use in Claude.

### "Device unreachable" 
- Is Revit open with a model?
- Did they click the MCP Switch?
- Is the "Open Server" dialog closed?

### Timeouts
The "Open Server" dialog blocks Revit. It must be **closed**, not left open.

## Important notes

- The user's email in Claude must match the email they used in the installer
- Revit must have a `.rvt` project open (not a family `.rfa`)
- The MCP Switch must be activated each time Revit opens
- Start with read-only queries before attempting modifications
