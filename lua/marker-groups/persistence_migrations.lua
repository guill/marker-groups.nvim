local M = {}

local migrations = {}

local function compare_versions(a, b)
  local function split(v)
    local x, y, z = v:match "^(%d+)%.(%d+)%.(%d+)$"
    return tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0
  end
  local ax, ay, az = split(a)
  local bx, by, bz = split(b)
  if ax ~= bx then
    return ax < bx
  end
  if ay ~= by then
    return ay < by
  end
  return az < bz
end

migrations["1.1.0"] = function(data)
  return { success = true, data = data }
end

function M.migrate(data, from_version, to_version)
  if not compare_versions(from_version, to_version) then
    return { success = true, data = data }
  end

  local ordered_versions = { "1.1.0" }
  local current_data = data

  for _, version in ipairs(ordered_versions) do
    if compare_versions(from_version, version) and not compare_versions(to_version, version) then
      local migration_fn = migrations[version]
      if migration_fn then
        local result = migration_fn(current_data)
        if not result.success then
          return result
        end
        current_data = result.data
      end
    end
  end

  return { success = true, data = current_data }
end

return M
