---
name: revit-query
description: Query and analyze Revit models. Use when users ask about their model, want element counts, room data, level information, or any read-only Revit operation. Requires revit-hub MCP connection.
tools: [revit-hub]
---

# Query Revit Models

Perform read-only queries on connected Revit models.

## Prerequisites

- User must have Revit Bridge installed and running
- MCP connection `revit-hub` must be configured with their Device ID and API Key
- Revit must be open with a model and MCP Switch activated

## Common Queries

### Model Information
```
get_project_info - Get project name, number, address, client
get_model_stats - Element counts by category
get_document_info - File path, worksharing status
```

### Spatial Data
```
get_levels - List all levels with elevations
get_rooms - List rooms with areas, numbers, departments
get_areas - Area schemes and area elements
```

### Elements by Category
```
get_walls - All wall instances with types and dimensions
get_doors - Door instances with marks, sizes, rooms
get_windows - Window instances
get_floors - Floor elements with areas
get_roofs - Roof elements
get_stairs - Stair instances
get_railings - Railing elements
```

### Structural
```
get_structural_columns - Column instances
get_structural_beams - Beam instances  
get_structural_foundations - Foundation elements
```

### MEP
```
get_ducts - Duct instances
get_pipes - Pipe instances
get_electrical_equipment - Electrical panels, equipment
```

### Quality Checks
```
check_model_health - Overall model health metrics
workflow_model_audit - Comprehensive audit
get_warnings - Model warnings
get_unplaced_rooms - Rooms not in model
get_duplicate_marks - Elements with duplicate marks
```

## Query Patterns

### Counting elements
Ask: "How many walls are in the model?"
→ Use `get_model_stats` or `get_walls` then count

### Filtering by level
Ask: "Show me all doors on Level 1"
→ Use `get_doors` then filter by Level parameter

### Room analysis
Ask: "What's the total area of offices?"
→ Use `get_rooms`, filter by department/name, sum areas

### Export data
Ask: "Export a schedule of all windows"
→ Use `get_windows`, format as table

## Response Format

When presenting Revit data:
- Use tables for lists of elements
- Include element IDs for reference
- Convert units to metric (meters, square meters)
- Group by category or level when appropriate
- Highlight any issues or warnings found

## Error Handling

If a query fails:
1. Check connection status: "Can you reach the Revit server?"
2. Verify Revit state: "Is Revit open with a model?"
3. Check MCP Switch: "Did you activate the MCP Switch and close the dialog?"
