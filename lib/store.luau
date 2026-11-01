--!strict
-- 两个半边共用的 tern.kv 读写与键名。
--
-- kv 在插件的每个 VM 里都是同一份文件，键名写在两边会漂：这里只有一份。
-- 只做转发，不藏逻辑，所以没有单测——真机验收覆盖它。

local M = {}

M.REQUEST = "request"
M.RESULT = "result"
M.HISTORY = "history"
M.NEXT_SEQ = "next_seq"
M.LAST_SEQ = "last_seq"

--- 读一个键；kv 出错（缺文件、坏 JSON）时当作没有，不把异常抛进渲染。
function M.get(key: string): any
	local ok, value = pcall(tern.kv.get, key)
	if ok then
		return value
	end
	return nil
end

--- 写一个键；失败静默，下一次写会重试。
function M.set(key: string, value: any)
	pcall(tern.kv.set, key, value)
end

--- 历史条目，过滤掉非字符串。
function M.history(): { string }
	local raw = M.get(M.HISTORY)
	local out: { string } = {}
	if type(raw) == "table" then
		for _, entry in ipairs(raw) do
			if type(entry) == "string" then
				table.insert(out, entry)
			end
		end
	end
	return out
end

return M
