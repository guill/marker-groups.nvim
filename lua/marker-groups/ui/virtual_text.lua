local M = {}

local api = vim.api
local config = require "marker-groups.config"
local feedback = require "marker-groups.feedback"

local _cached_namespaces = {}

local _update_timers = {}
local _hydrating = false

local function get_smallest_window_width(bufnr)
  local smallest_width = nil
  for _, win in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_buf(win) == bufnr then
      local width = api.nvim_win_get_width(win)
      if not smallest_width or width < smallest_width then
        smallest_width = width
      end
    end
  end
  return smallest_width or 80
end

local function word_wrap(text, width)
  if width <= 0 or #text <= width then
    return { text }
  end

  local result = {}
  local begin_pos = 1

  while begin_pos + width < #text do
    local end_pos = begin_pos + width
    local substring = string.sub(text, begin_pos, end_pos)
    local prestring, after_space = string.match(substring, "(.*)%s+()")

    if not after_space then
      prestring = substring
      after_space = begin_pos + #substring
    end

    table.insert(result, prestring)
    begin_pos = begin_pos + after_space - 1
  end

  table.insert(result, string.sub(text, begin_pos))
  return result
end

local function get_namespace(name)
  if not _cached_namespaces[name] then
    _cached_namespaces[name] = api.nvim_create_namespace(name)
  end
  return _cached_namespaces[name]
end

function M.setup_highlights()
  local bg = vim.o.background
  local colorscheme = vim.g.colors_name or "default"

  local highlights = {
    MarkerGroupsMarker = {
      light = { fg = "#0451A5", bg = "#F3F3F3" },
      dark = { fg = "#61AFEF", bg = "#2C323C" },
    },
    MarkerGroupsAnnotation = {
      light = { fg = "#0E8A00", italic = true },
      dark = { fg = "#98C379", italic = true },
    },
    MarkerGroupsContext = {
      light = { fg = "#6A6A6A" },
      dark = { fg = "#ABB2BF" },
    },
    MarkerGroupsMultilineStart = {
      light = { fg = "#AF00DB", bold = true },
      dark = { fg = "#C678DD", bold = true },
    },
    MarkerGroupsMultilineEnd = {
      light = { fg = "#AF00DB" },
      dark = { fg = "#C678DD" },
    },
    MarkerGroupsAnnotationBorder = {
      light = { fg = "#6A6A6A" },
      dark = { fg = "#5C6370" },
    },
  }

  local cfg = config.get()
  local hls = cfg.highlight_groups or {}
  local name_map = {
    MarkerGroupsMarker = hls.marker or "MarkerGroupsMarker",
    MarkerGroupsAnnotation = hls.annotation or "MarkerGroupsAnnotation",
    MarkerGroupsContext = hls.context or "MarkerGroupsContext",
    MarkerGroupsMultilineStart = hls.multiline_start or "MarkerGroupsMultilineStart",
    MarkerGroupsMultilineEnd = hls.multiline_end or "MarkerGroupsMultilineEnd",
    MarkerGroupsAnnotationBorder = hls.annotation_border or "MarkerGroupsAnnotationBorder",
  }

  for default_group, colors in pairs(highlights) do
    local hl_opts = bg == "light" and colors.light or colors.dark
    hl_opts.default = true

    api.nvim_set_hl(0, default_group, hl_opts)

    local custom_group = name_map[default_group]
    if custom_group ~= default_group then
      pcall(api.nvim_set_hl, 0, custom_group, { link = default_group, default = true })
    end
  end

  local group = api.nvim_create_augroup("MarkerGroupsHighlights", { clear = true })
  api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      M.setup_highlights()
    end,
    desc = "Update marker groups highlights on colorscheme change",
  })
end

