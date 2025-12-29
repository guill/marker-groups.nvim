local MiniTest = require "mini.test"

local T = MiniTest.new_set()

local relocator = require "marker-groups.relocator"

local function make_marker(id, start_line, end_line, marked_content, context_before, context_after)
  return {
    id = id,
    buffer_path = "/test/file.lua",
    start_line = start_line,
    end_line = end_line,
    marked_content = marked_content,
    context_before = context_before or {},
    context_after = context_after or {},
  }
end

T["build_line_index / creates index mapping lines to positions"] = function()
  local file_lines = { "line1", "line2", "line1", "line3" }
  local index = relocator._build_line_index(file_lines)

  MiniTest.expect.equality(index["line1"], { 1, 3 })
  MiniTest.expect.equality(index["line2"], { 2 })
  MiniTest.expect.equality(index["line3"], { 4 })
  MiniTest.expect.equality(index["nonexistent"], nil)
end

T["build_line_index / handles empty file"] = function()
  local index = relocator._build_line_index({})
  MiniTest.expect.equality(vim.tbl_count(index), 0)
end

T["sequence_matches / returns true for matching sequence"] = function()
  local file_lines = { "a", "b", "c", "d" }
  MiniTest.expect.equality(relocator._sequence_matches(file_lines, 2, { "b", "c" }), true)
end

T["sequence_matches / returns false for non-matching sequence"] = function()
  local file_lines = { "a", "b", "c", "d" }
  MiniTest.expect.equality(relocator._sequence_matches(file_lines, 2, { "b", "x" }), false)
end

T["sequence_matches / returns true for empty sequence"] = function()
  local file_lines = { "a", "b", "c" }
  MiniTest.expect.equality(relocator._sequence_matches(file_lines, 1, {}), true)
end

T["find_sequence_starts / finds single occurrence"] = function()
  local file_lines = { "a", "b", "c", "d" }
  local index = relocator._build_line_index(file_lines)
  local starts = relocator._find_sequence_starts(index, file_lines, { "b", "c" })
  MiniTest.expect.equality(starts, { 2 })
end

T["find_sequence_starts / finds multiple occurrences"] = function()
  local file_lines = { "a", "b", "a", "b" }
  local index = relocator._build_line_index(file_lines)
  local starts = relocator._find_sequence_starts(index, file_lines, { "a", "b" })
  MiniTest.expect.equality(starts, { 1, 3 })
end

T["find_sequence_starts / returns empty for no match"] = function()
  local file_lines = { "a", "b", "c" }
  local index = relocator._build_line_index(file_lines)
  local starts = relocator._find_sequence_starts(index, file_lines, { "x", "y" })
  MiniTest.expect.equality(starts, {})
end

T["relocate / exact match at original position"] = function()
  local file_lines = {
    "context before",
    "marked line 1",
    "marked line 2",
    "context after",
  }
  local index = relocator._build_line_index(file_lines)

  local fingerprint = {
    marker_id = "test-1",
    marked_content = { "marked line 1", "marked line 2" },
    context_before = { "context before" },
    context_after = { "context after" },
    original_start = 2,
    original_end = 3,
  }

  local result = relocator._relocate_single(fingerprint, file_lines, index)
  MiniTest.expect.equality(result.status, "exact")
  MiniTest.expect.equality(result.new_start, 2)
  MiniTest.expect.equality(result.new_end, 3)
end

T["relocate / content shifted down - finds new position"] = function()
  local file_lines = {
    "new line inserted",
    "another new line",
    "context before",
    "marked line 1",
    "marked line 2",
    "context after",
  }
  local index = relocator._build_line_index(file_lines)

  local fingerprint = {
    marker_id = "test-1",
    marked_content = { "marked line 1", "marked line 2" },
    context_before = { "context before" },
    context_after = { "context after" },
    original_start = 2,
    original_end = 3,
  }

  local result = relocator._relocate_single(fingerprint, file_lines, index)
  MiniTest.expect.equality(result.status, "exact")
  MiniTest.expect.equality(result.new_start, 4)
  MiniTest.expect.equality(result.new_end, 5)
