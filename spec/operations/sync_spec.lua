local tempdir = vim.fs.dirname(vim.fn.tempname())
vim.system({ "rm", "-r", tempdir }):wait()
vim.system({ "mkdir", "-p", tempdir }):wait()
vim.g.rocks_nvim = {
    rocks_path = tempdir,
    config_path = vim.fs.joinpath(tempdir, "rocks.toml"),
    lockfile_path = vim.fs.joinpath(tempdir, "rocks.lock"),
}
local nio = require("nio")
local operations = require("rocks.operations")
local helpers = require("rocks.operations.helpers")
local state = require("rocks.state")
local config = require("rocks.config.internal")
vim.env.PLENARY_TEST_TIMEOUT = 60000 * 5
describe("operations", function()
    vim.system({ "mkdir", "-p", config.rocks_path }):wait()
    local config_content = [[
[rocks]
nlua = "0.1.0"

[plugins]
"haskell-tools.nvim" = "2.4.0"
"sweetie.nvim" = "2.4.0"
]]
    local fh = assert(io.open(config.config_path, "w"), "Could not open rocks.toml for writing")
    fh:write(config_content)
    fh:close()
    nio.tests.it("sync", function()
        -- One package with a dependency to remove
        helpers.install({ name = "telescope.nvim", version = "0.1.6" }).wait() -- remove
        -- One to update
        helpers.install({ name = "sweetie.nvim", version = "1.2.1" }).wait() -- update
        -- One to downgrade
        helpers.install({ name = "haskell-tools.nvim", version = "3.0.0" }).wait()
        -- and nlua to install
        local installed_rocks = state.installed_rocks()
        assert.is_not_nil(installed_rocks["telescope.nvim"])
        assert.is_not_nil(installed_rocks["plenary.nvim"])
        assert.is_nil(installed_rocks.nlua)
        assert.same({
            name = "sweetie.nvim",
            version = "1.2.1",
        }, installed_rocks["sweetie.nvim"])
        assert.same({
            name = "haskell-tools.nvim",
            version = "3.0.0",
        }, installed_rocks["haskell-tools.nvim"])
        local future = nio.control.future()
        operations.sync(config.get_user_rocks(), function()
            future.set(true)
        end)
        future.wait()
        installed_rocks = state.installed_rocks()
        assert.is_nil(installed_rocks["telescope.nvim"])
        -- FIXME: #77
        -- assert.False(vim.tbl_contains(installed_rock_names, "plenary.nvim"))
        assert.same({
            name = "sweetie.nvim",
            version = "2.4.0",
        }, installed_rocks["sweetie.nvim"])
        assert.same({
            name = "haskell-tools.nvim",
            version = "2.4.0",
        }, installed_rocks["haskell-tools.nvim"])
        assert.same({
            name = "nlua",
            version = "0.1.0",
        }, installed_rocks.nlua)
    end)
end)
