--- l: https://github.com/ellisonleao/nvim-plugin-template/blob/main/lua/plugin_name.lua

---@class serai.Config
---@field name "Umar"|"Bearcu" Your name
---@field keys table<string, "Enter"|"Inspect"|"Quit"> Your name
local config = {
	name = "Umar",
    keys = {
        ["<Leader>se"] = "Enter",
        ["<Leader>si"] = "Inspect",
        ["<Leader>sq"] = "Quit",
    }
}
local vll = vim.log.levels

---@class Serai
local M = {}

---@type serai.Config
M.config = config

---@type boolean
M.is_running = false

--- @summary
---
---
--- id=setup
---@param args serai.Config?
M.setup = function(args)
	M.config = vim.tbl_deep_extend("force", M.config, args or {})

    for _, v in ipairs({"Enter", "Inspect", "Quit"}) do
        vim.api.nvim_create_user_command("Serai"..v, function() M[v:lower()]() end, {desc = "serai.nvim: "..v})
    end
    for k, v in pairs(M.config.keys) do
        vim.keymap.set("n", k, "<Cmd>Serai"..v.."<CR>", { desc = "serai.nvim: "..v, noremap = true, silent = true })
    end
end

---
M.enter = function()
	vim.notify("Entering Serai mode...", vll.INFO)
	M.is_running = true
end

M.inspect = function()
	if not M.is_running then
		vim.notify("Serai is not running!", vll.WARN)
		return
	end
	vim.notify("Inspect with " .. M.config.name, vll.INFO)
end

M.quit = function()
	if not M.is_running then
		vim.notify("Serai is not running!", vll.WARN)
		return
	end
	vim.notify("Quitting Serai mode...", vll.INFO)
	M.is_running = false
end

return M
