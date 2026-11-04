# 5 分钟自己编出 BXRTSPEdit.dylib（纯网页，不用装任何东西）

目标：**不装 Mac、不装 git、不下工具**，只用 GitHub 网页点几下，得到 `BXRTSPEdit.dylib`。
拿到后 TrollFools 一次注入两个 dylib，原版界面上就多一个蓝色 `RTSP` 圆钮，点开就是输入框。

---

## 第 1 步：建仓库（1 分钟）

1. 打开 https://github.com/new （没账号先注册，邮箱验证）
2. Repository name：`bxrtspedit`
3. 选 **Private**
4. **不要**勾 Add a README / .gitignore / license
5. 点绿色 **Create repository**

## 第 2 步：上传这 4 个文件（2 分钟）

在空仓库页面点蓝色小字 **uploading an existing file**，然后把本 zip 解压出来的**内容**拖进去：

```
Makefile
Tweak.xm
README.md
.github/workflows/build.yml      ← 这个是隐藏目录里的，必须一起上传
```

> Windows 资源管理器默认看不到 `.github`。
> 最稳的做法：把整个文件夹拖进去（不是单个文件），GitHub 会保留目录结构。
> 上传后确认仓库根目录**直接**是 `Makefile`，不能是 `bxrtspedit/Makefile`。

拖完点绿色 **Commit changes**。

## 第 3 步：跑编译（2–4 分钟）

1. 仓库顶部点 **Actions**
2. 左边选 **build-bxrtspedit**
3. 右边 **Run workflow** → 绿色按钮 **Run workflow**
4. 等黄点转绿 ✅（第一次要下载 Theos + iOS SDK，慢一点，正常）

## 第 4 步：下载成品

1. 点进这次运行记录（绿色勾那条）
2. 页面**拉到底部** → **Artifacts** → 点 **BXRTSPEdit-dylib**
3. 解压得到 `BXRTSPEdit.dylib`

## 第 5 步：注入（1 分钟）

TrollFools → 选宿主 App（抖音）→ 注入 → **同时勾两个**：

```
BXFloat.dylib        （你桌面那个能跑的版本）
BXRTSPEdit.dylib     （刚编出来的）
```

打开 App → 左侧出现蓝色 `RTSP` 圆钮（可拖）→ 点开 → 粘贴地址 → 保存 → 回原版面板点预览。

---

## 失败怎么办

| 现象 | 原因 / 处理 |
|---|---|
| Actions 里没有 `build-bxrtspedit` | `.github` 没上传成功。用命令行 `git add .` 重推，或网页上重新拖整个文件夹 |
| 编译失败 `SDK not found` / clone 超时 | 重新 Run workflow 一次（网络问题，不是代码问题） |
| 编译报语法错 | 把红色日志发我，我改到过为止 |
| 有圆钮但改地址无效 | 日志里搜 `[BXRTSP]`：`没命中目标方法` = 宿主不是这一版（0.20.33）；`hooked -[类 方法]` = 挂上了 |

## 日志过滤

```
log stream --style compact --predicate 'eventMessage CONTAINS "BXRTSP"'
```

看到 `[BXRTSP] hooked -[...]` 就说明钩子生效了。
