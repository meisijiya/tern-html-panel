--!strict
-- 最近打开的路径：最新在前、按路径去重、有上限。

local M = {}

local DEFAULT_CAP = 10

--- 把 `path` 放到最前，去掉重复的旧条目，最多留 `cap` 条。空路径不改动。
function M.add(entries: { string }, path: string, cap: number?): { string }
	local limit = cap or DEFAULT_CAP
	local out: { string } = {}
	if path ~= "" then
		table.insert(out, path)
	end
	for _, entry in ipairs(entries) do
		if entry ~= path and entry ~= "" and #out < limit then
			table.insert(out, entry)
		end
	end
	return out
end

return M
