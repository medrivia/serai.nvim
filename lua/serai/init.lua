-- @see https://github.com/ellisonleao/nvim-plugin-template/blob/main/lua/plugin_name.lua

-- id=util-iif
function IIF(cond, T, F) -- ternary conditional operator / inline if
	if cond then
		return T
	else
		return F
	end
end

-- id=actions
--- @enum (key) serai.Actions
local actions = {
	Enter = "Enter",
	Search = "Search",
	FileSearch = "FileSearch",
	DirSearch = "DirSearch",
	BufSearch = "BufSearch",
	Inspect = "Inspect",
	Reload = "Reload",
	Quit = "Quit",
}

--- id=config-default
--- @class serai.Config
--- @field name "Umar"|"Bearcu" Your name
--- @field keys table<string, serai.Actions> Your name
--- @field exclude string[] filetypes
local config = {
	name = "Umar",
	keys = {
		["<Leader>se"] = "Enter",
		["<Leader>ss"] = "Search",
		["<Leader>sf"] = "FileSearch",
		["<Leader>sd"] = "DirSearch",
		["<Leader>sb"] = "BufSearch",
		["<Leader>si"] = "Inspect",
		["<Leader>sr"] = "Reload",
		["<Leader>sq"] = "Quit",
	},
	exclude = {},
}
local vll = vim.log.levels

---@class Serai
local M = {}

---@type serai.Config
M.config = config

M.bufs = {}

---@type boolean
M.is_running = false

---@summary
---
-- id=fn-setup
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
	vim.notify("Reloading Serai plugin...", vll.INFO, { timeout = 1000 })
	require("lazy.core.loader").reload("serai.nvim")
end

---id=fn-is_float
M.is_float = function(win)
	local opts = vim.api.nvim_win_get_config(win)
	return opts and opts.relative and opts.relative ~= ""
end

---id=fn-is_valid_buf
M.is_valid_buf = function(buf)
	-- Skip special buffers
	local buftype = vim.api.nvim_get_option_value("buftype", { buf = buf })
    -- vim.notify(buftype)
	if buftype ~= "" and buftype ~= "quickfix" then
		return false
	end
	local filetype = vim.api.nvim_get_option_value("filetype", { buf = buf })
	if vim.tbl_contains(M.config.exclude, filetype) then
		return false
	end
	return true
end

---id=fn-is_valid_win
M.is_valid_win = function(win)
	if not vim.api.nvim_win_is_valid(win) then
		return false
	end
	-- avoid E5108 after pressing q:
	if vim.fn.getcmdwintype() ~= "" then
		return false
	end
	-- dont do anything for floating windows
	if M.is_float(win) then
		return false
	end
	local buf = vim.api.nvim_win_get_buf(win)
	return M.is_valid_buf(buf)
end

--- @param row integer
--- @param row2 integer
---id=fn-update_highlights
M.update_highlights = function(row, row2)
    local buf = 0
    vim.api.nvim_buf_clear_namespace(buf, M.ns, row, row2)
    for _, sign in pairs(vim.fn.sign_getplaced(buf, { group = "serai-signs" })[1].signs) do
        if sign.lnum - 1 >= row and sign.lnum - 1 < row2 then
            vim.fn.sign_unplace("serai-signs", { buffer = buf, id = sign.id })
        end
    end

    local lines = vim.api.nvim_buf_get_lines(buf, row, row2, false)
    for i, l in ipairs(lines) do
        local start, finish, prefix, match = string.find(l, "^(%W+)id[:=](%S+)")
        if match and M.is_comment(buf, row + i, start + prefix:len()) then
            -- vim.notify(string.format("%d %d %d %d", row + i - 1, start + prefix:len(), row + i - 1, finish))
            vim.hl.range(buf, M.ns, M.hl, { row + i - 1, start + prefix:len() - 1 }, { row + i - 1, finish }, { priority = 10000 })
            vim.fn.sign_place(
                0,
                "serai-signs",
                "serai-sign",
                buf,
                { lnum = row + i, priority = 1000 }
            )
        end
    end

end

