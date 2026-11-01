--!strict
-- 窗口半边：把面板写下的请求变成 Tern 内置 browser 块里的一个页面。
--
-- 面板（host.luau）没有 cx.browser，只有窗口有，所以请求走 tern.kv：
-- 面板写 `request`（带自己的 pane 定向），这里写 `result` 与 `history`。

local pathlib = require("./lib/path")
local history = require("./lib/history")
local store = require("./lib/store")

local KIND = "tern-html-panel.html"
local POLL_MS = 250

local seenSeq = 0

local function home(): string?
	return tern.getenv("USERPROFILE") or tern.getenv("HOME")
end

--- 比较用：Windows 路径不分大小写，末尾斜杠不算数。
local function samePath(a: string, b: string): boolean
	local x = string.gsub(string.lower(a), "/+$", "")
	local y = string.gsub(string.lower(b), "/+$", "")
	return x == y
end

--- browser 块的 url 和磁盘路径是不是同一个文件。
local function sameFile(url: string, path: string): boolean
	local resolved = pathlib.resolve(url, {})
	return resolved.path ~= nil and samePath(resolved.path, path)
end

--- 面板所在 tab 里第一个有 cwd 的 agent；没有就用面板自己的 cwd。
--- shortcut: 同 tab 多个 agent 时取列表里的第一个，不按切分树挑最近的；真觉得挑错了再补。
local function baseFor(cx: WindowCx, pane: number): string?
	local tab = cx.session:tab_of(pane)
	if tab ~= nil then
		for _, agent in ipairs(cx.agents:list()) do
			if agent.cwd ~= "" and cx.session:tab_of(agent.pane) == tab then
				return agent.cwd
			end
		end
	end
	local info = cx.session:pane(pane)
	return if info and info.cwd ~= "" then info.cwd else nil
end

local function record(cx: WindowCx, req: any, path: string?, err: string?)
	if path ~= nil then
		store.set(store.HISTORY, history.add(store.history(), path))
		store.set(store.RESULT, { seq = req.seq, ok = true, path = path })
	else
		store.set(store.RESULT, { seq = req.seq, ok = false, error = err })
	end
	store.set(store.LAST_SEQ, req.seq)
	-- 面板半边没有定时器：写完结果戳它一下，让它自己的 event 处理去读。
	-- pcall 会拆散方法绑定，所以包一层闭包。
	pcall(function()
		cx.session:event(req.pane, { ev = "action", id = "dock.refresh", act = "refresh" })
	end)
	tern.chrome.refresh()
end

local function errorText(result: any, err: any): string
	if type(result) == "table" and type(result.error) == "table" and type(result.error.message) == "string" then
		return result.error.message
	end
	if type(result) == "table" and type(result.error) == "string" then
		return result.error
	end
	return tostring(err)
end

local function openBlock(cx: WindowCx, req: any, path: string)
	cx.browser:call({ op = "blocks" }):next(function(result: any, _err: any, cx2: WindowCx?)
		if cx2 == nil then
			return
		end
		local found: any = nil
		local blocks = if type(result) == "table" and type(result.ok) == "table" and type(result.ok.blocks) == "table"
			then result.ok.blocks
			else {}
		for _, block in ipairs(blocks) do
			if type(block.url) == "string" and sameFile(block.url, path) then
				found = block
				break
			end
		end

		local function openNew(cx3: WindowCx)
			cx3.browser:call({ op = "open", owner = req.pane, url = path, how = "beside" }):next(function(open: any, err: any, cx4: WindowCx?)
				if cx4 == nil then
					return
				end
				if type(open) == "table" and open.ok then
					-- 焦点回到面板：接着粘下一个路径比盯着页面更常用。
					cx4.layout:focus(req.pane)
					record(cx4, req, path, nil)
				else
					record(cx4, req, nil, errorText(open, err))
				end
			end)
		end

		if found == nil then
			openNew(cx2)
			return
		end

		-- 上一轮残留的块可能 url 一样、页面已死：先看它的状态。
		cx2.browser:call({ op = "state", block = found.block }):next(function(state: any, _stateErr: any, cx3: WindowCx?)
			if cx3 == nil then
				return
			end
			local live = type(state) == "table" and type(state.ok) == "table" and state.ok.error == nil
			if live then
				cx3.layout:focus(found.block)
				record(cx3, req, path, nil)
				return
			end
			openNew(cx3)
		end)
	end)
end

local function handle(cx: WindowCx, req: any)
	local raw = req.path
	if type(raw) ~= "string" then
		record(cx, req, nil, "没有路径")
		return
	end
	local resolved = pathlib.resolve(raw, { home = home(), base = baseFor(cx, req.pane) })
	if resolved.path == nil then
		record(cx, req, nil, resolved.error)
		return
	end
	local path = resolved.path :: string

	local ok, exists = pcall(tern.fs.exists, path)
	if not ok or not exists then
		record(cx, req, nil, "文件不存在：" .. path)
		return
	end
	openBlock(cx, req, path)
end

local function owns(cx: WindowCx, pane: number): boolean
	for _, info in ipairs(cx.session:panes()) do
		if info.pane == pane then
			return true
		end
	end
	return false
end

local function isPanel(info: any): boolean
	return info.exited == nil and (info.block == KIND or info.program == KIND)
end

local function openPanel(cx: WindowCx)
	for _, info in ipairs(cx.session:panes()) do
		if isPanel(info) then
			cx.layout:focus(info.pane)
			return
		end
	end
	local pane = cx:new_block(KIND, nil, "beside")
	if pane == nil then
		cx:toast("error", "HTML 面板没有加载", "把插件装在当前机器上再试。")
	end
end

local function poll(cx: WindowCx?)
	if cx == nil then
		return
	end
	local req = store.get(store.REQUEST)
	if type(req) == "table" and type(req.seq) == "number" and type(req.pane) == "number" and req.seq > seenSeq then
		if owns(cx, req.pane) then
			seenSeq = req.seq
			handle(cx, req)
		end
	end
	tern.timer(POLL_MS, poll)
end

--- 状态栏显示最近打开的那个文件，点它开面板。
local function latest(): string?
	local entries = store.history()
	if type(entries) == "table" and type(entries[1]) == "string" then
		return string.match(entries[1], "([^/]+)$") or entries[1]
	end
	return nil
end

tern.command({
	id = "panel",
	title = "HTML 面板",
	icon = "web",
	run = openPanel,
})

tern.chrome.status(function(_pane)
	local name = latest()
	return {
		{
			text = name or "HTML",
			icon = "web",
			command = "plugin.tern-html-panel.panel",
		},
	}
end)

do
	local last = store.get(store.LAST_SEQ)
	if type(last) == "number" then
		seenSeq = last
	end
end

tern.timer(POLL_MS, poll)