end

T["relocate / content shifted up - finds new position"] = function()
  local file_lines = {
    "marked line 1",
    "marked line 2",
    "context after",
  }
  local index = relocator._build_line_index(file_lines)

  local fingerprint = {
    marker_id = "test-1",
    marked_content = { "marked line 1", "marked line 2" },
    context_before = {},
    context_after = { "context after" },
    original_start = 5,
    original_end = 6,
  }

  local result = relocator._relocate_single(fingerprint, file_lines, index)
  MiniTest.expect.equality(result.status, "exact")
  MiniTest.expect.equality(result.new_start, 1)
  MiniTest.expect.equality(result.new_end, 2)
end

T["relocate / content matches but context differs - content_only"] = function()
  local file_lines = {
    "different context",
    "marked line 1",
    "marked line 2",
    "also different",
  }
  local index = relocator._build_line_index(file_lines)

  local fingerprint = {
    marker_id = "test-1",
    marked_content = { "marked line 1", "marked line 2" },
    context_before = { "original context before" },
    context_after = { "original context after" },
    original_start = 2,
    original_end = 3,
  }

  local result = relocator._relocate_single(fingerprint, file_lines, index)
  MiniTest.expect.equality(result.status, "content_only")
  MiniTest.expect.equality(result.new_start, 2)
  MiniTest.expect.equality(result.new_end, 3)
end

T["relocate / content duplicated - keeps original position (ambiguous)"] = function()
  local file_lines = {
    "marked line",
    "other stuff",
    "marked line",
  }
  local index = relocator._build_line_index(file_lines)

  local fingerprint = {
    marker_id = "test-1",
    marked_content = { "marked line" },
    context_before = {},
    context_after = {},
    original_start = 1,
    original_end = 1,
  }

  local result = relocator._relocate_single(fingerprint, file_lines, index)
  MiniTest.expect.equality(result.status, "unchanged")
  MiniTest.expect.equality(result.new_start, 1)
  MiniTest.expect.equality(result.new_end, 1)
end

T["relocate / content deleted - keeps original lines"] = function()
  local file_lines = {
    "completely",
    "different",
    "content",
  }
  local index = relocator._build_line_index(file_lines)

  local fingerprint = {
    marker_id = "test-1",
    marked_content = { "original marked line" },
    context_before = { "original before" },
    context_after = { "original after" },
    original_start = 5,
    original_end = 5,
  }

  local result = relocator._relocate_single(fingerprint, file_lines, index)
  MiniTest.expect.equality(result.status, "unchanged")
  MiniTest.expect.equality(result.new_start, 5)
  MiniTest.expect.equality(result.new_end, 5)
end

T["relocate / empty line marker with context - uses context to find"] = function()
  local file_lines = {
    "new stuff",
    "if condition then",
    "",
    "  do_something()",
    "end",
  }
  local index = relocator._build_line_index(file_lines)

  local fingerprint = {
    marker_id = "test-1",
    marked_content = { "" },
    context_before = { "if condition then" },
    context_after = { "  do_something()" },
    original_start = 2,
    original_end = 2,
  }

  local result = relocator._relocate_single(fingerprint, file_lines, index)
  MiniTest.expect.equality(result.status, "exact")
  MiniTest.expect.equality(result.new_start, 3)
  MiniTest.expect.equality(result.new_end, 3)
end

T["relocate / context matches when content changed - context_only"] = function()
  local file_lines = {
    "context before",
    "completely new content",
    "replacing the original",
    "context after",
  }
  local index = relocator._build_line_index(file_lines)

  local fingerprint = {
    marker_id = "test-1",
    marked_content = { "function start()", "  original middle", "end" },
    context_before = { "context before" },
    context_after = { "context after" },
    original_start = 2,
    original_end = 4,
  }

  local result = relocator._relocate_single(fingerprint, file_lines, index)
  MiniTest.expect.equality(result.status, "context_only")
  MiniTest.expect.equality(result.new_start, 2)
  MiniTest.expect.equality(result.new_end, 3)
