---@mod rocks.operations.helpers
--
-- Copyright (C) 2023 Neorocks Org.
--
-- Version:    0.1.0
-- License:    GPLv3
-- Created:    07 Mar 2024
-- Updated:    07 Mar 2024
-- Homepage:   https://github.com/nvim-neorocks/rocks.nvim
-- Maintainers: NTBBloodbath <bloodbathalchemist@protonmail.com>, Vhyrro <vhyrro@gmail.com>, mrcjkb <marc@jakobi.dev>
--
---@brief [[
--
-- This module has helpers (used by the rocks.operations modules), which interact with
-- luarocks. Installing, uninstalling, updating, etc.
--
---@brief ]]

local luarocks = require("rocks.luarocks")
local lock = require("rocks.operations.lock")
local constants = require("rocks.constants")
local config = require("rocks.config.internal")
local runtime = require("rocks.runtime")
local adapter = require("rocks.adapter")
local state = require("rocks.state")
local log = require("rocks.log")
local cache = require("rocks.cache")
local nio = require("nio")

local helpers = {}

---@class InstallOpts
---@field use_lockfile boolean

---@param rock_spec RockSpec
---@param opts? InstallOpts
---@return nio.control.Future
helpers.install = function(rock_spec, opts)
    cache.invalidate_removable_rocks()
    local name = rock_spec.name:lower()
    local version = rock_spec.version
    local message = version and ("Installing: %s -> %s"):format(name, version) or ("Installing: %s"):format(name)
    log.info(message)
    -- TODO(vhyrro): Input checking on name and version
    local future = nio.control.future()
    local install_cmd = {
        "install",
        name,
    }
    local servers = {}
    vim.list_extend(servers, constants.ROCKS_SERVERS)
    if version then
        -- If specified version is dev then install the `scm-1` version of the rock
        if version == "dev" or version == "scm" then
            if cache.search_binary_dev_rocks(rock_spec.name, version) then
                -- Rock found on rocks-binaries-dev
                table.insert(servers, constants.ROCKS_BINARIES_DEV)
            else
                -- Search dev manifest
                table.insert(install_cmd, 2, "--dev")
            end
        else
            table.insert(install_cmd, version)
        end
    end
    local install_opts = {
        servers = servers,
    }
    if opts and opts.use_lockfile then
        -- luarocks locks dependencies when there is a lockfile in the cwd
        local lockfile = lock.create_luarocks_lock(rock_spec.name)
        if lockfile and vim.uv.fs_stat(lockfile) then
            install_opts.cwd = vim.fs.dirname(lockfile)
        end
    end
    -- We always want to insert --pin so that the luarocks.lock is created in the
    -- install directory on the rtp
    table.insert(install_cmd, "--pin")
    luarocks.cli(install_cmd, function(sc)
        ---@cast sc vim.SystemCompleted
        if sc.code ~= 0 then
            message = ("Failed to install %s"):format(name)
            log.error(message)
            future.set_error(sc.stderr)
        else
            ---@type Rock
            local installed_rock = {
                name = name,
                -- The `gsub` makes sure to escape all punctuation characters
                -- so they do not get misinterpreted by the lua pattern engine.
                -- We also exclude `-<specrev>` from the version match.
                version = sc.stdout:match(name:gsub("%p", "%%%1") .. "%s+([^-%s]+)"),
            }
            message = ("Installed: %s -> %s"):format(installed_rock.name, installed_rock.version)
            log.info(message)

            if config.dynamic_rtp and not rock_spec.opt then
                runtime.packadd(name)
                adapter.init_tree_sitter_parser_symlink()
            else
                -- Add rock to the rtp, but don't source any scripts
                runtime.packadd(name, { bang = true })
            end

            future.set(installed_rock)
        end
    end, install_opts)
    return future
end

---Removes a rock
---@param name string
---@param progress_handle? ProgressHandle
---@return nio.control.Future
helpers.remove = function(name, progress_handle)
    cache.invalidate_removable_rocks()
    local message = ("Uninstalling: %s"):format(name)
    log.info(message)
    if progress_handle then
        progress_handle:report({ message = message })
    end
    local future = nio.control.future()
    luarocks.cli({
        "remove",
        name,
    }, function(sc)
        ---@cast sc vim.SystemCompleted
        if sc.code ~= 0 then
            message = ("Failed to remove %s."):format(name)
            if progress_handle then
                progress_handle:report({ message = message })
            end
            future.set_error(sc.stderr)
        else
            log.info(("Uninstalled: %s"):format(name))
            future.set(sc)
        end
        adapter.validate_tree_sitter_parser_symlink()
    end)
    return future
end

---Removes a rock, and recursively removes its dependencies
---if they are no longer needed.
---@type async fun(name: string, keep: string[], progress_handle?: ProgressHandle): boolean
helpers.remove_recursive = nio.create(function(name, keep, progress_handle)
    ---@cast name string
    local dependencies = state.rock_dependencies(name)
    local future = helpers.remove(name, progress_handle)
    local success, _ = pcall(future.wait)
    if not success then
        return false
    end
    local removable_rocks = state.query_removable_rocks()
    local removable_dependencies = vim.iter(dependencies)
        :filter(function(rock_name)
            return vim.list_contains(removable_rocks, rock_name) and not vim.list_contains(keep, rock_name)
        end)
        :totable()
    for _, dep in pairs(removable_dependencies) do
        if vim.list_contains(removable_rocks, dep.name) then
            success = success and helpers.remove_recursive(dep.name, keep, progress_handle)
        end
    end
    return success
end, 3)

return helpers