local function format_annotation(annotation, max_length)
  if not annotation or annotation == "" then
    return "(no annotation)"
  end

  max_length = max_length or config.get_value("max_annotation_display", 50)

  local lines = vim.split(annotation, "\n", { plain = true })
  local formatted = lines[1] or ""

  if #lines > 1 then
    local suffix = string.format(" (+%d lines)", #lines - 1)
    local available = max_length - #suffix
    if #formatted > available then
      formatted = formatted:sub(1, math.max(1, available - 3)) .. "..."
    end
    formatted = formatted .. suffix
  elseif #formatted > max_length then
    formatted = formatted:sub(1, max_length - 3) .. "..."
  end

  return formatted
end

local function create_marker_virtual_text(marker, marker_type, context_info)
  local cfg = config.get()
  local hls = cfg.highlight_groups or {}
  local hl_marker = hls.marker or "MarkerGroupsMarker"
  local hl_annotation = hls.annotation or "MarkerGroupsAnnotation"
  local hl_context = hls.context or "MarkerGroupsContext"
  local hl_ml_start = hls.multiline_start or "MarkerGroupsMultilineStart"
  local hl_ml_end = hls.multiline_end or "MarkerGroupsMultilineEnd"
  marker_type = marker_type or (marker.start_line == marker.end_line and "single" or "multiline_start")

  local annotation = format_annotation(marker.annotation)
  local virtual_text = {}

  table.insert(virtual_text, { " ", "Normal" })

  if marker_type == "single" then
    table.insert(virtual_text, { cfg.signs.marker .. " ", hl_marker })
    table.insert(virtual_text, { annotation, hl_annotation })
  elseif marker_type == "multiline_start" then
    table.insert(virtual_text, { cfg.signs.multiline_start .. " ", hl_ml_start })
    table.insert(virtual_text, { annotation, hl_annotation })
  elseif marker_type == "multiline_end" then
    table.insert(virtual_text, { cfg.signs.multiline_end .. " ", hl_ml_end })
    table.insert(virtual_text, { context_info or ("End: " .. format_annotation(annotation, 25)), hl_context })
  end

  if cfg.debug then
    local line_info = marker_type == "single" and string.format(" [L%d]", marker.start_line)
      or string.format(" [L%d-%d]", marker.start_line, marker.end_line)
    table.insert(virtual_text, { line_info, hl_context })
  end

  return virtual_text
end

local function create_annotation_virt_lines(marker, bufnr, display_config)
  local cfg = config.get()
  local hls = cfg.highlight_groups or {}
  local hl_annotation = hls.annotation or "MarkerGroupsAnnotation"
  local hl_border = hls.annotation_border or "MarkerGroupsAnnotationBorder"
  local hl_marker = hls.marker or "MarkerGroupsMarker"
  local hl_context = hls.context or "MarkerGroupsContext"

  local annotation = marker.annotation or ""
  if annotation == "" then
    return nil
  end

  local max_lines = display_config.max_virtual_lines or 5
  local show_borders = display_config.show_borders ~= false
  local wrap_width = display_config.wrap_width or 0

  if wrap_width == 0 then
    local win_width = get_smallest_window_width(bufnr)
    wrap_width = math.max(20, win_width - 10)
  end

  local raw_lines = vim.split(annotation, "\n", { plain = true })
  local wrapped_lines = {}

  for _, line in ipairs(raw_lines) do
    local wrapped = word_wrap(line, wrap_width - 6)
    for _, wl in ipairs(wrapped) do
      table.insert(wrapped_lines, wl)
    end
  end

  local virt_lines = {}
  local truncated = #wrapped_lines > max_lines

  if show_borders then
    table.insert(virt_lines, {
      { "   ", "" },
      { "┌─ ", hl_border },
      { cfg.signs.marker .. " ", hl_marker },
    })
  end

  local lines_to_show = truncated and max_lines or #wrapped_lines
  for i = 1, lines_to_show do
    local line_content = wrapped_lines[i] or ""
    if show_borders then
      table.insert(virt_lines, {
        { "   ", "" },
        { "│ ", hl_border },
        { line_content, hl_annotation },
      })
    else
      table.insert(virt_lines, {
        { "     ", "" },
        { line_content, hl_annotation },
      })
    end
  end

  if truncated then
    local remaining = #wrapped_lines - max_lines
    if show_borders then
      table.insert(virt_lines, {
        { "   ", "" },
        { "│ ", hl_border },
        { string.format("(+%d more lines...)", remaining), hl_context },
      })
    else
      table.insert(virt_lines, {
        { "     ", "" },
        { string.format("(+%d more lines...)", remaining), hl_context },
      })
    end
  end

  if show_borders then
    table.insert(virt_lines, {
      { "   ", "" },
      { "└─────────────", hl_border },
    })
  end

  return virt_lines
end

local function render_multiline_below_mode(buf, vt_ns, marker, display_config, priority)
  local cfg = config.get()
  local hls = cfg.highlight_groups or {}
  local hl_border = hls.annotation_border or "MarkerGroupsAnnotationBorder"
  local hl_marker = hls.marker or "MarkerGroupsMarker"
  local hl_annotation = hls.annotation or "MarkerGroupsAnnotation"
  local hl_context = hls.context or "MarkerGroupsContext"

  local show_borders = display_config.show_borders ~= false
  local max_lines = display_config.max_virtual_lines or 5
  local wrap_width = display_config.wrap_width or 0

  if wrap_width == 0 then
    local win_width = get_smallest_window_width(buf)
    wrap_width = math.max(20, win_width - 10)
  end

  local start_line = marker.start_line
  local end_line = marker.end_line

  if show_borders then
    api.nvim_buf_set_extmark(buf, vt_ns, start_line - 1, 0, {
      virt_lines = { { { "┌─ ", hl_border }, { cfg.signs.marker .. " ", hl_marker } } },
      virt_lines_above = true,
      hl_mode = "combine",
      priority = priority,
    })
  end

  if show_borders then
    for line_num = start_line, end_line do
      local line_idx = line_num - 1
      local line_content = api.nvim_buf_get_lines(buf, line_idx, line_idx + 1, false)[1] or ""
      local first_char = line_content:sub(1, 1)

      if first_char == "" or first_char:match("%s") then
        api.nvim_buf_set_extmark(buf, vt_ns, line_idx, 0, {
          virt_text = { { "│", hl_border } },
          virt_text_pos = "overlay",
          hl_mode = "combine",
          priority = priority,
        })
      end
    end
  end

  local annotation = marker.annotation or ""
  if annotation == "" then
    if show_borders then
      api.nvim_buf_set_extmark(buf, vt_ns, end_line - 1, 0, {
        virt_lines = { { { "└─────────────", hl_border } } },
        virt_lines_above = false,
        hl_mode = "combine",
        priority = priority,
      })
    end
    return
  end

  local raw_lines = vim.split(annotation, "\n", { plain = true })
  local wrapped_lines = {}

  for _, line in ipairs(raw_lines) do
    local wrapped = word_wrap(line, wrap_width - 4)
    for _, wl in ipairs(wrapped) do
      table.insert(wrapped_lines, wl)
    end
  end

  local virt_lines = {}
  local truncated = #wrapped_lines > max_lines

  if show_borders then
    table.insert(virt_lines, { { "├──", hl_border } })
  end

  local lines_to_show = truncated and max_lines or #wrapped_lines
  for i = 1, lines_to_show do
    local line_content = wrapped_lines[i] or ""
    if show_borders then
      table.insert(virt_lines, { { "│ ", hl_border }, { line_content, hl_annotation } })
    else
      table.insert(virt_lines, { { "  ", "" }, { line_content, hl_annotation } })
    end
  end

  if truncated then
    local remaining = #wrapped_lines - max_lines
    if show_borders then
      table.insert(virt_lines, { { "│ ", hl_border }, { string.format("(+%d more lines...)", remaining), hl_context } })
    else
      table.insert(virt_lines, { { "  ", "" }, { string.format("(+%d more lines...)", remaining), hl_context } })
    end
  end

  if show_borders then
    table.insert(virt_lines, { { "└─────────────", hl_border } })
  end

  api.nvim_buf_set_extmark(buf, vt_ns, end_line - 1, 0, {
    virt_lines = virt_lines,
    virt_lines_above = false,
    hl_mode = "combine",
    priority = priority,
  })
end

function M.update_buffer_display(buf, markers)
  if not api.nvim_buf_is_valid(buf) then
    return
  end

  local cfg = config.get()
  local display_config = cfg.annotation_display or {}
  local display_mode = display_config.mode or "eol"

  local vt_ns = get_namespace "marker_groups_virtual_text"

  api.nvim_buf_clear_namespace(buf, vt_ns, 0, -1)

  if display_mode == "hidden" then
    return
  end

  table.sort(markers, function(a, b)
    return a.start_line < b.start_line
  end)

  for i, marker in ipairs(markers) do
    local success, err = pcall(function()
      local marker_type = marker.start_line == marker.end_line and "single" or "multiline_start"

      if display_mode == "below" then
        render_multiline_below_mode(buf, vt_ns, marker, display_config, 1000 + i)
      else
        local virtual_text = create_marker_virtual_text(marker, marker_type)
        api.nvim_buf_set_extmark(buf, vt_ns, marker.start_line - 1, -1, {
          virt_text = virtual_text,
          virt_text_pos = "eol",
          hl_mode = "combine",
          priority = 1000 + i,
        })

        if marker.end_line > marker.start_line then
          local end_vt =
            create_marker_virtual_text(marker, "multiline_end", "End: " .. format_annotation(marker.annotation, 30))
          api.nvim_buf_set_extmark(buf, vt_ns, marker.end_line - 1, -1, {
            virt_text = end_vt,
            virt_text_pos = "eol",
            hl_mode = "combine",
            priority = 1000 + i,
          })
        end
      end
    end)

    if not success and cfg.debug then
      require("marker-groups.feedback").notify(
        string.format("Failed to create virtual text for marker %s: %s", marker.id or "unknown", err),
        vim.log.levels.WARN,
        {}
      )
    end
  end
end

function M.clear_buffer_display(buf)
  if not api.nvim_buf_is_valid(buf) then
    return
  end

  local vt_ns = get_namespace "marker_groups_virtual_text"
  api.nvim_buf_clear_namespace(buf, vt_ns, 0, -1)
end

local _virtual_text_enabled = true

function M.toggle_display(enabled)
  local new_state = enabled ~= nil and enabled or not _virtual_text_enabled
  _virtual_text_enabled = new_state

  if new_state then
    M.update_all_buffers()
    require("marker-groups.feedback").notify("Marker virtual text enabled", vim.log.levels.INFO, {})
  else
    for _, buf in ipairs(api.nvim_list_bufs()) do
      if api.nvim_buf_is_loaded(buf) then
        M.clear_buffer_display(buf)
      end
    end
    require("marker-groups.feedback").notify("Marker virtual text disabled", vim.log.levels.INFO, {})
  end
end

function M.is_enabled()
  return _virtual_text_enabled
end

function M.debug_info()
  local info = {
    enabled = M.is_enabled(),
    namespace_cache = vim.tbl_keys(_cached_namespaces),
    highlight_groups = {},
    loaded_buffers_with_markers = 0,
  }

  do
    local cfg = config.get()
    local hls = cfg.highlight_groups or {}
    local groups = {
      hls.marker or "MarkerGroupsMarker",
      hls.annotation or "MarkerGroupsAnnotation",
      hls.context or "MarkerGroupsContext",
      hls.multiline_start or "MarkerGroupsMultilineStart",
      hls.multiline_end or "MarkerGroupsMultilineEnd",
    }
    for _, group in ipairs(groups) do
      local hl = api.nvim_get_hl(0, { name = group })
      info.highlight_groups[group] = hl
    end
  end

  local state = require "marker-groups.state"
  local active_group = state.get_group()
  if active_group then
    local paths = {}
    for _, marker in ipairs(active_group.markers) do
      paths[marker.buffer_path] = true
    end
    for path in pairs(paths) do
      local buf = vim.fn.bufnr(path)
      if buf ~= -1 and api.nvim_buf_is_loaded(buf) then
        info.loaded_buffers_with_markers = info.loaded_buffers_with_markers + 1
      end
    end
  end

  return info
end

function M.refresh_buffer(buf, immediate)
  buf = buf or api.nvim_get_current_buf()

  if not api.nvim_buf_is_valid(buf) then
    return
  end

  local buf_path = api.nvim_buf_get_name(buf)
  if not buf_path or buf_path == "" then
    return
  end

  if not immediate then
    if _update_timers[buf] then
      _update_timers[buf]:stop()
    end

    _update_timers[buf] = vim.defer_fn(function()
      _update_timers[buf] = nil
      M.refresh_buffer(buf, true)
    end, 100)
    return
  end

  local markers = require("marker-groups.markers").list_markers(nil, {
    buffer_path = buf_path,
  })

  M.update_buffer_display(buf, markers)
end

function M.force_refresh_all()
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(buf) then
      M.refresh_buffer(buf, true)
    end
  end
end

function M.update_all_buffers()
  if not M.is_enabled() then
    return
  end

  local state = require "marker-groups.state"
  local active_group = state.get_group()

  if not active_group then
    return
  end

  local markers_by_buffer = {}
  for _, marker in ipairs(active_group.markers) do
    local path = marker.buffer_path
    if not markers_by_buffer[path] then
      markers_by_buffer[path] = {}
    end
    table.insert(markers_by_buffer[path], marker)
  end

  for path, markers in pairs(markers_by_buffer) do
    local buf = vim.fn.bufnr(path)
    if buf ~= -1 and api.nvim_buf_is_loaded(buf) then
      M.update_buffer_display(buf, markers)
    end
  end

  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(buf) then
      local buf_path = api.nvim_buf_get_name(buf)
      if buf_path and buf_path ~= "" and not markers_by_buffer[buf_path] then
        M.clear_buffer_display(buf)
      end
    end
  end
end

function M.setup_auto_updates()
  local state = require "marker-groups.state"

  state.on("active_group_changed", function(data)
    vim.schedule(function()
      M.update_all_buffers()
    end)
  end)

  state.on("marker_added", function(data)
    vim.schedule(function()
      local buf = vim.fn.bufnr(data.marker.buffer_path)
      if buf ~= -1 and api.nvim_buf_is_loaded(buf) then
        local markers = require("marker-groups.markers").list_markers(nil, {
          buffer_path = data.marker.buffer_path,
        })
        M.update_buffer_display(buf, markers)
      end
    end)
  end)

  state.on("marker_removed", function(data)
    vim.schedule(function()
      local buf = vim.fn.bufnr(data.marker.buffer_path)
      if buf ~= -1 and api.nvim_buf_is_loaded(buf) then
        local markers = require("marker-groups.markers").list_markers(nil, {
          buffer_path = data.marker.buffer_path,
        })
        M.update_buffer_display(buf, markers)
      end
    end)
  end)

  state.on("group_created", function(data)
    vim.schedule(function()
      -- Suppress noisy create notification to avoid confusion during hydration and normal use
      -- Visual updates are handled elsewhere; no notification needed here.
      return
    end)
  end)

  state.on("group_renamed", function(data)
    vim.schedule(function()
      M.update_all_buffers()
      feedback.notify("Group renamed: " .. data.old_name .. " -> " .. data.new_name, feedback.levels.DEBUG)
    end)
  end)

  state.on("group_deleted", function(data)
    vim.schedule(function()
      M.update_all_buffers()
      feedback.notify("Group deleted: " .. data.group_name, feedback.levels.DEBUG)
    end)
  end)

  state.on("group_loaded", function(data)
    vim.schedule(function()
      if require("marker-groups.config").get_value("debug", false) then
        feedback.notify("Group loaded: " .. data.group_name, feedback.levels.DEBUG)
      end
    end)
  end)

  state.on("buffer_major_change", function(data)
    vim.schedule(function()
      if api.nvim_buf_is_valid(data.buffer) then
        local markers = require("marker-groups.markers").list_markers(nil, {
          buffer_path = data.path,
        })
        M.update_buffer_display(data.buffer, markers)
      end
    end)
  end)

  state.on("state_initialized", function(data)
    vim.schedule(function()
      M.update_all_buffers()
      feedback.notify("Marker groups UI synchronized with state", feedback.levels.DEBUG)
      -- Suppress noisy create logs briefly during hydration sequence
      _hydrating = true
      vim.defer_fn(function()
        _hydrating = false
      end, 600)
    end)
  end)

  M.setup_buffer_autocmds()
end

function M.setup_buffer_autocmds()
  local group = api.nvim_create_augroup("MarkerGroupsVirtualText", { clear = true })

  api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(args)
      local buf = args.buf
      if M.is_enabled() and api.nvim_buf_is_valid(buf) then
        vim.schedule(function()
          M.refresh_buffer(buf)
        end)
      end
    end,
    desc = "Update marker virtual text on buffer enter",
  })

  api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(args)
      local buf = args.buf
      if M.is_enabled() and api.nvim_buf_is_valid(buf) then
        vim.schedule(function()
          M.refresh_buffer(buf)
        end)
      end
    end,
    desc = "Update marker virtual text after buffer save",
  })

  api.nvim_create_autocmd("BufUnload", {
    group = group,
    callback = function(args)
      local buf = args.buf
      if api.nvim_buf_is_valid(buf) then
        M.clear_buffer_display(buf)
      end
    end,
    desc = "Clear marker virtual text on buffer unload",
  })

  api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function()
      if M.is_enabled() then
        local buf = api.nvim_get_current_buf()
        if api.nvim_buf_is_valid(buf) then
          vim.schedule(function()
            M.refresh_buffer(buf)
          end)
        end
      end
    end,
    desc = "Update marker virtual text on window enter",
  })

  api.nvim_create_autocmd("ModeChanged", {
    group = group,
    callback = function()
      if M.is_enabled() then
        local buf = api.nvim_get_current_buf()
        if api.nvim_buf_is_valid(buf) then
          vim.defer_fn(function()
            M.refresh_buffer(buf)
          end, 50)
        end
      end
    end,
    desc = "Update marker virtual text on mode change",
  })
end

function M.clear_buffer_autocmds()
  pcall(api.nvim_del_augroup_by_name, "MarkerGroupsVirtualText")
end

function M.get_annotation_mode()
  return config.get_value("annotation_display.mode", "eol")
end

function M.set_annotation_mode(mode)
  local valid_modes = { eol = true, below = true, hidden = true }
  if not valid_modes[mode] then
    return false, "Invalid mode. Must be 'eol', 'below', or 'hidden'"
  end

  config.update { annotation_display = { mode = mode } }
  M.update_all_buffers()
  return true, nil
end

function M.cycle_annotation_mode()
  local modes = { "eol", "below", "hidden" }
  local current = M.get_annotation_mode()
  local current_idx = 1

  for i, m in ipairs(modes) do
    if m == current then
      current_idx = i
      break
    end
  end

  local next_idx = (current_idx % #modes) + 1
  local next_mode = modes[next_idx]
  M.set_annotation_mode(next_mode)
  return next_mode
end

return M