end

T["relocate / only context matches - context_only finds gap"] = function()
  local file_lines = {
    "context before",
    "completely new content",
    "context after",
  }
  local index = relocator._build_line_index(file_lines)

  local fingerprint = {
    marker_id = "test-1",
    marked_content = { "old content that was replaced" },
    context_before = { "context before" },
    context_after = { "context after" },
    original_start = 2,
    original_end = 2,
  }

  local result = relocator._relocate_single(fingerprint, file_lines, index)
  MiniTest.expect.equality(result.status, "context_only")
  MiniTest.expect.equality(result.new_start, 2)
  MiniTest.expect.equality(result.new_end, 2)
end

T["relocate / content matches with different context - content_only"] = function()
  local file_lines = {
    "outer before removed",
    "inner before",
    "marked content",
    "inner after",
    "outer after removed",
  }
  local index = relocator._build_line_index(file_lines)

  local fingerprint = {
    marker_id = "test-1",
    marked_content = { "marked content" },
    context_before = { "outer before", "inner before" },
    context_after = { "inner after", "outer after" },
    original_start = 3,
    original_end = 3,
  }

  local result = relocator._relocate_single(fingerprint, file_lines, index)
  MiniTest.expect.equality(result.status, "content_only")
  MiniTest.expect.equality(result.new_start, 3)
  MiniTest.expect.equality(result.new_end, 3)
end

T["relocate / no context stored - returns unchanged"] = function()
  local file_lines = { "a", "b", "c" }
  local index = relocator._build_line_index(file_lines)

  local fingerprint = {
    marker_id = "test-1",
    marked_content = {},
    context_before = {},
    context_after = {},
    original_start = 2,
    original_end = 2,
  }

  local result = relocator._relocate_single(fingerprint, file_lines, index)
  MiniTest.expect.equality(result.status, "unchanged")
  MiniTest.expect.equality(result.new_start, 2)
  MiniTest.expect.equality(result.new_end, 2)
end

T["relocate / multi-line marker shifted"] = function()
  local file_lines = {
    "new header",
    "context before 1",
    "context before 2",
    "function foo()",
    "  line 1",
    "  line 2",
    "  line 3",
    "end",
    "context after 1",
    "context after 2",
  }
  local index = relocator._build_line_index(file_lines)

  local fingerprint = {
    marker_id = "test-1",
    marked_content = { "function foo()", "  line 1", "  line 2", "  line 3", "end" },
    context_before = { "context before 1", "context before 2" },
    context_after = { "context after 1", "context after 2" },
    original_start = 3,
    original_end = 7,
  }

  local result = relocator._relocate_single(fingerprint, file_lines, index)
  MiniTest.expect.equality(result.status, "exact")
  MiniTest.expect.equality(result.new_start, 4)
  MiniTest.expect.equality(result.new_end, 8)
end

