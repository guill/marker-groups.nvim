---
title: Configuration
---

```lua
require("marker-groups").setup({
  data_dir = vim.fn.stdpath("data") .. "/marker-groups",
  debug = false,
  log_level = "info",
  drawer_config = {
    width = 60,
    side = "right",
    border = "rounded",
    title_pos = "center",
  },
  context_lines = 2,
  max_annotation_display = 50,
  
  -- Annotation display mode and options
  annotation_display = {
    mode = "eol",           -- "eol" | "below" | "hidden"
    max_virtual_lines = 5,  -- Max lines shown in "below" mode
    wrap_width = 0,         -- Auto-wrap width (0 = auto based on window)
    show_borders = true,    -- Show box-drawing borders in "below" mode
  },
  
  highlight_groups = {
    marker = "MarkerGroupsMarker",
    annotation = "MarkerGroupsAnnotation",
    context = "MarkerGroupsContext",
    multiline_start = "MarkerGroupsMultilineStart",
    multiline_end = "MarkerGroupsMultilineEnd",
    annotation_border = "MarkerGroupsAnnotationBorder",
  },
  keymaps = {
    enabled = true,
    prefix = "<leader>m",
    mappings = {
      marker = {
        add = { suffix = "a", mode = { "n", "v" }, desc = "Add marker" },
        edit = { suffix = "e", desc = "Edit marker at cursor" },
        delete = { suffix = "d", desc = "Delete marker at cursor" },
        list = { suffix = "l", desc = "List markers in buffer" },
          },
      group = {
        create = { suffix = "gc", desc = "Create marker group" },
        select = { suffix = "gs", desc = "Select marker group" },
        list = { suffix = "gl", desc = "List marker groups" },
        rename = { suffix = "gr", desc = "Rename marker group" },
        delete = { suffix = "gd", desc = "Delete marker group" },
      },
      view = { toggle = { suffix = "v", desc = "Toggle drawer marker viewer" } },
      
    },
  },
  -- Picker backend (default: 'vim')
  -- Accepted values: 'vim' | 'snacks' | 'fzf-lua' | 'mini.pick' | 'telescope'
  -- Invalid values fall back to 'vim'.
  picker = 'vim',
})
```

## Limits

- Annotations: up to 1000 UTF‑8 characters and 10 lines (inputs exceeding these are truncated)
- Group names: up to 100 UTF‑8 characters (inputs longer than this are truncated)

## Annotation Display Modes

The `annotation_display.mode` option controls how annotations are displayed inline:

| Mode | Description |
|------|-------------|
| `"eol"` | (Default) Display at end of line. Multi-line annotations show first line with "(+N lines)" indicator. |
| `"below"` | Display as virtual lines below the code. Supports multi-line with word wrapping and box-drawing borders. |
| `"hidden"` | Hide all inline annotations. Markers are only visible in the drawer. |

You can change modes at runtime using `:MarkerAnnotationMode {mode}` or cycle through modes with `:MarkerAnnotationMode` (no argument).

### Lua API

```lua
-- Get current mode
local mode = require("marker-groups").get_annotation_mode()

-- Set mode
require("marker-groups").set_annotation_mode("below")
```


