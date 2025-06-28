--- @see https://github.com/ellisonleao/nvim-plugin-template/blob/main/lua/plugin_name.lua

function IIF(cond, T, F) -- ternary conditional operator / inline if
	if cond then
		return T
	else
		return F
	end
end

--- @enum (key) serai.Actions
local actions = {
	Enter = "Enter",
	Find = "Find",
	Inspect = "Inspect",
	Reload = "Reload",
	Quit = "Quit",
}

--- @class serai.Config
--- @field name "Umar"|"Bearcu" Your name
--- @field keys table<string, serai.Actions> Your name
local config = {
	name = "Umar",
	keys = {
		["<Leader>se"] = "Enter",
		["<Leader>sf"] = "Find",
		["<Leader>si"] = "Inspect",
		["<Leader>sr"] = "Reload",
		["<Leader>sq"] = "Quit",
	},
}
local vll = vim.log.levels

---@class Serai
local M = {}

---@type serai.Config
M.config = config

---@type boolean
M.is_running = false

---@summary
---
---id=fn-setup
---@param args serai.Config?
M.setup = function(args)
	M.config = vim.tbl_deep_extend("force", M.config, args or {})

	for _, action in pairs(actions) do
		vim.api.nvim_create_user_command("Serai" .. action, function()
			M[action:lower()]()
		end, { desc = "serai.nvim: " .. action })
	end
	for k, v in pairs(M.config.keys) do
		vim.keymap.set(
			"n",
			k,
			"<Cmd>Serai" .. v .. "<CR>",
			{ desc = "serai.nvim: " .. v, noremap = true, silent = true }
		)
	end
end

---id=fn-reload
M.reload = function()
	require("lazy.core.loader").reload("serai.nvim")
end

---id=fn-enter
M.enter = function()
	vim.notify("Entering Serai mode...", vll.INFO)
	M.is_running = true
end

local builtin = require("fzf-lua.previewer.builtin")
-- Inherit from "base" instead of "buffer_or_file"
local MyPreviewer = builtin.buffer_or_file:extend()

function MyPreviewer:new(o, opts, fzf_win)
	MyPreviewer.super.new(self, o, opts, fzf_win)
	setmetatable(self, MyPreviewer)
	return self
end

function MyPreviewer:parse_entry(entry_str)
	local row, path = entry_str:match("^(%d+)%s+%S+%s+(%S+)$")
	return {
		path = path,
		line = tonumber(row),
		col = 1,
	}
end

-- function MyPreviewer:populate_preview_buf(entry_str)
--   local tmpbuf = self:get_tmp_buffer()
--   vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, {
--     string.format("SELECTED FILE: %s", entry_str)
--   })
--   self:set_preview_buf(tmpbuf)
--   self.win:update_preview_scrollbar()
-- end

---id=fn-find
M.find = function(bufname)
	local bufnr = IIF(bufname, M.find_buffer_by_name(bufname), 0)
	if bufnr == -1 then
		bufnr = M.add_file_to_buffer(bufname)
	end
	bufname = bufname or vim.api.nvim_buf_get_name(bufnr)

	local tbl = M.get_comments({ bufnr = bufnr })
	if tbl == nil then
		return
	end
	require("fzf-lua").fzf_exec(function(fzf_cb)
		for _, v in pairs(tbl) do
			fzf_cb(v.row .. " " .. v.text .. " " .. bufname)
		end
		fzf_cb()
	end, {
		fzf_opts = {
			["--with-nth"] = 2,
		},
		-- fn_transform = function(x)
		--           vim.notify(x)
		--               return 'yay'
		-- 	-- return require("fzf-lua").utils.ansi_codes.magenta(x)
		-- end,
		previewer = MyPreviewer,
		actions = {
			Enter = function(selected)
				local row = tonumber(selected[1]:match("^(%d+)%s?"))
				vim.notify(selected)
				vim.api.nvim_win_set_cursor(0, { row, 0 })
				vim.cmd("normal! zz")
			end,
		},
	})
end

---id=fn-inspect
M.inspect = function()
	if not M.is_running then
		vim.notify("Serai is not running!", vll.WARN)
		return
	end
	local res = M.get_comments()
	vim.notify(vim.inspect(res))
end

M.quit = function()
	if not M.is_running then
		vim.notify("Serai is not running!", vll.WARN)
		return
	end
	vim.notify("Quitting Serai mode...", vll.INFO)
	M.is_running = false
end

--- Fetch comments
--- @return nil|{row: number, col: number, text: string}[]
--- @see https://github.com/ibhagwan/fzf-lua/blob/main/lua/fzf-lua/providers/buffers.lua#L492
M.get_comments = function(opts)
	-- Default to current buffer
	opts = vim.tbl_deep_extend("force", { bufnr = 0 }, opts or {})

	local __has_ts, _ = pcall(require, "nvim-treesitter")
	if not __has_ts then
		vim.notify("Treesitter requires 'nvim-treesitter'.", vll.WARN)
		return
	end

	local ts = vim.treesitter
	local ft = vim.bo[opts.bufnr].ft
	local lang = ts.language.get_lang(ft) or ft
	if not M.has_ts_parser(lang) then
		vim.notify(
			string.format("No treesitter parser found for '%s' (bufnr=%d).", opts._bufname, opts.bufnr),
			vll.WARN
		)
		return
	end

	local parser = ts.get_parser(opts.bufnr)
	if not parser then
		return
	end
	parser:parse()
	local root = parser:trees()[1]:root()
	if not root then
		return
	end

	local query = (ts.query.parse(lang, "(comment) @comment"))
	if not query then
		return
	end

	local res = {}
	for _, node in query:iter_captures(root, opts.bufnr) do
		local text = ts.get_node_text(node, opts.bufnr)
		--- @example
		---
		---```lua
		---select(3, string.find("-id=hello", "%W*id[:=](%S+)")) == "hello"
		---```
		local _, _, match = string.find(text, "^%W*id[:=](%S+)")
		if match then
			local row, col = node:range()
			table.insert(res, { row = row + 1, col = col, text = match })
		end
	end

	return res
end

--- @see https://github.com/ibhagwan/fzf-lua/blob/main/lua/fzf-lua/utils.lua#L1384
---id=fn-has_ts_parser
M.has_ts_parser = function(lang)
	if vim.fn.has("nvim-0.11") == 1 then
		return vim.treesitter.language.add(lang)
	else
		return pcall(vim.treesitter.language.add, lang)
	end
end

--- @see https://github.com/nvim-neo-tree/neo-tree.nvim/blob/main/lua/neo-tree/utils/init.lua#L205C1-L213C4
--- @return integer
M.find_buffer_by_name = function(name)
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		local buf_name = vim.api.nvim_buf_get_name(buf)
		if buf_name == name then
			return buf
		end
	end
	return -1
end

--- @return integer
M.add_file_to_buffer = function(name)
	local bufnr = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(bufnr, name)
	vim.api.nvim_buf_call(bufnr, vim.cmd.edit)
	return bufnr
end

return M