---id=fn-add_highlights
M.add_highlights = function(win)
	win = win or vim.api.nvim_get_current_win()
	if not M.is_valid_win(win) then
		return
	end
	local buf = vim.api.nvim_win_get_buf(win)
	if M.bufs[buf] then
		return
	end
	local list = M.get_comments({ bufnr = buf })
	if not list then
		return
	end
	for _, v in pairs(list) do
		-- vim.notify(v.row .. " " .. v.col .. " " .. v.row2 .. " " .. v.col2)
		M.bufs[buf] = true
        -- vim.api.nvim_buf_add_highlight(buf, M.ns, M.hl, v.row - 1, 0, -1)
		vim.hl.range(buf, M.ns, M.hl, { v.row - 1, v.col - 1 }, { v.row2 - 1, v.col2 - 1 }, { priority = 10000 })
		-- vim.api.nvim_buf_set_extmark(buf, M.ns, v.row - 1, 0, { hl_group = M.hl, })
        vim.fn.sign_place(
            0,
            "serai-signs",
            "serai-sign",
            buf,
            { lnum = v.row, priority = 1000 }
        )
	end

	-- vim.api.nvim_buf_set_extmark(buffer, ns, line, from, {
	--   end_line = line,
	--   end_col = to,
	--   hl_group = hl,
	--   priority = 500,
	-- })
	-- vim.api.nvim_buf_add_highlight(buffer, ns, hl, line, from, to)
    local res = vim.api.nvim_buf_get_extmarks(0, M.ns, 0, -1, {})
    -- vim.print(res)
end

M.ns = vim.api.nvim_create_namespace("serai")
M.hl = "SeraiId"

---id=fn-signs
function M.signs()
    vim.fn.sign_define("serai-sign", {
        text = "🪪",
        texthl = "SeraiSign",
    })
end

---id=fn-enter
M.enter = function()
    M.is_running = true
	vim.notify("Entering Serai mode...", vll.INFO, { timeout = 1000 })
	vim.api.nvim_set_hl(M.ns, "SeraiId", { fg = "#000000", bg = "#AACCEE", bold = true })
    M.signs()
    -- vim.cmd("hi def TodoBg" .. kw .. " guibg=" .. hex .. " guifg=" .. fg .. " gui=" .. bg_gui)
    vim.api.nvim_set_hl_ns(M.ns)

	vim.api.nvim_create_augroup("Serai", { clear = false })
	vim.api.nvim_create_autocmd({ "BufWinEnter", "WinNew" }, {
		group = "Serai",
		callback = function()
			M.add_highlights()
		end,
	})
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = "Serai",
		callback = function()
            if not M.is_valid_win(0) then return end
            vim.notify("Updating...", vll.INFO, { timeout = 250 })
            local cur = vim.api.nvim_win_get_cursor(0)
			M.update_highlights(cur[1] - 1, cur[1] )
		end,
	})
	for _, win in pairs(vim.api.nvim_list_wins()) do
		M.add_highlights(win)
	end
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

-- hard to fetch treesitter
-- function MyPreviewer:preview_buf_post(entry_str)
--     MyPreviewer.super.preview_buf_post(self, entry_str)
--     if not self.win then return end
--     -- local buf = self.preview_bufnr
--     M.add_highlights(self.win.preview_winid)
-- end

-- function MyPreviewer:populate_preview_buf(entry_str)
--   local tmpbuf = self:get_tmp_buffer()
--   vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, {
--     string.format("SELECTED FILE: %s", entry_str)
--   })
--   self:set_preview_buf(tmpbuf)
--   self.win:update_preview_scrollbar()
-- end

-- id=fn-search
M.search = function(bufname)
	local bufnr = IIF(bufname, M.find_buffer_by_name(bufname), 0)
	if bufnr == -1 then
		bufnr = M.add_file_to_buffer(bufname)
	end
	bufname = bufname or vim.api.nvim_buf_get_name(bufnr)
	-- vim.notify(bufnr .. bufname)

	local tbl = M.get_comments({ bufnr = bufnr })
    -- vim.notify(vim.inspect(tbl))
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
				local row, id = selected[1]:match("^(%d+)%s+(%S+)")
				vim.notify(id, vll.INFO, { timeout = 1000 })
				vim.api.nvim_set_current_buf(bufnr)
				vim.api.nvim_win_set_cursor(0, { tonumber(row), 0 })
				vim.cmd("normal! zz")
			end,
		},
	})
