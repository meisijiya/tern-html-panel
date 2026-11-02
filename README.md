# tern-html-panel

粘一个本地 HTML 路径，在 Tern 内置 browser 块里渲染。

## 为什么

Tern 的 browser 块地址栏是 URL 栏：粘 `D:/x.html` 会被当成搜索词丢给搜索引擎，粘 `file:///D:/x.html` 会撞 `WebView2 error 9` 或变成下载。同一个路径走 `tern browser` 的 `open` op 是能正常渲染的——本插件把这条路径做成一个面板。

## 安装

```bash
tern plugin link D:/26code/tern-html-panel
tern plugin list            # 期望 ready
```

改过 `lib/` 后要 `tern plugin unlink tern-html-panel` 再 `link`：`require` 有缓存，只 `reload` 会拿新半边配旧模块。

## 用法

1. 命令面板「HTML 面板」，或点状态栏最右边的那个文件名片。
2. 粘路径，Enter。

接受的写法（都会先规整再打开）：

- `D:/26code/x.html`、`D:\26code\x.html`（反斜杠换正斜杠）
- `file:///D:/26code/x.html`（`file://` 前缀与百分号编码都剥掉）
- `"D:/26code/x.html"`（被引号包住）
- `~/x.html`（按 `USERPROFILE` / `HOME` 展开）
- `pages/x.html`（相对路径：先用面板所在 tab 里最近的 agent 的 cwd，没有就用面板自己的 cwd）

同一路径已经开着就聚焦它，不重复开；页面已死（`state.error` 非空）才新开。打开成功后焦点回到面板，接着粘下一个。

面板和页面都默认以画中画浮层出现：面板浮在窗口右上角，页面浮在右下角，都不裂终端的格子、不动 tab 布局。想变常规布局，用 Tern 自带的 `Picture in picture`（`Ctrl+Alt+Shift+P`）切回去。

已经是并列布局的旧面板和旧页面（改动前开的）也会被浮起来：从状态栏重新打开面板会把它浮到右上角，重新粘同一个路径会把它浮到右下角。

最近 10 条记在 `tern.kv`，点一条即重开；底部「清空」删掉历史，「刷新」手动重读结果（窗口半边写完结果本来会自己触发一次，这个是兜底）。`Esc` 清输入。

## 结构

- `host.luau`：面板块（输入框、历史、错误行）。宿主半边没有 `cx.browser`，也没有可用定时器。
- `window.luau`：窗口半边。轮询 `request`，开块、复用、写 `result` 与 `history`，再给面板发一个 `refresh` 事件。
- `lib/path.luau`：路径规整（引号、`file://`、百分号编码、反斜杠、`~`、`.`/`..`、相对路径）。纯函数，不碰磁盘。
- `lib/history.luau`：最近路径的去重与截断。纯函数。
- `tern.d.luau`：`tern plugin types .` 生成，勿手改。

两个半边只通过 `tern.kv` 加一个 TSP 事件通信；kv 是全局的，所以请求带面板自己的 pane id 定向。

## 测试

```bash
test/build.sh /path/to/luau      # 或 TERNS_LUAU=... test/build.sh
```

`test/build.sh` 把 `lib/` 和断言拼成一个脚本再跑：luau 的 `require` 在独立沙箱里，桩进不去。半边不参与单测——它们在加载时就要 `tern.*` 全局，桩会掩盖真机行为。

## 真机验收（改完必跑）

1. `tern plugin link .` + `tern plugin reload tern-html-panel` → `tern plugin list` 里 `ready`。
2. 开面板 → 面板浮在右上角且自带焦点；粘 `D:/26code/learning-SuperBizAgent/index.html` + Enter → 右下角浮出 browser 块，`tern browser '{"op":"blocks"}' --window <KEY>` 里该块 `title` 非空。
3. 再粘同一路径 → 块数量不变，焦点回到面板。
4. 反斜杠、`file:///`、带引号三种写法各一次 → 都渲染。
5. 粘 `D:/nope/x.html` → 面板红字「文件不存在」，不开新块。
6. 相对路径：面板所在 tab 的 cwd 下存在该文件 → 打开；不存在 → 报错，不猜。
7. 重开面板 / 重启 Tern → 历史还在。

## 不做

- 不接管 browser 块的地址栏（那是 Tern 的 UI，插件没有 hook）。
- 不读剪贴板（插件 API 只有 `copy`，没有 read）。
- 不起本地 HTTP 服务：内置 browser 块对裸路径能渲染，不需要端口和静态服务器。
- 不监视目录、不绑默认快捷键。
- 不为 PDF/图片做专门适配：browser 块本身能显示。
