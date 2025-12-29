local M = {}

local context_module = require "marker-groups.context"

--- @alias RelocationStatus
--- | "exact"           # Full content + full context matched
--- | "content_only"    # Full content matched, context differs
--- | "anchors_context" # First/last lines + full context matched
--- | "context_only"    # Only context matched (content changed)
--- | "partial_context" # Shrunk context matched
--- | "unchanged"       # No match found, keeping original lines

--- @class RelocationResult
--- @field marker_id string
--- @field status RelocationStatus
--- @field new_start number
--- @field new_end number

--- @class MarkerFingerprint
--- @field marker_id string
--- @field marked_content string[]
--- @field context_before string[]
--- @field context_after string[]
--- @field original_start number
--- @field original_end number

--- @param file_lines string[]
--- @return table<string, number[]>
local function build_line_index(file_lines)
  local index = {}
  for i, line in ipairs(file_lines) do
    if not index[line] then
      index[line] = {}
    end
    table.insert(index[line], i)
  end
  return index
end

--- @param file_lines string[]
--- @param start_pos number
--- @param expected_lines string[]
--- @return boolean
local function sequence_matches(file_lines, start_pos, expected_lines)
  if #expected_lines == 0 then
    return true
  end
  for i, expected in ipairs(expected_lines) do
    local file_line = file_lines[start_pos + i - 1]
    if file_line ~= expected then
      return false
    end
  end
  return true
end

--- @param tbl1 table
--- @param tbl2 table
--- @param tbl3 table|nil
--- @return table
local function concat_tables(tbl1, tbl2, tbl3)
  local result = {}
  for _, v in ipairs(tbl1 or {}) do
    table.insert(result, v)
  end
  for _, v in ipairs(tbl2 or {}) do
    table.insert(result, v)
  end
  if tbl3 then
    for _, v in ipairs(tbl3) do
      table.insert(result, v)
    end
  end
  return result
end

--- @param line_index table<string, number[]>
--- @param file_lines string[]
--- @param sequence string[]
--- @return number[]
local function find_sequence_starts(line_index, file_lines, sequence)
  if #sequence == 0 then
    return {}
  end

  local first_line = sequence[1]
  local candidates = line_index[first_line] or {}

  local matches = {}
  for _, pos in ipairs(candidates) do
    if pos + #sequence - 1 <= #file_lines and sequence_matches(file_lines, pos, sequence) then
      table.insert(matches, pos)
    end
  end
  return matches
end

