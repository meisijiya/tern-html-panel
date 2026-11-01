--!strict
-- 把用户粘贴的东西变成可以直接交给 browser 块的绝对路径。
--
-- 只做形状上的规整（引号、file:// 前缀、百分号编码、反斜杠、~、. 与 ..），
-- 不碰磁盘：文件存不存在由调用方用 tern.fs.exists 查。

local M = {}

export type ResolveOpts = {
	--- `~/…` 展开用的家目录；没有就让 `~` 报错。
	home: string?,
	--- 相对路径的基准目录；没有就让相对路径报错。
	base: string?,
}

export type Resolved = {
	--- 规整后的绝对路径；出错时为 nil。
	path: string?,
	--- 为什么没法得到路径，中文，可直接显示。
	error: string?,
}

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

local function unquote(s: string): string
	local first = string.sub(s, 1, 1)
	if #s >= 2 and (first == '"' or first == "'") and string.sub(s, -1) == first then
		return trim(string.sub(s, 2, -2))
	end
	return s
end

local function percentDecode(s: string): string
	if not string.find(s, "%%%x%x") then
		return s
	end
	return (string.gsub(s, "%%(%x%x)", function(hex: string): string
		return string.char(tonumber(hex, 16) :: number)
	end))
end

--- 反斜杠换正斜杠，连续斜杠收成一个；开头两个斜杠（UNC、//wsl.localhost）保留。
local function slashes(s: string): string
	s = string.gsub(s, "\\", "/")
	if string.sub(s, 1, 2) == "//" then
		return "//" .. (string.gsub(string.sub(s, 3), "/+", "/"))
	end
	return (string.gsub(s, "/+", "/"))
end

--- 拆成「前缀 + 段」，消掉 `.` 与 `..`，再拼回来。
local function collapse(s: string): string
	local prefix = ""
	local rest = s
	local drive = string.match(s, "^(%a:/)")
	if drive then
		prefix = string.sub(drive, 1, 2)
		rest = string.sub(s, 4)
	elseif string.sub(s, 1, 2) == "//" then
		prefix = "//"
		rest = string.sub(s, 3)
	elseif string.sub(s, 1, 1) == "/" then
		prefix = "/"
		rest = string.sub(s, 2)
	end

	local out: { string } = {}
	for seg in string.gmatch(rest, "[^/]+") do
		if seg == ".." then
			if #out > 0 then
				table.remove(out)
			end
		elseif seg ~= "." then
			table.insert(out, seg)
		end
	end

	if prefix == "" then
		return table.concat(out, "/")
	end
	if prefix == "//" then
		return "//" .. table.concat(out, "/")
	end
	if #out == 0 then
		return prefix
	end
	return prefix .. "/" .. table.concat(out, "/")
end

--- 去掉 `file://` 前缀（含 host），并把 `/D:/…` 还原成 `D:/…`。
local function stripFileUrl(s: string): string
	local lower = string.lower(s)
	if string.sub(lower, 1, #"file://") ~= "file://" then
		return s
	end
	local rest = string.sub(s, #"file://" + 1)
	if string.sub(rest, 1, 1) ~= "/" then
		-- file://host/path：丢掉 host。
		local slash = string.find(rest, "/")
		rest = if slash then string.sub(rest, slash) else ""
	end
	if string.match(rest, "^/%a:/") then
		rest = string.sub(rest, 2)
	end
	return rest
end

--- 把 `~` 与 `~/…` 展开成家目录。
local function expandHome(s: string, home: string?): (string?, string?)
	if s ~= "~" and string.sub(s, 1, 2) ~= "~/" then
		return s, nil
	end
	if home == nil or home == "" then
		return nil, "找不到家目录，用完整路径吧"
	end
	return home .. string.sub(s, 2), nil
end

local function isAbsolute(s: string): boolean
	return string.match(s, "^%a:/") ~= nil or string.sub(s, 1, 1) == "/"
end

function M.resolve(input: string, opts: ResolveOpts?): Resolved
	local o = opts or {}
	local text = unquote(trim(input))
	if text == "" then
		return { error = "路径是空的" }
	end

	text = collapse(slashes(percentDecode(stripFileUrl(text))))
	local expanded, homeError = expandHome(text, o.home)
	if homeError then
		return { error = homeError }
	end
	text = expanded :: string

	if not isAbsolute(text) then
		local base = o.base
		if base == nil or base == "" then
			return { error = "相对路径找不到基准目录，用完整路径吧" }
		end
		text = collapse(slashes(base) .. "/" .. text)
	end

	if not isAbsolute(text) then
		return { error = "不是一个能打开的路径：" .. text }
	end
	return { path = text }
end

return M
