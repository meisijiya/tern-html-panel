# GLOSSARY

## 面板（panel）

`host.luau` 注册的 `tern-html-panel.html` 块：一个输入框、最近打开列表、一行提示。它在宿主半边运行，拿不到 `cx.browser`，也没有可用的定时器。

## 请求（request）

面板写进 `tern.kv` 的 `request` 键：`{seq, pane, path}`。`pane` 是面板自己的 pane id——kv 是全局的，靠它把请求定向到一个窗口；`seq` 单调递增，跨窗口、跨重启只增。

## 结果（result）

窗口半边写进 `tern.kv` 的 `result` 键：`{seq, ok, path | error}`。面板收到窗口发来的 `refresh` 事件后读它，把 `ok` 翻成「已打开 …」、把 `error` 原样显示。

## 历史（history）

`tern.kv` 的 `history` 键：最近成功打开的绝对路径，最新在前、按路径去重、上限 10 条。只有窗口半边写（单一写者），面板只读。

## 裸路径（bare path）

不带 scheme 的本地路径，如 `D:/26code/x.html`。Tern 的 browser `open` op 会把它归一化成 `file:///…` 并渲染；显式的 `file:///D:/x.html` 反而可能撞 `WebView2 error 9`。面板一律交裸路径给 op。

## 画中画（picture in picture）

浮在终端之上的独立窗口，不占 tab 的格子。面板用 `cx.layout:float` 浮在右上角，页面由 browser `open` op 的 `corner` 直接开成浮层落在右下角。
