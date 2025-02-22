---@mod rocks.health rocks.nvim health checks
--
-- Copyright (C) 2023 Neorocks Org.
--
-- Version:    0.1.0
-- License:    GPLv3
-- Created:    24 Oct 2023
-- Updated:    24 Oct 2023
-- Homepage:   https://github.com/nvim-neorocks/rocks.nvim
-- Maintainers: NTBBloodbath <bloodbathalchemist@protonmail.com>, Vhyrro <vhyrro@gmail.com>, mrcjkb <marc@jakobi.dev>
--
---@brief [[
--
-- rocks.nvim health checks
--
---@brief ]]

local health = {}

---@type RocksConfig
local config = require("rocks.config.internal")

local h = vim.health
local start = h.start
local ok = h.ok
local error = h.error
local warn = h.warn

---@class (exact) LuaDependency
---@field module string The name of a module
---@field optional fun():boolean Function that returns whether the dependency is optional
---@field url string URL (markdown)
---@field info string Additional information

---@class (exact) ExternalDependency
---@field name string Name of the dependency
---@field get_binaries fun():string[]Function that returns the binaries to check for
---@field version_flag? string
---@field parse_version? fun(stdout:string):string
---@field optional fun():boolean Function that returns whether the dependency is optional
---@field url string URL (markdown)
---@field info string Additional information
---@field extra_checks function|nil Optional extra checks to perform if the dependency is installed

---@type ExternalDependency[]
local external_dependencies = {
    {
        name = "luarocks",
        get_binaries = function()
            return { "luarocks" }
        end,
        optional = function()
            return true
        end,
        url = "[luarocks](https://luarocks.org/#quick-start)",
        info = "LuaRocks is the package manager for Lua modules.",
    },
    {
        name = "lua",
        get_binaries = function()
            return { "lua" }
        end,
        version_flag = "-v",
        parse_version = function(stdout)
            return stdout:match("^Lua%s(%d+%.%d+%.%d+)")
        end,
        optional = function()
            return true
        end,
        url = "[Lua](https://www.lua.org/)",
        info = "luarocks requires a Lua installation.",
    },
}

---@param dep ExternalDependency
---@return boolean is_installed
---@return string|nil version
local check_installed = function(dep)
    local binaries = dep.get_binaries()
    for _, binary in ipairs(binaries) do
        if vim.fn.executable(binary) == 1 then
            local systemObj = vim.system({ binary, dep.version_flag or "--version" }):wait()
            local version = binary == "lua" -- (╯°□°)╯︵ ┻━┻
                    and systemObj.stderr
                or systemObj.stdout
            return true, version
        end
    end
    return false
end

---@param dep ExternalDependency
local function check_external_dependency(dep)
    local installed, mb_version = check_installed(dep)
    if installed then
        local mb_version_newline_idx = mb_version and mb_version:find("\n")
        local mb_version_len = mb_version
            and (mb_version_newline_idx and mb_version_newline_idx - 1 or mb_version:len())
        local version = mb_version and mb_version:sub(0, mb_version_len) or "(unknown version)"
        ok(("%s: found %s"):format(dep.name, version))
        if dep.extra_checks then
            dep.extra_checks()
        end
        return
    end
    if dep.optional() then
        warn(([[
        %s: not found.
        Install %s for extended capabilities.
        %s
        ]]):format(dep.name, dep.url, dep.info))
    else
        error(([[
        %s: not found.
        rocks.nvim requires %s.
        %s
        ]]):format(dep.name, dep.url, dep.info))
    end
end

local function check_config()
    start("Checking rocks.nvim config")
    if vim.g.rocks_nvim and not config.debug_info.was_g_rocks_nvim_sourced then
        warn("unrecognized configs in vim.g.rocks_nvim: " .. vim.inspect(config.debug_info.unrecognized_configs))
    end
    local valid, err = require("rocks.config.check").validate(config)
    if valid then
        ok("No errors found in config.")
    else
        error(err or "" .. vim.g.rocks_nvim and "" or " This looks like a plugin bug!")
    end
end

local function check_rocks_toml()
    start("Checking rocks.toml")
    local success, user_rocks_or_err = xpcall(require("rocks.config.internal").get_user_rocks, function(err)
        error(err)
    end)
    if not success then
        return
    end
    for rock_name, _ in pairs(user_rocks_or_err) do
        if rock_name:lower() ~= rock_name then
            error(("Plugin name is not lowercase: %s"):format(rock_name))
        end
        ok("No errors found in rocks.toml.")
    end
end

function health.check()
    start("Checking external dependencies")
    for _, dep in ipairs(external_dependencies) do
        check_external_dependency(dep)
    end
    check_config()
    check_rocks_toml()
end

return health
