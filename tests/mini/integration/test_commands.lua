local MiniTest = require "mini.test"

local T = MiniTest.new_set()

local expect_truthy = MiniTest.new_expectation("truthy", function(x)
  return not not x
end, function(x)
  return "Object: " .. vim.inspect(x)
end)

local function with_child(fn)
  local child = MiniTest.new_child_neovim()
  child.restart { "--headless", "-u", "scripts/minimal_init.lua" }
  local ok, err = pcall(fn, child)
  child.stop()
  if not ok then
    error(err)
  end
end

T["group management / MarkerGroupsCreate adds group"] = function()
  with_child(function(child)
    child.lua [[require('marker-groups').setup({ data_dir = vim.fn.tempname() .. '_mg_it_cmd', log_level = 'error' })]]
    child.lua [[require('marker-groups.state').initialize(require('marker-groups.config').get())]]
    child.lua [[require('marker-groups.commands').setup()]]

    child.cmd "MarkerGroupsCreate test-group-cmd"

    local exists = child.lua [[local s=require('marker-groups.state'); return s.get_group('test-group-cmd')~=nil]]
    expect_truthy(exists)
  end)
end

T["marker commands / MarkerAdd adds marker to current buffer"] = function()
  with_child(function(child)
    child.lua [[require('marker-groups').setup({ data_dir = vim.fn.tempname() .. '_mg_it_cmd2', log_level = 'error' })]]
    child.lua [[require('marker-groups.state').initialize(require('marker-groups.config').get())]]
    child.lua [[require('marker-groups.commands').setup()]]

    child.lua [[vim.cmd('enew')]]
    child.lua [[vim.api.nvim_buf_set_lines(0,0,-1,false,{'one','two','three'})]]
    child.lua [[local tmp=vim.fn.tempname(); vim.cmd('write '..tmp)]]
    child.lua [[vim.api.nvim_win_set_cursor(0,{2,0})]]

    child.cmd "MarkerAdd added-via-command"

    local count = child.lua [[local m=require('marker-groups.markers'); return #m.get_current_buffer_markers()]]
    MiniTest.expect.equality(count, 1)

    local ann =
      child.lua [[local m=require('marker-groups.markers'); local list=m.get_current_buffer_markers(); return list[1].annotation]]
    MiniTest.expect.equality(ann, "added-via-command")
  end)
end

T["group management / MarkerGroupsRename truncates long arg names"] = function()
  with_child(function(child)
    child.lua [[require('marker-groups').setup({ data_dir = vim.fn.tempname() .. '_mg_it_cmd3', log_level = 'error' })]]
    child.lua [[require('marker-groups.state').initialize(require('marker-groups.config').get())]]
    child.lua [[require('marker-groups.commands').setup()]]

    child.lua [[require('marker-groups.groups').create_group('truncate-src')]]
    local long = child.lua [[return string.rep('x',150)]]
    child.cmd("MarkerGroupsRename truncate-src " .. long)
    local has_trunc =
      child.lua [[local s=require('marker-groups.state'); local names=s.get_group_names(); local t=string.rep('x',100); return vim.tbl_contains(names,t)]]
    expect_truthy(has_trunc)
  end)
end

T["group management / MarkerGroupsSelect activates group"] = function()
  with_child(function(child)
    child.lua [[require('marker-groups').setup({ data_dir = vim.fn.tempname() .. '_mg_it_cmd4', log_level = 'error' })]]
    child.lua [[require('marker-groups.state').initialize(require('marker-groups.config').get())]]
    child.lua [[require('marker-groups.commands').setup()]]
    child.lua [[require('marker-groups.state').create_group('selectable-group')]]
    child.cmd "MarkerGroupsSelect selectable-group"
    local active = child.lua [[return require('marker-groups.state').get_active_group()]]
    MiniTest.expect.equality(active, "selectable-group")
  end)
end

T["command list / MarkerGroupsList runs without error"] = function()
  with_child(function(child)
    child.lua [[require('marker-groups').setup({ data_dir = vim.fn.tempname() .. '_mg_it_cmd5', log_level = 'error' })]]
    child.lua [[require('marker-groups.state').initialize(require('marker-groups.config').get())]]
    child.lua [[require('marker-groups.commands').setup()]]
    child.cmd "MarkerGroupsList"
  end)
end

T["marker commands / range add via ex-range"] = function()
  with_child(function(child)
    child.lua [[require('marker-groups').setup({ data_dir = vim.fn.tempname() .. '_mg_it_cmd6', log_level = 'error' })]]
    child.lua [[require('marker-groups.state').initialize(require('marker-groups.config').get())]]
    child.lua [[require('marker-groups.commands').setup()]]
    child.lua [[vim.cmd('enew')]]
    child.lua [[vim.api.nvim_buf_set_lines(0,0,-1,false,{'A','B','C','D','E'})]]
    child.lua [[local tmp=vim.fn.tempname(); vim.cmd('write '..tmp)]]
    child.cmd "2,4MarkerAdd range marker"
    local m =
      child.lua [=[local m=require('marker-groups.markers'); local list=m.get_current_buffer_markers(); return list[#list]]=]
    MiniTest.expect.equality(m.annotation, "range marker")
    MiniTest.expect.equality(m.start_line, 2)
    MiniTest.expect.equality(m.end_line, 4)
  end)
end

T["drawer commands / width valid and invalid"] = function()
  with_child(function(child)
    child.lua [[require('marker-groups').setup({ data_dir = vim.fn.tempname() .. '_mg_it_cmd7', log_level = 'error' })]]
    child.lua [[require('marker-groups.state').initialize(require('marker-groups.config').get())]]
    child.lua [[require('marker-groups.commands').setup()]]
    child.cmd "MarkerGroupsDrawerWidth 90"
    local width = child.lua [[return require('marker-groups.ui.drawer').get_drawer_width()]]
    MiniTest.expect.equality(width, 90)
    local ok = child.lua [[return pcall(vim.cmd, 'MarkerGroupsDrawerWidth invalid')]]
    expect_truthy(ok == false)
  end)
end

local function write_file(path, lines)
  local file = io.open(path, "w")
  if not file then
    error("Failed to open file for writing: " .. path)
  end
  file:write(table.concat(lines, "\n"))
  file:close()
end

T["relocation commands / MarkerGroupsRelocate relocates markers in current buffer"] = function()
  with_child(function(child)
    child.lua [[
      require('marker-groups').setup({ 
        data_dir = vim.fn.tempname() .. '_mg_relocate_cmd',
        log_level = 'error',
        stored_context_lines = 3,
        enable_relocation = true,
      })
      require('marker-groups.state').initialize(require('marker-groups.config').get())
      require('marker-groups.commands').setup()
    ]]

    local tmp_path = child.lua [[
      vim.cmd('enew')
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        'line 1',
        'line 2',
        'line 3',
        'MARKER LINE',
        'line 5',
        'line 6',
      })
      local tmp = vim.fn.tempname() .. '.txt'
      vim.cmd('write ' .. tmp)
      
      vim.api.nvim_win_set_cursor(0, {4, 0})
      require('marker-groups.markers').add_marker('relocate-cmd-test')
      return tmp
    ]]

    local initial_line = child.lua [[
      local m = require('marker-groups.markers')
      local markers = m.get_current_buffer_markers()
      return markers[1] and markers[1].start_line or -1
    ]]
    MiniTest.expect.equality(initial_line, 4)

    write_file(tmp_path, {
      "NEW LINE 1",
      "NEW LINE 2",
      "line 1",
      "line 2",
      "line 3",
      "MARKER LINE",
      "line 5",
      "line 6",
    })

    child.cmd "edit!"
    child.cmd "MarkerGroupsRelocate"

    local new_line = child.lua [[
      local state = require('marker-groups.state')
      local group = state.get_group('default')
      if group and group.markers[1] then
        return group.markers[1].start_line
      end
      return -1
    ]]

    MiniTest.expect.equality(new_line, 6)
  end)
end

return T