--- @param line_index table<string, number[]>
--- @param file_lines string[]
--- @param ctx_before string[]
--- @param ctx_after string[]
--- @param expected_gap number
--- @return {gap_start: number, gap_end: number}|nil
local function find_context_gap(line_index, file_lines, ctx_before, ctx_after, expected_gap)
  if #ctx_before == 0 or #ctx_after == 0 then
    return nil
  end

  local before_starts = find_sequence_starts(line_index, file_lines, ctx_before)

  for _, before_start in ipairs(before_starts) do
    local before_end = before_start + #ctx_before - 1
    local expected_after_start = before_end + expected_gap + 1

    local search_start = math.max(before_end + 1, expected_after_start - 10)
    local search_end = math.min(#file_lines, expected_after_start + 10)

    for after_start = search_start, search_end do
      if sequence_matches(file_lines, after_start, ctx_after) then
        local gap_start = before_end + 1
        local gap_end = after_start - 1
        if gap_end >= gap_start then
          return { gap_start = gap_start, gap_end = gap_end }
        end
      end
    end
  end

  return nil
end

--- @param tbl table
--- @return table
local function shallow_copy(tbl)
  local copy = {}
  for i, v in ipairs(tbl) do
    copy[i] = v
  end
  return copy
end

--- @param fingerprint MarkerFingerprint
--- @param file_lines string[]
--- @param line_index table<string, number[]>
--- @return RelocationResult
local function relocate_single(fingerprint, file_lines, line_index)
  local content = fingerprint.marked_content
  local ctx_before = fingerprint.context_before or {}
  local ctx_after = fingerprint.context_after or {}
  local content_len = #content

  local unchanged_result = {
    marker_id = fingerprint.marker_id,
    status = "unchanged",
    new_start = fingerprint.original_start,
    new_end = fingerprint.original_end,
  }

  if content_len == 0 and #ctx_before == 0 and #ctx_after == 0 then
    return unchanged_result
  end

  local full_sequence = concat_tables(ctx_before, content, ctx_after)
  if #full_sequence > 0 then
    local full_matches = find_sequence_starts(line_index, file_lines, full_sequence)
    if #full_matches == 1 then
      local new_start = full_matches[1] + #ctx_before
      return {
        marker_id = fingerprint.marker_id,
        status = "exact",
        new_start = new_start,
        new_end = new_start + content_len - 1,
      }
    end
  end

  if content_len > 0 then
    local content_matches = find_sequence_starts(line_index, file_lines, content)
    if #content_matches == 1 then
      return {
        marker_id = fingerprint.marker_id,
        status = "content_only",
        new_start = content_matches[1],
        new_end = content_matches[1] + content_len - 1,
      }
    end
  end

  if content_len >= 2 and (#ctx_before > 0 or #ctx_after > 0) then
    local anchor_sequence = concat_tables(ctx_before, { content[1], content[content_len] }, ctx_after)
    local anchor_matches = find_sequence_starts(line_index, file_lines, anchor_sequence)
    if #anchor_matches == 1 then
      local new_start = anchor_matches[1] + #ctx_before
      return {
        marker_id = fingerprint.marker_id,
        status = "anchors_context",
        new_start = new_start,
        new_end = new_start + content_len - 1,
      }
    end
  end

  if #ctx_before > 0 and #ctx_after > 0 then
    local gap_result = find_context_gap(line_index, file_lines, ctx_before, ctx_after, content_len)
    if gap_result then
      return {
        marker_id = fingerprint.marker_id,
        status = "context_only",
        new_start = gap_result.gap_start,
        new_end = gap_result.gap_end,
      }
    end
  end

  local shrunk_before = shallow_copy(ctx_before)
  local shrunk_after = shallow_copy(ctx_after)

  while #shrunk_before > 0 or #shrunk_after > 0 do
    if #shrunk_before > 0 then
      table.remove(shrunk_before, 1)
    end
    if #shrunk_after > 0 then
      table.remove(shrunk_after)
    end

    if content_len > 0 then
      local shrunk_sequence = concat_tables(shrunk_before, content, shrunk_after)
      if #shrunk_sequence > 0 then
        local shrunk_matches = find_sequence_starts(line_index, file_lines, shrunk_sequence)
        if #shrunk_matches == 1 then
          local new_start = shrunk_matches[1] + #shrunk_before
          return {
            marker_id = fingerprint.marker_id,
            status = "partial_context",
            new_start = new_start,
            new_end = new_start + content_len - 1,
          }
        end
      end
    end

    if #shrunk_before > 0 and #shrunk_after > 0 then
      local gap_result = find_context_gap(line_index, file_lines, shrunk_before, shrunk_after, content_len)
      if gap_result then
        return {
          marker_id = fingerprint.marker_id,
          status = "partial_context",
          new_start = gap_result.gap_start,
          new_end = gap_result.gap_end,
        }
      end
    end
  end

  return unchanged_result
end

--- @param file_path string
--- @param markers table[]
--- @return RelocationResult[]
function M.relocate_markers_for_file(file_path, markers)
  local file_lines, _ = context_module.read_file_lines(file_path, { force_disk = true })

  if not file_lines then
    local results = {}
    for _, m in ipairs(markers) do
      table.insert(results, {
        marker_id = m.id,
        status = "unchanged",
        new_start = m.start_line,
        new_end = m.end_line,
      })
    end
    return results
  end

  local line_index = build_line_index(file_lines)

  local results = {}
  for _, marker in ipairs(markers) do
    if context_module.has_context(marker) then
      local fingerprint = {
        marker_id = marker.id,
        marked_content = marker.marked_content,
        context_before = marker.context_before or {},
        context_after = marker.context_after or {},
        original_start = marker.start_line,
        original_end = marker.end_line,
      }
      table.insert(results, relocate_single(fingerprint, file_lines, line_index))
    else
      table.insert(results, {
        marker_id = marker.id,
        status = "unchanged",
        new_start = marker.start_line,
        new_end = marker.end_line,
      })
    end
  end

  return results
end

--- @param markers table[]
--- @return RelocationResult[]
function M.relocate_all_markers(markers)
  local markers_by_file = {}
  for _, marker in ipairs(markers) do
    local path = marker.buffer_path
    if not markers_by_file[path] then
      markers_by_file[path] = {}
    end
    table.insert(markers_by_file[path], marker)
  end

  local all_results = {}
  for file_path, file_markers in pairs(markers_by_file) do
    local results = M.relocate_markers_for_file(file_path, file_markers)
    for _, result in ipairs(results) do
      table.insert(all_results, result)
    end
  end

  return all_results
end

M._build_line_index = build_line_index
M._sequence_matches = sequence_matches
M._find_sequence_starts = find_sequence_starts
M._find_context_gap = find_context_gap
M._relocate_single = relocate_single

return M
