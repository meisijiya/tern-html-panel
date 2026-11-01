--!strict
-- HTML 面板（宿主半边）：收路径，写请求，显示结果与最近打开。
--
-- 真正开块的是 window.luau —— 只有窗口半边拿得到 cx.browser。两边靠 tern.kv 传令：
-- 这里写 `request`，那边写 `result` 和 `history`（kv 全局，请求带 pane 定向），
-- 写完再给面板发一个 refresh 事件：宿主半边没有定时器。

local store = require("./lib/store")

local ui = tern.ui

local LIST_KEY = "recent"

type Text = { text: string, cursor: number }
type Message = { tone: string, text: string }
type State = {
	input: Text,
	message: Message?,
	history: { string },
	--- 已提交、等结果的序号。
	pending: number?,
}

--- 输入框的光标：一直停在末尾，所以只需要“文本有多长”。
--- Tern 的 cursor 是 UTF-16 偏移：BMP 之外的一个字符占 2 个单元。
local function cursorOf(text: string): number
	local units = 0
	local at = 1
	while at <= #text do
		local code = utf8.codepoint(text, at)
		units += if code > 0xFFFF then 2 else 1
		at = utf8.offset(text, 2, at) or (#text + 1)
	end
	return units
end

--- 删掉最后一个字符（不是最后一个字节）。
local function dropLast(text: string): string
	local count = utf8.len(text) or 0
	if count == 0 then
		return ""
	end
	local start = utf8.offset(text, count) or 1
	return string.sub(text, 1, start - 1)
end

--- 序号：跨面板、跨窗口、跨重启只增。
local function nextSeq(): number
	local high = 0
	for _, key in ipairs({ store.NEXT_SEQ, store.LAST_SEQ }) do
		local value = store.get(key)
		if type(value) == "number" and value > high then
			high = value
		end
	end
	local seq = high + 1
	store.set(store.NEXT_SEQ, seq)
	return seq
end

local function basename(path: string): string
	return string.match(path, "([^/]+)$") or path
end

local function dirOf(path: string): string
	return string.gsub(path, "[^/]+$", "")
end

local function submit(state: State, cx: BlockCx)
	local raw = state.input.text
	if string.match(raw, "^%s*$") ~= nil then
		state.message = { tone = "warning", text = "先粘一个 HTML 路径" }
		return
	end
	local seq = nextSeq()
	store.set(store.REQUEST, { seq = seq, pane = cx.pane, path = raw })
	state.pending = seq
	state.message = { tone = "muted", text = "打开中…" }
end

--- 窗口半边写完结果后会发一个 refresh 事件过来，这里把结果读成状态。
local function applyResult(state: State)
	local result = store.get(store.RESULT)
	if state.pending == nil or type(result) ~= "table" or result.seq ~= state.pending then
		return
	end
	if result.ok then
		state.message = { tone = "muted", text = "已打开 " .. basename(tostring(result.path)) }
		state.input = { text = "", cursor = 0 }
	else
		state.message = { tone = "warning", text = tostring(result.error) }
	end
	state.pending = nil
end

local function messageNode(message: Message?): Node?
	if message == nil then
		return nil
	end
	return ui.text({ ui.span(message.text, message.tone) })
end

local function historyList(state: State, cx: BlockCx): Node
	local items: { Item } = {}
	for _, path in ipairs(state.history) do
		table.insert(items, {
			label = { ui.span(basename(path), "strong") },
			detail = { ui.span(dirOf(path), "muted") },
			icon = "web",
		})
	end
	-- shortcut: 列表行没法从公开 API 拿 id，直接改节点里的 key（tern-prompt-panel 同样做法）；
	-- Tern 改节点结构就得跟着改。
	local list = ui.list(items)
	local kids = list.c or {}
	for i in ipairs(items) do
		local props: { [string]: any } = kids[i].p or {}
		props.key = tostring(i)
		kids[i].p = props
	end
	local props: { [string]: any } = list.p or {}
	props.key = LIST_KEY
	props.empty = { ui.span("还没有打开过", "muted") }
	props.max = { lines = math.max(3, cx.rows - 8) }
	list.p = props
	return list
end

tern.block.define("html", {
	init = function(_cx: BlockCx, _args: { string }, _saved: any): State
		return {
			input = { text = "", cursor = 0 },
			message = nil,
			history = store.history(),
			pending = nil,
		}
	end,

	title = function(_state: State): string
		return "HTML"
	end,

	view = function(state: State, cx: BlockCx): BlockView
		local body: { Node } = {
			ui.text({
				ui.span("HTML 面板", "strong"),
				ui.span("  粘一个本地 HTML 路径，Enter 打开", "muted"),
			}),
			ui.node("input", {
				key = "f_path",
				text = state.input.text,
				cursor = state.input.cursor,
				placeholder = "D:/…/page.html、file:///D:/… 或 ./page.html",
			}),
		}
		local message = messageNode(state.message)
		if message then
			table.insert(body, message)
		end
		table.insert(body, historyList(state, cx))
		-- 这个按钮也是窗口半边回来的通道：它按 `dock.refresh` 发 refresh，
		-- 带动 event 处理读结果（宿主半边没有定时器）。
		local dock = ui.row({
			ui.button("刷新", { icon = "refresh", key = "refresh", variant = "quiet", actions = { click = "refresh" } }),
			ui.button("清空", { icon = "trash", key = "clear", variant = "quiet", actions = { click = "clear" } }),
			ui.text({ ui.span("窗口半边写完结果会自己触发", "muted") }),
		})
		return { main = ui.col(body), dock = dock }
	end,

	key = function(state: State, key: Key, cx: BlockCx): boolean?
		-- shortcut: 光标恒在末尾，左/右/Home/End 不移动；路径多是整段粘贴，要改就 Esc 重来。
		if key.name == "enter" then
			submit(state, cx)
			return true
		elseif key.name == "escape" then
			state.input = { text = "", cursor = 0 }
			state.message = nil
			return true
		end
		if key.ctrl or key.alt or key.meta then
			return false
		end
		if key.name == "paste" then
			-- 单行输入：多行粘贴里的换行去掉，否则路径里藏着看不到的字符。
			state.input.text = state.input.text .. (string.gsub(key.text or "", "[\r\n]+", ""))
		elseif key.name == "backspace" then
			state.input.text = dropLast(state.input.text)
		elseif key.text ~= nil and key.text ~= "" then
			state.input.text = state.input.text .. key.text
		else
			return false
		end
		state.input.cursor = cursorOf(state.input.text)
		return true
	end,

	event = function(state: State, ev: UiEvent, cx: BlockCx)
		if ev.ev == "action" and ev.act == "refresh" then
			applyResult(state)
			state.history = store.history()
			return
		end
		if ev.ev == "action" and ev.act == "clear" then
			store.set(store.HISTORY, nil) -- nil 删键：留 {} 会写成空对象
			state.history = {}
			return
		end
		if ev.ev ~= "select" or type(ev.item) ~= "string" then
			return
		end
		local prefix = "main." .. LIST_KEY .. "."
		if string.sub(ev.item, 1, #prefix) ~= prefix then
			return
		end
		local at = tonumber(string.sub(ev.item, #prefix + 1))
		local path = if at then state.history[at] else nil
		if path == nil then
			return
		end
		state.input = { text = path, cursor = cursorOf(path) }
		submit(state, cx)
	end,
})