end

-- id=fn-filesearch
M.filesearch = function(cwd)
	local cwd = cwd or vim.uv.cwd()
	require("fzf-lua").files({
		cwd = cwd,
		actions = {
			Enter = function(selected)
				local file = require("fzf-lua.path").entry_to_file(selected[1])
				local path = cwd .. "/" .. file.stripped
				vim.notify(vim.inspect(path))
				M.search(path)
			end,
		},
	})
end

-- id=fn-bufsearch
M.bufsearch = function(cwd)
	local cwd = cwd or vim.uv.cwd()
	require("fzf-lua").fzf_exec(M.list_buffers(), {
		cwd = cwd,
		actions = {
			Enter = function(selected)
				M.search(selected[1])
			end,
		},
	})
end

-- id=fn-dirsearch
M.dirsearch = function()
	require("fzf-lua").zoxide({
		actions = {
			Enter = function(selected)
				local cwd = selected[1]:match("[^\t]+$") or selected[1]
				M.filesearch(cwd)
			end,
		},
	})
end

-- id=fn-inspect
M.inspect = function()
	if not M.is_running then
		vim.notify("Serai is not running!", vll.WARN, { timeout = 2000 })
		return
	end
	local res = M.get_comments()
	vim.notify(vim.inspect(res))
end

-- id=fn-quit
M.quit = function()
	if not M.is_running then
		vim.notify("Serai is not running!", vll.WARN, { timeout = 2000 })
		return
	end
	vim.notify("Quitting Serai mode...", vll.INFO, { timeout = 1000 })
    for buf, _ in pairs(M.bufs) do
        if vim.api.nvim_buf_is_valid(buf) then
            pcall(vim.api.nvim_buf_clear_namespace, buf, M.ns, 0, -1)
        end
    end
    M.bufs = {}
    vim.fn.sign_unplace("serai-signs")
	M.is_running = false
end

