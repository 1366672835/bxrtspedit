# BXRTSPEdit —— 让「原版界面」能改 RTSP 地址

原版 `BXFloat.dylib` 的界面里**没有地址输入框**，补丁也加不了控件（加控件 = 写 ObjC = 要编译）。
所以这个组合只能这么做：**原版 dylib 一个字不动 + 额外注入一个 20KB 的小 dylib**，
它在界面上放一个可拖的 `RTSP` 圆钮，点开就是输入框。

## 它挂在哪、为什么这么挂

`BXFloat` 里真正取地址的那段（两个架构各一份）：

```
arm64  0x3311C4
arm64e 0x336AC4（前面可能带 pacibsp，源码里给了 3 个候选地址挨个试）
```

函数开头：

```
ldp  x0, x28, [x0, #0x20]     ; x0 = self->_urlString（NSString），x28 = 来源枚举
...
msgSend(x0, @selector(UTF8String))
x21 = char *url               ; ← 后面全用这个
```

所以只要在**函数入口**把 `self+0x20` 换成用户输入的那个 `NSString`，
后面整条链路（包括 `server_only` 的判断）就都用我们的地址 —— 原版 UI 完全不用改。

`objc_storeStrong` 写强引用槽，等于 `self->_urlString = url`，旧的自动释放，不泄漏。

## 行为

- 第一次启动：读 `NSUserDefaults` 的 `bx_rtsp_url`，没有就用 dylib 内嵌的那串（即 `.bat` 打进去的地址）
- 点 `RTSP` 圆钮 → 弹输入框（带粘贴清除按钮、URL 键盘）→ 保存
- 保存后**下一次点「预览」就生效**，不用重启 App
- 弹窗里「用原版地址」= 清空覆盖，回到内嵌地址
- 位置可拖，存 `bx_rtsp_btn_x` / `bx_rtsp_btn_y`

## 怎么出成品（3 步）

源码已经齐了：`Makefile` / `Tweak.xm` / `.github/workflows/build.yml`。

### A. 有 Mac（最快）

```bash
export THEOS=~/theos
cd BXRTSPEdit
make            # 产物 .theos/obj/*/BXRTSPEdit.dylib
```

### B. 没 Mac，用 GitHub Actions（2–4 分钟）

1. 新建 Private 仓库（空仓库，不要 README）
2. 把本目录**所有内容**推上去（`.github` 是隐藏目录，必须包含）
3. Actions → `build-bxrtspedit` → Run workflow → 绿了以后从 Artifacts 下 `BXRTSPEdit-dylib`

> 你这台机器上没有 git 凭据时，用 REST API 推（`ghpush.py` 那种写法）也行；或者网页
> 「uploading an existing file」直接拖。

### C. 注入

TrollFools → 选宿主 App → 注入**两个** dylib：

```
BXFloat.dylib                （02-原版解锁版 里那个）
BXRTSPEdit.dylib             （这里编出来的）
```

打开 App → 右上角（默认 16,140）出现蓝色 `RTSP` 圆钮 → 点开输入地址。

## 排错

| 现象 | 原因 |
|---|---|
| 没有圆钮 | dylib 没注入成功 / 不是同一个宿主 App |
| 有圆钮但改地址无效 | 日志 `[BXRTSP] 没找到目标方法` → 偏移不匹配（宿主不是 0.20.33 这一版） |
| 改完仍然连不上 | 地址本身问题；先确保 VLC 能播；注意原版只走 `rtsp://` |
| 弹窗点不动 | 原版面板把触摸放行了，正常情况下没问题；若被挡，先关掉原版面板再点 |

日志过滤关键词：`BXRTSP`。
