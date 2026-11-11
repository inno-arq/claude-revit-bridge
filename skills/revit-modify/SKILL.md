---
name: revit-modify
description: Modify Revit models - create, edit, or delete elements. Use when users want to make changes to their model. CAUTION - modifications cannot be easily undone. Requires revit-hub MCP connection.
tools: [revit-hub]
---

# Modify Revit Models

Create, edit, and delete elements in connected Revit models.

## CRITICAL WARNINGS

Before ANY modification:

1. **Undo is limited** - Revit's undo does not group MCP operations. Each change is separate.
2. **Start with test models** - Never modify production files on first use.
3. **Verify before modifying** - Always query the current state before making changes.
4. **Confirm with user** - Always ask for explicit confirmation before modifications.

## Prerequisites

- All prerequisites from `revit-query`
- User explicitly requests a modification
- User confirms understanding of undo limitations

## Modification Operations

### Creating Elements
```
create_wall - Create a wall between two points
create_floor - Create a floor from boundary
create_room - Place a room in an enclosed area
create_door - Insert a door in a wall
create_window - Insert a window in a wall
place_family_instance - Place any loaded family
```

### Editing Elements
```
set_parameter_value - Change any parameter on an element
move_element - Move element to new location
rotate_element - Rotate element
copy_element - Create a copy of an element
mirror_element - Mirror element across axis
```

### Deleting Elements
```
delete_element - Delete a single element
delete_elements - Delete multiple elements by ID
```

### Batch Operations
```
tag_all_walls - Add tags to all walls
tag_all_doors - Add tags to all doors
renumber_rooms - Renumber rooms sequentially
```

## Modification Workflow

1. **Query first**: Get current state
2. **Propose change**: Describe what will be modified
3. **Get confirmation**: Explicit user approval
4. **Execute**: Make the modification
5. **Verify**: Query again to confirm change

Example dialogue:
```
User: "Add a door to the wall between Room 101 and Room 102"

Claude: 
1. First let me find that wall... [queries walls, finds wall ID 12345]
2. I found wall 12345 between those rooms. I'll place a standard single door.
   
   **Proposed change:**
   - Wall: 12345
   - Door type: Single Flush 0915x2134mm
   - Location: Center of wall
   
   Should I proceed? (This will modify your model)

User: "Yes"

Claude: [executes create_door, verifies placement]
Done! Door placed with ID 67890. The door opens into Room 102.
```

## Safety Rules

1. **Never auto-modify** - Always require explicit user request
2. **Limit scope** - One modification at a time unless explicitly asked for batch
3. **Provide rollback info** - Tell user the element ID so they can undo manually
4. **Check for issues** - Run `check_model_health` after significant changes
5. **Document changes** - Summarize what was modified at the end

## Family Activation

Before placing family instances:
```
activate_family_symbol - Must activate a family type before placing instances
```

This must be done in a separate transaction BEFORE the placement.

## Error Recovery

If a modification fails:
1. The model may be in an inconsistent state
2. Check `get_warnings` for new warnings
3. User may need to undo manually in Revit
4. Report the error clearly with element IDs involved