-- id=fn-get_comments
--- @summary Fetch comments
--- @return nil|{row: number, col: number, row2: number, col2: number, text: string}[]
--- @see https://github.com/ibhagwan/fzf-lua/blob/main/lua/fzf-lua/providers/buffers.lua#L492
M.get_comments = function(opts)
	-- Default to current buffer
	opts = vim.tbl_deep_extend("force", { bufnr = 0 }, opts or {})

	local __has_ts, _ = pcall(require, "nvim-treesitter")
	if not __has_ts then
		vim.notify("Treesitter requires 'nvim-treesitter'.", vll.WARN, { timeout = 2000 })
		return
	end

	local ts = vim.treesitter
	local ft = vim.bo[opts.bufnr].ft
	local lang = ts.language.get_lang(ft) or ft
	if not M.has_ts_parser(lang) then
		vim.notify(
			string.format("No treesitter parser found for '%s' (bufnr=%d).", opts._bufname, opts.bufnr),
			vll.WARN,
			{ timeout = 2000 }
		)
		return
	end

    -- @experimental Map variable checks for duplicates.
    local map = {}
    local res = {}

	-- @issue Disable for help (problematic)
	if vim.tbl_contains({ "vimdoc" }, lang) then
		return
	end
	-- @issue For injected ones, use per-line basis
	if vim.tbl_contains({ "markdown", "svelte" }, lang) then
		vim.notify("Using legacy mode", vll.INFO, { timeout = 1000 })
		for i, l in ipairs(vim.api.nvim_buf_get_lines(opts.bufnr, 0, -1, false)) do
			-- local _, _, match = string.find(l, "^%s*<!--%W*id[:=](%S+)")
			local start, finish, prefix, match = string.find(l, "^(%W+)id[:=](%S+)")
			if match and M.is_comment(opts.bufnr, i, start + prefix:len()) then
			-- if match then
				table.insert(res, { row = i, col = start + prefix:len(), row2 = i, col2 = finish + 1, text = match, duplicate = false })
                if map[match] then
                    res[#res].duplicate = true
                    res[map[match]] = true
                end
			end
		end
		return res
	end

	local query = ts.query.parse(lang, "(comment) @comment")
	local parser = ts.get_parser(opts.bufnr)
	if not parser then
		return
	end
	local trees = parser:parse()
	if not trees then
		return
	end

	-- local res = {}
	-- for _, t in ipairs(trees) do
	-- 	local root = t:root()
	-- 	for _, node in query:iter_captures(root, 0) do
	-- 		vim.notify(ts.get_node_text(node, opts.bufnr))
	-- 		local text = ts.get_node_text(node, opts.bufnr)
	-- 		local _, _, match = string.find(text, "^%W*id[:=](%S+)")
	-- 		if match then
	-- 			local row, col = node:range()
	-- 			table.insert(res, { row = row + 1, col = col, text = match })
	-- 		end
	-- 		-- Do something with the matches (e.g., highlight them)
	-- 		-- local start_row, start_col, end_row, end_col = match:range()
	-- 		-- vim.api.nvim_buf_add_highlight(0, -1, 'htmlTag', start_row, start_col, end_col)
	-- 	end
	-- end

	for _, t in ipairs(trees) do
		local root = t:root()
		if not query then
			return
		end

		for _, node in query:iter_captures(root, opts.bufnr) do
			local text = ts.get_node_text(node, opts.bufnr)
			--- @example
			---
			---```lua
			---select(3, string.find("-id=hello", "%W*id[:=](%S+)")) == "hello"
			---```
			local col, _, prefix, match = string.find(text, "^(%W+)id[:=](%S+)")
			if match then
				local row, _, row2, col2 = node:range()
				table.insert(res, { row = row + 1, col = col + prefix:len(), row2 = row2 + 1, col2 = col2 + 1, text = match, duplicate = false })
                if map[match] then
                    res[#res].duplicate = true
                    res[map[match]] = true
                end
			end
		end
		::done::
	end

	return res
end

-- id=fn-has_ts_parser
--- @see https://github.com/ibhagwan/fzf-lua/blob/main/lua/fzf-lua/utils.lua#L1384
M.has_ts_parser = function(lang)
	if vim.fn.has("nvim-0.11") == 1 then
		return vim.treesitter.language.add(lang)
	else
		return pcall(vim.treesitter.language.add, lang)
	end
end

-- id=fn-list_buffers
M.list_buffers = function()
    return vim.tbl_map(function(buf) return vim.api.nvim_buf_get_name(buf) end, vim.tbl_filter(function(buf) return vim.api.nvim_buf_is_loaded(buf) and M.is_valid_buf(buf) end, vim.api.nvim_list_bufs()))
end

-- id=fn-find_buffer_by_name
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

-- id=fn-add_file_to_buffer
--- @return integer
M.add_file_to_buffer = function(name)
	local bufnr = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(bufnr, name)
	vim.api.nvim_buf_call(bufnr, vim.cmd.edit)
	return bufnr
end

-- id=fn-wait_for_parsing
M.wait_for_parsing = function(buf)
    local parser = vim.treesitter.get_parser(buf)
    if parser then
        local tree = parser:parse(true)[1]
        if tree and tree:root() then
            return true
        end
    end
    return false
end

-- id=fn-is_comment
--- @param buf integer Buffer number
--- @param row integer 1-indexed
--- @param col integer 1-indexed
--- @see https://github.com/folke/todo-comments.nvim/blob/main/lua/todo-comments/highlight.lua#L62
M.is_comment = function(buf, row, col)
    while not M.wait_for_parsing(buf) do
        vim.wait(100)  -- Wait for 100ms before checking again
    end
    local captures = vim.treesitter.get_captures_at_pos(buf, row - 1, col)
    for _, c in ipairs(captures) do
        if c.capture == "comment" then
            return true
        end
    end
    return false
    -- vim.notify(row.." "..col)

	-- local win = vim.fn.bufwinid(buf)
	-- return win ~= -1
	-- 	and vim.api.nvim_win_call(win, function()
	-- 		for _, i1 in ipairs(vim.fn.synstack(row, col)) do
	-- 			local i2 = vim.fn.synIDtrans(i1)
	-- 			local n1 = vim.fn.synIDattr(i1, "name")
	-- 			local n2 = vim.fn.synIDattr(i2, "name")
	-- 			vim.notify(n1 .. n2)
	-- 			if n1 == "Comment" or n2 == "Comment" then
	-- 				return true
	-- 			end
	-- 		end
	-- 	end)
end

return M
