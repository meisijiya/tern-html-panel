--!strict
-- lib/ 的测试：不需要 Tern 在跑，也不碰磁盘。
--
--   test/build.sh [path-to-luau]
--
-- 只拼 lib/，不拼两个半边：半边在加载时就要 tern.* 全局，桩会掩盖真机行为；
-- 半边靠真机验收（见 README 的验收清单）。

-- ==== TESTS ====

local failures = 0
local total = 0

local function show(v: any): string
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

local function eq(name: string, got: any, want: any)
	total += 1
	if got ~= want then
		failures += 1
		print(string.format("FAIL %s\n  got  %s\n  want %s", name, show(got), show(want)))
	end
end

local function pathOf(name: string, input: string, opts: any, want: string)
	eq(name, path.resolve(input, opts).path, want)
end

local function errorOf(name: string, input: string, opts: any)
	total += 1
	local got = path.resolve(input, opts)
	if got.path ~= nil or type(got.error) ~= "string" or got.error == "" then
		failures += 1
		print(string.format("FAIL %s: expected an error, got path=%s error=%s", name, show(got.path), show(got.error)))
	end
end

pathOf("absolute", "D:/a/b.html", {}, "D:/a/b.html")
pathOf("backslashes", "D:\\26code\\a.html", {}, "D:/26code/a.html")
pathOf("file url", "file:///D:/a/b.html", {}, "D:/a/b.html")
pathOf("file url with host", "file://localhost/D:/a/b.html", {}, "D:/a/b.html")
pathOf("percent encoded", "file:///D:/26code/%E9%B9%88%E9%B9%95/x.html", {}, "D:/26code/鹈鹕/x.html")
pathOf("quoted", '"D:/a/b.html"', {}, "D:/a/b.html")
pathOf("single quoted with spaces", "'  D:/a b/c.html  '", {}, "D:/a b/c.html")
pathOf("tilde", "~/x.html", { home = "C:/Users/me" }, "C:/Users/me/x.html")
pathOf("tilde alone", "~", { home = "C:/Users/me" }, "C:/Users/me")
pathOf("relative with base", "pages/a.html", { base = "D:/26code/foo" }, "D:/26code/foo/pages/a.html")
pathOf("relative into path", "pages/../x.html", { base = "D:/26code/foo/" }, "D:/26code/foo/x.html")
pathOf("unc", "//wsl.localhost/Ubuntu/home/me/x.html", {}, "//wsl.localhost/Ubuntu/home/me/x.html")
pathOf("collapses slashes", "D:/a///b//c.html", {}, "D:/a/b/c.html")

errorOf("empty", "   ", {})
errorOf("relative without base", "pages/a.html", {})
errorOf("tilde without home", "~/x.html", {})

local function list(entries: { string }): string
	return table.concat(entries, "|")
end

eq("history prepends", list(history.add({ "b", "c" }, "a")), "a|b|c")
eq("history dedupes to front", list(history.add({ "b", "a", "c" }, "a")), "a|b|c")
eq("history caps", list(history.add({ "b", "c" }, "a", 2)), "a|b")
eq("history from empty", list(history.add({}, "a")), "a")
eq("history skips empty path", list(history.add({ "a" }, "")), "a")

print(string.format("%d/%d passed", total - failures, total))
if failures > 0 then
	error(string.format("%d failing", failures))
end
