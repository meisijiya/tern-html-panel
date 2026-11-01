#!/usr/bin/env bash
# 跑 test/run_tests.luau：把 lib/ 和断言拼成一个脚本交给 luau。luau 的 require 在
# 独立沙箱里跑，桩进不去，所以只能拼接。
#
#   test/build.sh [path-to-luau]
#
# luau 依次取 $1、$TERNS_LUAU、PATH 上的 luau。
set -eu

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(dirname "$here")"
runner="$here/run_tests.luau"
# Windows 的 luau.exe 读不了 WSL 的 /tmp，拼接结果放仓库里。
out="$here/.bundle.luau"
trap 'rm -f "$out"' EXIT

luau="${1:-${TERNS_LUAU:-}}"
if [[ -z "$luau" ]]; then
	if command -v luau >/dev/null 2>&1; then
		luau="$(command -v luau)"
	else
		echo "no luau CLI: pass one as \$1 or set \$TERNS_LUAU" >&2
		echo "  download: https://github.com/luau-lang/luau/releases" >&2
		exit 1
	fi
fi

# 只有在 WSL 里才换路径：Git Bash 里 wslpath 也在 PATH 上，换出来的 /mnt/… 反而跑不了。
wsl=0
case "$(uname -r)" in
*microsoft* | *Microsoft*) wsl=1 ;;
esac

if [[ "$wsl" == 1 ]]; then
	case "$luau" in
	[A-Za-z]:[\\/]*)
		luau="$(wslpath -u "$luau")"
		;;
	esac
fi

python_cmd="$(command -v python3 || command -v python)"
"$python_cmd" - "$runner" "$repo" "$out" <<'PY'
import io
import os
import re
import sys

runner_path, repo, out_path = sys.argv[1:4]
MARKER = "-- ==== TESTS ===="
REQUIRE = re.compile(r'^local \w+ = require\("\./(lib/)?\w+"\)\n', re.M)
MODULES = ["path", "history"]


def source(path):
	with io.open(path, encoding="utf-8") as fh:
		text = fh.read()
	if text.startswith("--!strict\n"):
		text = text[len("--!strict\n"):]
	# 拼进函数体后 export 不再合法：type 留声明，const 变局部。
	text = re.sub(r'(?m)^export (type|const) ', lambda m: "type " if m.group(1) == "type" else "local ", text)
	return REQUIRE.sub("", text)


with io.open(runner_path, encoding="utf-8") as fh:
	runner = fh.read()
head, tail = runner.split(MARKER, 1)

parts = [head]
for name in MODULES:
	body = source(os.path.join(repo, "lib", name + ".luau"))
	parts.append("local %s = (function()\n%s\nend)()\n" % (name, body))
parts.append(tail)

with io.open(out_path, "w", encoding="utf-8", newline="\n") as fh:
	fh.write("".join(parts))
print(out_path)
PY

if [[ "$wsl" == 1 && "$luau" == *.exe ]]; then
	out="$(wslpath -w "$out")"
fi

"$luau" "$out"
