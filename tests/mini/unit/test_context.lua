local MiniTest = require "mini.test"

local T = MiniTest.new_set()

local context = require "marker-groups.context"

T["read_file_lines / reads file from disk"] = function()
  local temp_file = vim.fn.tempname() .. ".lua"
  local file = io.open(temp_file, "w")
  file:write("line 1\nline 2\nline 3\n")
  file:close()

  local lines, err = context.read_file_lines(temp_file)
  MiniTest.expect.equality(err, nil)
  MiniTest.expect.equality(#lines, 3)
  MiniTest.expect.equality(lines[1], "line 1")
  MiniTest.expect.equality(lines[2], "line 2")
  MiniTest.expect.equality(lines[3], "line 3")

  os.remove(temp_file)
end

T["read_file_lines / returns nil for invalid path"] = function()
  local lines, err = context.read_file_lines(nil)
  MiniTest.expect.equality(lines, nil)
  MiniTest.expect.equality(type(err), "string")
end

T["read_file_lines / returns nil for empty path"] = function()
  local lines, err = context.read_file_lines("")
  MiniTest.expect.equality(lines, nil)
end

T["read_file_lines / returns nil for non-existent file"] = function()
  local lines, err = context.read_file_lines("/nonexistent/path/file.lua")
  MiniTest.expect.equality(lines, nil)
end

T["capture / captures marked content and context"] = function()
  local temp_file = vim.fn.tempname() .. ".lua"
  local file = io.open(temp_file, "w")
  file:write("line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\n")
  file:close()

  local ctx = context.capture(temp_file, 4, 4, 2)
  MiniTest.expect.equality(ctx.marked_content, { "line 4" })
  MiniTest.expect.equality(ctx.context_before, { "line 2", "line 3" })
  MiniTest.expect.equality(ctx.context_after, { "line 5", "line 6" })

  os.remove(temp_file)
end

T["capture / handles multi-line markers"] = function()
  local temp_file = vim.fn.tempname() .. ".lua"
  local file = io.open(temp_file, "w")
  file:write("a\nb\nc\nd\ne\nf\ng\n")
  file:close()

  local ctx = context.capture(temp_file, 3, 5, 1)
  MiniTest.expect.equality(ctx.marked_content, { "c", "d", "e" })
  MiniTest.expect.equality(ctx.context_before, { "b" })
  MiniTest.expect.equality(ctx.context_after, { "f" })

  os.remove(temp_file)
end

T["capture / handles marker at start of file"] = function()
  local temp_file = vim.fn.tempname() .. ".lua"
  local file = io.open(temp_file, "w")
  file:write("first\nsecond\nthird\n")
  file:close()

  local ctx = context.capture(temp_file, 1, 1, 2)
  MiniTest.expect.equality(ctx.marked_content, { "first" })
  MiniTest.expect.equality(ctx.context_before, {})
  MiniTest.expect.equality(ctx.context_after, { "second", "third" })

  os.remove(temp_file)
end

T["capture / handles marker at end of file"] = function()
  local temp_file = vim.fn.tempname() .. ".lua"
  local file = io.open(temp_file, "w")
  file:write("first\nsecond\nthird\n")
  file:close()

  local ctx = context.capture(temp_file, 3, 3, 2)
  MiniTest.expect.equality(ctx.marked_content, { "third" })
  MiniTest.expect.equality(ctx.context_before, { "first", "second" })
  MiniTest.expect.equality(ctx.context_after, {})

  os.remove(temp_file)
end

T["capture / returns nil for non-existent file"] = function()
  local ctx = context.capture("/nonexistent/path.lua", 1, 1, 2)
  MiniTest.expect.equality(ctx, nil)
end

T["capture / handles empty file"] = function()
  local temp_file = vim.fn.tempname() .. ".lua"
  local file = io.open(temp_file, "w")
  file:write("")
  file:close()

  local ctx = context.capture(temp_file, 1, 1, 2)
  MiniTest.expect.equality(ctx.marked_content, {})
  MiniTest.expect.equality(ctx.context_before, {})
  MiniTest.expect.equality(ctx.context_after, {})

  os.remove(temp_file)
end

T["capture / clamps line numbers to valid range"] = function()
  local temp_file = vim.fn.tempname() .. ".lua"
  local file = io.open(temp_file, "w")
  file:write("a\nb\nc\n")
  file:close()

  local ctx = context.capture(temp_file, 100, 200, 2)
  MiniTest.expect.equality(ctx.marked_content, { "c" })

  os.remove(temp_file)
end

T["has_context / returns true for marker with content"] = function()
  local marker = {
    marked_content = { "some content" },
    context_before = {},
    context_after = {},
  }
  MiniTest.expect.equality(context.has_context(marker), true)
end

T["has_context / returns false for marker without content"] = function()
  local marker = {
    context_before = { "before" },
    context_after = { "after" },
  }
  MiniTest.expect.equality(context.has_context(marker), false)
end

T["has_context / returns false for empty content array"] = function()
  local marker = {
    marked_content = {},
    context_before = {},
    context_after = {},
  }
  MiniTest.expect.equality(context.has_context(marker), false)
end

T["has_context / returns false for nil marker"] = function()
  MiniTest.expect.equality(context.has_context(nil), false)
end

T["fingerprint / creates readable fingerprint"] = function()
  local ctx = {
    marked_content = { "a", "b" },
    context_before = { "x" },
    context_after = { "y", "z" },
  }
  local fp = context.fingerprint(ctx)
  MiniTest.expect.equality(fp, "before:1, content:2, after:2")
end

T["fingerprint / handles nil context"] = function()
  local fp = context.fingerprint(nil)
  MiniTest.expect.equality(fp, "[no context]")
end

T["fingerprint / handles empty context"] = function()
  local ctx = {
    marked_content = {},
    context_before = {},
    context_after = {},
  }
  local fp = context.fingerprint(ctx)
  MiniTest.expect.equality(fp, "")
end

return T
