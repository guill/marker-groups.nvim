local MiniTest = require "mini.test"

local T = MiniTest.new_set()

local function with_child(fn)
  local child = MiniTest.new_child_neovim()
  child.restart { "--headless", "-u", "scripts/minimal_init.lua" }
  local ok, err = pcall(fn, child)
  child.stop()
  if not ok then
    error(err)
  end
end

local function write_file(path, lines)
  local file = io.open(path, "w")
  if not file then
    error("Failed to open file for writing: " .. path)
  end
  file:write(table.concat(lines, "\n"))
  file:close()
end

--
-- Scenario 1: File modified when NOT loaded in NeoVim
-- Given: marker created, saved, buffer closed
-- When: file modified externally
-- Then: marker relocates on persistence load
--

T["relocation / file modified externally (not loaded) - lines inserted before marker"] = function()
  with_child(function(child)
    child.lua [[
      vim.g.__mg_force_persist = true
      local dd = vim.fn.tempname() .. '_mg_reloc1'
      require('marker-groups').setup({ 
        data_dir = dd, 
        log_level = 'error',
        stored_context_lines = 3,
        enable_relocation = true,
      })
      require('marker-groups.state').initialize(require('marker-groups.config').get())
    ]]

    local tmp_path = child.lua [[
      vim.cmd('enew')
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        'line 1',
        'line 2', 
        'line 3',
        'line 4',
        'MARKER TARGET LINE',
        'line 6',
        'line 7',
      })
      local tmp = vim.fn.tempname() .. '.txt'
      vim.cmd('write ' .. tmp)
      vim.g.__mg_test_path = tmp
      
      vim.api.nvim_win_set_cursor(0, {5, 0})
      local m = require('marker-groups.markers')
      m.add_marker('test-marker')
      
      return tmp
    ]]

    local initial_line = child.lua [[
      local m = require('marker-groups.markers')
      local markers = m.get_current_buffer_markers()
      return markers[1] and markers[1].start_line or -1
    ]]
    MiniTest.expect.equality(initial_line, 5)

    child.lua [[
      require('marker-groups.persistence').save()
      vim.cmd('bdelete!')
    ]]

    write_file(tmp_path, {
      "NEW LINE 1",
      "NEW LINE 2",
      "NEW LINE 3",
      "line 1",
      "line 2",
      "line 3",
      "line 4",
      "MARKER TARGET LINE",
      "line 6",
      "line 7",
    })

    child.lua [[
      local state = require('marker-groups.state')
      state.initialize(require('marker-groups.config').get())
      require('marker-groups.persistence').load()
    ]]

    child.lua("vim.cmd('edit ' .. vim.fn.fnameescape('" .. tmp_path .. "'))")

    local new_line = child.lua [[
      local m = require('marker-groups.markers')
      local markers = m.list_markers()
      for _, marker in ipairs(markers) do
        if marker.annotation == 'test-marker' then
          return marker.start_line
        end
      end
      return -1
    ]]

    MiniTest.expect.equality(new_line, 8)
  end)
end

T["relocation / file modified externally (not loaded) - lines deleted before marker"] = function()
  with_child(function(child)
    child.lua [[
      vim.g.__mg_force_persist = true
      local dd = vim.fn.tempname() .. '_mg_reloc2'
      require('marker-groups').setup({ 
        data_dir = dd, 
        log_level = 'error',
        stored_context_lines = 3,
        enable_relocation = true,
      })
      require('marker-groups.state').initialize(require('marker-groups.config').get())
    ]]

    local tmp_path = child.lua [[
      vim.cmd('enew')
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        'line 1',
        'line 2', 
        'line 3',
        'line 4',
        'line 5',
        'MARKER TARGET LINE',
        'line 7',
        'line 8',
      })
      local tmp = vim.fn.tempname() .. '.txt'
      vim.cmd('write ' .. tmp)
      
      vim.api.nvim_win_set_cursor(0, {6, 0})
      local m = require('marker-groups.markers')
      m.add_marker('delete-test')
      
      return tmp
    ]]

    local initial_line = child.lua [[
      local m = require('marker-groups.markers')
      local markers = m.get_current_buffer_markers()
      return markers[1] and markers[1].start_line or -1
    ]]
    MiniTest.expect.equality(initial_line, 6)

    child.lua [[
      require('marker-groups.persistence').save()
      vim.cmd('bdelete!')
    ]]

    write_file(tmp_path, {
      "line 4",
      "line 5",
      "MARKER TARGET LINE",
      "line 7",
      "line 8",
    })

    child.lua [[
      local state = require('marker-groups.state')
      state.initialize(require('marker-groups.config').get())
      require('marker-groups.persistence').load()
    ]]

    child.lua("vim.cmd('edit ' .. vim.fn.fnameescape('" .. tmp_path .. "'))")

    local new_line = child.lua [[
      local m = require('marker-groups.markers')
      local markers = m.list_markers()
      for _, marker in ipairs(markers) do
        if marker.annotation == 'delete-test' then
          return marker.start_line
        end
      end
      return -1
    ]]

    MiniTest.expect.equality(new_line, 3)
  end)
