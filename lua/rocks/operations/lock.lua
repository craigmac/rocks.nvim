---@mod rocks.operations.lock
--
-- Copyright (C) 2024 Neorocks Org.
--
-- License:    GPLv3
-- Created:    04 Apr 2024
-- Updated:    04 Apr 2024
-- Homepage:   https://github.com/nvim-neorocks/rocks.nvim
-- Maintainers: NTBBloodbath <bloodbathalchemist@protonmail.com>, Vhyrro <vhyrro@gmail.com>, mrcjkb <marc@jakobi.dev>
--
---@brief [[
--
-- Lockfile management.
--
---@brief ]]

local config = require("rocks.config.internal")
local fs = require("rocks.fs")

local lock = {}

---@param reset boolean
local function parse_rocks_lock(reset)
    local lockfile = reset and "" or fs.read_or_create(config.lockfile_path, "")
    return require("toml_edit").parse(lockfile)
end

---@param rock_name? rock_name
function lock.update_lockfile(rock_name)
    local luarocks_lockfiles = vim.iter(vim.api.nvim_get_runtime_file("luarocks.lock", true))
        :filter(function(path)
            return not rock_name or path:find(rock_name .. "/[^%/]+/luarocks.lock$") ~= nil
        end)
        :totable()
    local reset = rock_name == nil
    local rocks_lock = parse_rocks_lock(reset)
    for _, luarocks_lockfile in ipairs(luarocks_lockfiles) do
        local rock_key = rock_name or luarocks_lockfile:match("/([^%/]+)/[^%/]+/luarocks.lock$")
        if rock_key then
            local ok, loader = pcall(loadfile, luarocks_lockfile)
            if not ok or not loader then
                return
            end
            local success, luarocks_lock_tbl = pcall(loader)
            if not success or not luarocks_lock_tbl or not luarocks_lock_tbl.dependencies then
                return
            end
            rocks_lock[rock_key] = {}
            local has_deps = false
            for dep, version in pairs(luarocks_lock_tbl.dependencies) do
                local is_semver = pcall(vim.version.parse, version:match("([^-]+)") or version)
                if is_semver and dep ~= "lua" then
                    rocks_lock[rock_key][dep] = version
                    has_deps = true
                end
            end
            if not has_deps then
                rocks_lock[rock_key] = nil
            end
        end
    end
    fs.write_file(config.lockfile_path, "w", tostring(rocks_lock))
end

---@param rock_name rock_name
---@return string | nil luarocks_lock
function lock.create_luarocks_lock(rock_name)
    local lockfile = require("toml_edit").parse_as_tbl(fs.read_or_create(config.lockfile_path, ""))
    local dependencies = lockfile[rock_name]
    if not dependencies then
        return
    end
    local temp_dir = vim.fs.dirname(vim.fn.tempname())
    vim.fn.mkdir(temp_dir, "p")
    local luarocks_lock = vim.fs.joinpath(temp_dir, "luarocks.lock")
    local content = ([[
return {
    dependencies = %s,
}
]]):format(vim.inspect(dependencies))
    -- NOTE: Because luarocks is going to use the lockfile immediately,
    -- we have to write it synchronously
    local fh = io.open(luarocks_lock, "w")
    if fh then
        fh:write(content)
        fh:close()
        return luarocks_lock
    end
end

return lock