T["relocate_markers_for_file / handles markers without context"] = function()
  local temp_file = vim.fn.tempname() .. ".lua"
  local file = io.open(temp_file, "w")
  file:write("line 1\nline 2\nline 3\n")
  file:close()

  local markers = {
    {
      id = "no-context",
      buffer_path = temp_file,
      start_line = 2,
      end_line = 2,
    },
  }

  local results = relocator.relocate_markers_for_file(temp_file, markers)
  MiniTest.expect.equality(#results, 1)
  MiniTest.expect.equality(results[1].status, "unchanged")
  MiniTest.expect.equality(results[1].new_start, 2)

  os.remove(temp_file)
end

T["relocate_markers_for_file / handles non-existent file"] = function()
  local markers = {
    make_marker("test-1", 2, 2, { "content" }, { "before" }, { "after" }),
  }

  local results = relocator.relocate_markers_for_file("/nonexistent/path.lua", markers)
  MiniTest.expect.equality(#results, 1)
  MiniTest.expect.equality(results[1].status, "unchanged")
end

T["relocate_all_markers / groups by file and relocates"] = function()
  local temp_file1 = vim.fn.tempname() .. ".lua"
  local temp_file2 = vim.fn.tempname() .. ".lua"

  local file1 = io.open(temp_file1, "w")
  file1:write("before\nmarked\nafter\n")
  file1:close()

  local file2 = io.open(temp_file2, "w")
  file2:write("x\ny\nz\n")
  file2:close()

  local markers = {
    {
      id = "m1",
      buffer_path = temp_file1,
      start_line = 2,
      end_line = 2,
      marked_content = { "marked" },
      context_before = { "before" },
      context_after = { "after" },
    },
    {
      id = "m2",
      buffer_path = temp_file2,
      start_line = 2,
      end_line = 2,
      marked_content = { "y" },
      context_before = { "x" },
      context_after = { "z" },
    },
  }

  local results = relocator.relocate_all_markers(markers)
  MiniTest.expect.equality(#results, 2)

  local found_m1, found_m2 = false, false
  for _, r in ipairs(results) do
    if r.marker_id == "m1" then
      found_m1 = true
      MiniTest.expect.equality(r.status, "exact")
    end
    if r.marker_id == "m2" then
      found_m2 = true
      MiniTest.expect.equality(r.status, "exact")
    end
  end
  MiniTest.expect.equality(found_m1, true)
  MiniTest.expect.equality(found_m2, true)

  os.remove(temp_file1)
  os.remove(temp_file2)
end

T["edge case / single line file"] = function()
  local file_lines = { "only line" }
  local index = relocator._build_line_index(file_lines)

  local fingerprint = {
    marker_id = "test-1",
    marked_content = { "only line" },
    context_before = {},
    context_after = {},
    original_start = 1,
    original_end = 1,
  }

  local result = relocator._relocate_single(fingerprint, file_lines, index)
  MiniTest.expect.equality(result.status, "exact")
  MiniTest.expect.equality(result.new_start, 1)
end

T["edge case / content at end of file with no after context"] = function()
  local file_lines = {
    "some",
    "content",
    "before",
    "marked line",
  }
  local index = relocator._build_line_index(file_lines)

  local fingerprint = {
    marker_id = "test-1",
    marked_content = { "marked line" },
    context_before = { "before" },
    context_after = {},
    original_start = 4,
    original_end = 4,
  }

  local result = relocator._relocate_single(fingerprint, file_lines, index)
  MiniTest.expect.equality(result.status, "exact")
  MiniTest.expect.equality(result.new_start, 4)
end

T["edge case / content at start of file with no before context"] = function()
  local file_lines = {
    "marked line",
    "after",
    "more",
    "content",
  }
  local index = relocator._build_line_index(file_lines)

  local fingerprint = {
    marker_id = "test-1",
    marked_content = { "marked line" },
    context_before = {},
    context_after = { "after" },
    original_start = 1,
    original_end = 1,
  }

  local result = relocator._relocate_single(fingerprint, file_lines, index)
  MiniTest.expect.equality(result.status, "exact")
  MiniTest.expect.equality(result.new_start, 1)
end

T["edge case / content matches despite outer context removed"] = function()
  local file_lines = {
    "ctx1",
    "ctx2",
    "marked",
    "ctx3",
    "ctx4",
  }
  local index = relocator._build_line_index(file_lines)

  local fingerprint = {
    marker_id = "test-1",
    marked_content = { "marked" },
    context_before = { "removed1", "removed2", "ctx1", "ctx2" },
    context_after = { "ctx3", "ctx4", "removed3", "removed4" },
    original_start = 3,
    original_end = 3,
  }

  local result = relocator._relocate_single(fingerprint, file_lines, index)
  MiniTest.expect.equality(result.status, "content_only")
  MiniTest.expect.equality(result.new_start, 3)
end

return T