end

T["relocation / file modified externally (not loaded) - multi-line marker"] = function()
  with_child(function(child)
    child.lua [[
      vim.g.__mg_force_persist = true
      local dd = vim.fn.tempname() .. '_mg_reloc3'
      require('marker-groups').setup({ 
        data_dir = dd, 
        log_level = 'error',
        stored_context_lines = 3,
        enable_relocation = true,
      })
      require('marker-groups.state').initialize(require('marker-groups.config').get())
    ]]

    local tmp_path = child.lua [[
      vim.cmd('enew')
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        'line 1',
        'line 2', 
        'MARKER START',
        'MARKER MIDDLE',
        'MARKER END',
        'line 6',
        'line 7',
      })
      local tmp = vim.fn.tempname() .. '.txt'
      vim.cmd('write ' .. tmp)
      
      local m = require('marker-groups.markers')
      m.add_marker_range(3, 5, 'multi-line-test')
      
      return tmp
    ]]

    local initial = child.lua [[
      local m = require('marker-groups.markers')
      local markers = m.get_current_buffer_markers()
      if markers[1] then
        return { markers[1].start_line, markers[1].end_line }
      end
      return { -1, -1 }
    ]]
    MiniTest.expect.equality(initial, { 3, 5 })

    child.lua [[
      require('marker-groups.persistence').save()
      vim.cmd('bdelete!')
    ]]

    write_file(tmp_path, {
      "NEW 1",
      "NEW 2",
      "line 1",
      "line 2",
      "MARKER START",
      "MARKER MIDDLE",
      "MARKER END",
      "line 6",
      "line 7",
    })

    child.lua [[
      local state = require('marker-groups.state')
      state.initialize(require('marker-groups.config').get())
      require('marker-groups.persistence').load()
    ]]

    child.lua("vim.cmd('edit ' .. vim.fn.fnameescape('" .. tmp_path .. "'))")

    local new_range = child.lua [[
      local m = require('marker-groups.markers')
      local markers = m.list_markers()
      for _, marker in ipairs(markers) do
        if marker.annotation == 'multi-line-test' then
          return { marker.start_line, marker.end_line }
        end
      end
      return { -1, -1 }
    ]]

    MiniTest.expect.equality(new_range, { 5, 7 })
  end)
end

--
-- Scenario 2: File modified on disk while NeoVim has it open
-- Given: marker created, saved, buffer still open
-- When: file modified externally, then reloaded
-- Then: marker relocates after reload
--

T["relocation / file modified while buffer open - reload with :edit!"] = function()
  with_child(function(child)
    child.lua [[
      vim.g.__mg_force_persist = true
      local dd = vim.fn.tempname() .. '_mg_reloc4'
      require('marker-groups').setup({ 
        data_dir = dd, 
        log_level = 'error',
        stored_context_lines = 3,
        enable_relocation = true,
      })
      require('marker-groups.state').initialize(require('marker-groups.config').get())
    ]]

    local tmp_path = child.lua [[
      vim.cmd('enew')
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        'alpha',
        'beta', 
        'gamma',
        'TARGET LINE',
        'delta',
        'epsilon',
      })
      local tmp = vim.fn.tempname() .. '.txt'
      vim.cmd('write ' .. tmp)
      vim.g.__mg_test_path = tmp
      
      vim.api.nvim_win_set_cursor(0, {4, 0})
      local m = require('marker-groups.markers')
      m.add_marker('reload-test')
      
      return tmp
    ]]

    local initial_line = child.lua [[
      local m = require('marker-groups.markers')
      local markers = m.get_current_buffer_markers()
      return markers[1] and markers[1].start_line or -1
    ]]
    MiniTest.expect.equality(initial_line, 4)

    child.lua [[require('marker-groups.persistence').save()]]

    write_file(tmp_path, {
      "NEW FIRST LINE",
      "NEW SECOND LINE",
      "alpha",
      "beta",
      "gamma",
      "TARGET LINE",
      "delta",
      "epsilon",
    })

    child.lua [[
      local state = require('marker-groups.state')
      state.initialize(require('marker-groups.config').get())
      require('marker-groups.persistence').load()
      
      vim.cmd('edit!')
      
      local m = require('marker-groups.markers')
      m.refresh_extmarks(0)
    ]]

    local new_line = child.lua [[
      local m = require('marker-groups.markers')
      local markers = m.list_markers()
      for _, marker in ipairs(markers) do
        if marker.annotation == 'reload-test' then
          return marker.start_line
        end
      end
      return -1
    ]]

    MiniTest.expect.equality(new_line, 6)
  end)
end

T["relocation / file modified while buffer open - checktime trigger"] = function()
  with_child(function(child)
    child.lua [[
      vim.g.__mg_force_persist = true
      vim.o.autoread = true
      local dd = vim.fn.tempname() .. '_mg_reloc5'
      require('marker-groups').setup({ 
        data_dir = dd, 
        log_level = 'error',
        stored_context_lines = 3,
        enable_relocation = true,
      })
      require('marker-groups.state').initialize(require('marker-groups.config').get())
    ]]

    local tmp_path = child.lua [[
      vim.cmd('enew')
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        'first',
        'second', 
        'third',
        'IMPORTANT LINE',
        'fourth',
        'fifth',
      })
      local tmp = vim.fn.tempname() .. '.txt'
      vim.cmd('write ' .. tmp)
      
      vim.api.nvim_win_set_cursor(0, {4, 0})
      local m = require('marker-groups.markers')
      m.add_marker('checktime-test')
      
      return tmp
    ]]

    child.lua [[require('marker-groups.persistence').save()]]

    write_file(tmp_path, {
      "INSERTED 1",
      "INSERTED 2",
      "INSERTED 3",
      "INSERTED 4",
      "first",
      "second",
      "third",
      "IMPORTANT LINE",
      "fourth",
      "fifth",
    })

    child.lua [[
      local state = require('marker-groups.state')
      state.initialize(require('marker-groups.config').get())
      require('marker-groups.persistence').load()
      
      vim.cmd('checktime')
      vim.wait(100)
      
      local m = require('marker-groups.markers')
      m.refresh_extmarks(0)
    ]]

    local new_line = child.lua [[
      local m = require('marker-groups.markers')
      local markers = m.list_markers()
      for _, marker in ipairs(markers) do
        if marker.annotation == 'checktime-test' then
          return marker.start_line
        end
      end
      return -1
    ]]

    MiniTest.expect.equality(new_line, 8)
  end)
end

--
-- Edge cases
--

T["relocation / marker content changed - falls back gracefully"] = function()
  with_child(function(child)
    child.lua [[
      vim.g.__mg_force_persist = true
      local dd = vim.fn.tempname() .. '_mg_reloc6'
      require('marker-groups').setup({ 
        data_dir = dd, 
        log_level = 'error',
        stored_context_lines = 3,
        enable_relocation = true,
      })
      require('marker-groups.state').initialize(require('marker-groups.config').get())
    ]]

    local tmp_path = child.lua [[
      vim.cmd('enew')
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        'context before 1',
        'context before 2',
        'context before 3',
        'ORIGINAL MARKER CONTENT',
        'context after 1',
        'context after 2',
        'context after 3',
      })
      local tmp = vim.fn.tempname() .. '.txt'
      vim.cmd('write ' .. tmp)
      
      vim.api.nvim_win_set_cursor(0, {4, 0})
      local m = require('marker-groups.markers')
      m.add_marker('content-changed-test')
      
      return tmp
    ]]

    child.lua [[
      require('marker-groups.persistence').save()
      vim.cmd('bdelete!')
    ]]

    write_file(tmp_path, {
      "new line 1",
      "new line 2",
      "context before 1",
      "context before 2",
      "context before 3",
      "COMPLETELY DIFFERENT CONTENT",
      "context after 1",
      "context after 2",
      "context after 3",
    })

    child.lua [[
      local state = require('marker-groups.state')
      state.initialize(require('marker-groups.config').get())
      require('marker-groups.persistence').load()
    ]]

    child.lua("vim.cmd('edit ' .. vim.fn.fnameescape('" .. tmp_path .. "'))")

    local new_line = child.lua [[
      local m = require('marker-groups.markers')
      local markers = m.list_markers()
      for _, marker in ipairs(markers) do
        if marker.annotation == 'content-changed-test' then
          return marker.start_line
        end
      end
      return -1
    ]]

    MiniTest.expect.equality(new_line, 6)
  end)
end

T["relocation / disabled via config - markers stay at original positions"] = function()
  with_child(function(child)
    child.lua [[
      vim.g.__mg_force_persist = true
      local dd = vim.fn.tempname() .. '_mg_reloc7'
      require('marker-groups').setup({ 
        data_dir = dd, 
        log_level = 'error',
        stored_context_lines = 3,
        enable_relocation = false,
      })
      require('marker-groups.state').initialize(require('marker-groups.config').get())
    ]]

    local tmp_path = child.lua [[
      vim.cmd('enew')
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        'line 1',
        'line 2',
        'MARKER LINE',
        'line 4',
      })
      local tmp = vim.fn.tempname() .. '.txt'
      vim.cmd('write ' .. tmp)
      
      vim.api.nvim_win_set_cursor(0, {3, 0})
      local m = require('marker-groups.markers')
      m.add_marker('no-reloc-test')
      
      return tmp
    ]]

    child.lua [[
      require('marker-groups.persistence').save()
      vim.cmd('bdelete!')
    ]]

    write_file(tmp_path, {
      "NEW 1",
      "NEW 2",
      "line 1",
      "line 2",
      "MARKER LINE",
      "line 4",
    })

    child.lua [[
      local state = require('marker-groups.state')
      state.initialize(require('marker-groups.config').get())
      require('marker-groups.persistence').load()
    ]]

    child.lua("vim.cmd('edit ' .. vim.fn.fnameescape('" .. tmp_path .. "'))")

    local line = child.lua [[
      local m = require('marker-groups.markers')
      local markers = m.list_markers()
      for _, marker in ipairs(markers) do
        if marker.annotation == 'no-reloc-test' then
          return marker.start_line
        end
      end
      return -1
    ]]

    MiniTest.expect.equality(line, 3)
  end)
end

T["relocation / multiple markers in same file - all relocate correctly"] = function()
  with_child(function(child)
    child.lua [[
      vim.g.__mg_force_persist = true
      local dd = vim.fn.tempname() .. '_mg_reloc8'
      require('marker-groups').setup({ 
        data_dir = dd, 
        log_level = 'error',
        stored_context_lines = 3,
        enable_relocation = true,
      })
      require('marker-groups.state').initialize(require('marker-groups.config').get())
    ]]

    local tmp_path = child.lua [[
      vim.cmd('enew')
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        'line 1',
        'MARKER A',
        'line 3',
        'line 4',
        'MARKER B',
        'line 6',
        'line 7',
        'MARKER C',
        'line 9',
      })
      local tmp = vim.fn.tempname() .. '.txt'
      vim.cmd('write ' .. tmp)
      
      local m = require('marker-groups.markers')
      vim.api.nvim_win_set_cursor(0, {2, 0})
      m.add_marker('marker-a')
      vim.api.nvim_win_set_cursor(0, {5, 0})
      m.add_marker('marker-b')
      vim.api.nvim_win_set_cursor(0, {8, 0})
      m.add_marker('marker-c')
      
      return tmp
    ]]

    child.lua [[
      require('marker-groups.persistence').save()
      vim.cmd('bdelete!')
    ]]

    write_file(tmp_path, {
      "INSERTED 1",
      "INSERTED 2",
      "line 1",
      "MARKER A",
      "line 3",
      "line 4",
      "MARKER B",
      "line 6",
      "line 7",
      "MARKER C",
      "line 9",
    })

    child.lua [[
      local state = require('marker-groups.state')
      state.initialize(require('marker-groups.config').get())
      require('marker-groups.persistence').load()
    ]]

    child.lua("vim.cmd('edit ' .. vim.fn.fnameescape('" .. tmp_path .. "'))")

    local positions = child.lua [[
      local m = require('marker-groups.markers')
      local markers = m.list_markers()
      local result = {}
      for _, marker in ipairs(markers) do
        result[marker.annotation] = marker.start_line
      end
      return result
    ]]

    MiniTest.expect.equality(positions["marker-a"], 4)
    MiniTest.expect.equality(positions["marker-b"], 7)
    MiniTest.expect.equality(positions["marker-c"], 10)
  end)
end

return T
