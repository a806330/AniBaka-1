# 定制改动清单（CUSTOMIZATIONS）

> 本文件是定制版 Baka 相对上游官方版的**全部功能性改动**的登记表。
> 用途：软件官方更新覆盖定制版后，以新版官方源码为底，逐项核对并重放仍需要的改动，
> 官方已有等价或更优实现的项则舍弃，最终云端编译出「新版官方 + 精选定制」的版本。
>
> - 上游官方仓库：<https://github.com/AniBakaBaka/AniBaka>
> - 定制仓库：<https://github.com/a806330/AniBaka>（分支 `custom-windows-build`）
> - 定制基线：首个提交 `c6585b9ae7`（上游原始代码），其后 32 个提交均为定制改动
> - 完整 diff 参考：[customizations-diff.md](customizations-diff.md)
>   （可用 `GET /repos/a806330/AniBaka/compare/c6585b9ae7...HEAD` 随时重新生成权威版本）
>
> 本清单最后更新于 **v15（2026-11-04）**：文件夹名改用「播放地址名（线路名）」区分同一扩展源下的不同播放地址 + HLS 并发上限改回 48（选项去 4 加 48）+ 已完成分组/全选拆分/清除确认弹窗/长按提示等 UI 修复。承接 v14（clearCompleted 只清记录不删文件 + 「覆盖同名文件」开关 + 多选停留/Esc）、v13（风险加固 + UI 文案化 + 文件夹名加源名后缀）、v12（新增作品文件夹）+ 禁用官方更新覆盖。

## 更新后恢复流程（SOP）

1. **确认上游新版**：到上游仓库找最新 release/commit；官方安装包更新会整体覆盖 `D:\AniBaka\baka`（用户数据在 `文档\baka\hive`，不受影响）。
2. **逐项核对**：对下表每一项，检查新版源码对应文件——官方已实现等价/更优功能 → 该项标记"舍弃"；官方未实现或实现更差 → 重放。
3. **重放**：在定制仓库以新版上游代码重建分支（新基线提交 = 新版源码），按表逐文件合入改动。注意语义适配而非盲目打补丁（上游代码结构可能已变化）。
4. **编译**：触发 workflow `build_windows_custom.yml`（id 402046819，约 8 分钟），下载 artifact 替换 `D:\AniBaka\baka`。
5. **验证**：启动 → 批量解析多集看悬浮条 → 取消/重试 → 下载完成后核对文件落盘位置与命名。

## 功能清单

### A. 解析可靠性（核心价值，最优先保住）

| # | 功能 | 涉及文件 | 重放要点 | 舍弃条件 |
|---|------|----------|----------|----------|
| A1 | 解析独立于播放页：退出播放页解析不中断。`PlaybackContent` 加 `retain()/release()` 引用计数，dispose 被 retain 推迟 | `lib/services/playback/playback_content.dart` | 计数逻辑挂在 dispose 路径；入队时同步 retain（弹窗还开着时 content 必活） | 官方重构后解析本身不依赖页面存活 |
| A2 | 全局解析管理器 `DownloadResolveManager`（单例，独立于页面生命周期），批量解析进串行队列逐作品处理 | `lib/services/download/download_resolve_manager.dart`（新文件）、`lib/widgets/episode/episode_list_dialog.dart`（解析逻辑迁出） | 新文件可整体照搬；dialog 侧只需调用 `enqueue` | 无（上游无对应物） |
| A3 | 解析失败自动重试：首次 + 最多 3 次，退避 1/2/3 秒，单集请求 15s 超时、批内 4 集并发 | `download_resolve_manager.dart` | 常量 `_maxAttempts=4`、`_resolveConcurrency=4` | 官方有更健壮的重试机制 |
| A4 | 常驻悬浮条 `DownloadResolveBanner`：挂在 `MaterialApp.builder` 的 Stack，`ValueNotifier<ResolveBanner?>` 驱动，数字原地更新不闪烁、不排队 | `download_resolve_manager.dart`（状态+组件）、`lib/app/baka_app.dart`（挂载） | 挂载点在 builder 返回的 widget 外层 | 官方有等价的全局解析进度 UI |
| A5 | 悬浮条按钮：解析中仅 [取消]；最终失败态 [重试][取消]。取消 = 完全取消、已解析部分全部丢弃不入队；重试 = 对失败集重新发起 | `download_resolve_manager.dart` | 取消路径须 `task.dispose()` 释放已生成任务、`keepAlive?.release()` | 无 |
| A6 | 悬浮条文案：`正在解析《作品名》（X/N）【剩余N部作品排队中】`，重试提示同格式 | `download_resolve_manager.dart` | 队列数实时取 `_queue.length` | 无 |
| A7 | 解析异常时释放 keepAlive 引用（防泄漏） | `download_resolve_manager.dart` | catch 分支 `job.keepAlive?.release()` | 无 |

### B. 下载执行

| # | 功能 | 涉及文件 | 重放要点 | 舍弃条件 |
|---|------|----------|----------|----------|
| B1 | 启动即初始化下载服务（`await downloads.init()`），保证清理与压实总能执行 | `lib/app/app_runtime.dart` | 一行调用 | 官方已在启动时初始化 |
| B2 | 启动清理失效任务：`_load()` 时删除 failed 状态或文件已不存在的任务，并 `compact()` 压实 Hive（解决追加写导致文件越积越大） | `lib/services/download/download_manager.dart` | 清理后必须 compact，否则 Hive 碎片持续膨胀（实测 1.6MB→44KB） | 官方实现等价清理 |
| B3 | 下载并发可配置：任务数（1/2/3/4/6/8/10）与 HLS 分片并发（**v15 起 8/16/24/32/48**），存 `Instances.sp`，键 `download_max_concurrent` / `download_hls_concurrency` | `download_manager.dart`、`lib/pages/setting/app_settings_page.dart` | 设置页加「下载（定制版）」区块。HLS 选项沿革：v13 去 48 留 4/8/16/24/32 → **v15 去 4、加回 48**（用户实测 32 下载仍太慢），最终 8/16/24/32/48 | 官方提供下载并发设置 |
| B4 | HLS 全局并发闸门 `_Semaphore`（**v15 起软上限 48**，v13 起不再写死 16，信号量按设置值懒重建以支持 24/32/48）；合并全局串行 `_enqueueRemux`；合并不占下载槽（`_DownloadRun.merging`） | `download_manager.dart` | 三者配套，防多任务同时合并导致卡顿。软上限：`_kMaxHlsConcurrency=48`（v14 为 32），`_hlsConcurrency` 超限截断；`_gate` 在设置值变化时重建（`_hlsGateValue` 比对）。**软上限必须与设置页最大选项一致**，否则选了 48 仍被截断 | 官方有等价的全局限流 |
| B5 | HLS 成品移出 `.hls` 缓存目录、规范命名放保存目录；移动成功才删缓存（失败重试 3 次） | `download_manager.dart` | 用户核心诉求：本地播放器可连续播放 | 官方已产出平铺成品 |
| B6 | 不下载弹幕：`download_danmaku` 默认 false，解析跳过 Bangumi 请求 | `download_resolve_manager.dart` | 仅省时间，优先级低 | 无（保持默认关即可） |
| B7 | 下载进度节流 300ms（防 UI 掉帧） | `download_manager.dart` | 简单节流 | 官方已有节流 |

| B8 | 下载按作品名自动建文件夹，视频落于其内；仅解析完成、正式开始下载时才创建（解析阶段不碰文件系统）；删除某作品**全部**下载内容时连带删除该文件夹；目录或文件已不在当前路径则静默跳过。**v14 起与 B15「覆盖同名文件」开关联动**，**v15 起后缀补上播放地址名**：开关关闭（默认）= `作品名【扩展源名（播放地址名）】`（无播放地址名 → `作品名【扩展源名】`，两者都无 → 纯 `作品名`），开关打开 = 纯 `作品名` | `lib/models/download_task.dart`（`sourceName` / `lineName`）、`lib/services/download/download_resolve_manager.dart`、`lib/pages/player/player_page.dart`、`lib/services/download/download_manager.dart` | 关键函数 `_seriesFolderName`：`_overwriteSameName==true` 直接返回 `_sanitizePathPart(title)`；否则按 `src`/`line` 组合 `【扩展源名（播放地址名）】`。`_seriesRoot` 由 saveDir + `_seriesFolderName` 推导（不落库）；`_isSameSeries` 比较 `_seriesFolderName(a)==_seriesFolderName(b)`。**旧任务无 `lineName` → 退化为 v14 的 `作品名【扩展源名】`，目录名不变、向后兼容**。`sourceName` 来自 `job.detail['sourceDisplayName']`（扩展源名），`lineName` 来自 B16 的线路名，两者都随 `toJson/fromJson` 持久化 | 官方把下载按作品聚合进子文件夹 |
| B9 | 禁用官方更新检查/安装：把 `updateInfo?.hasUpdate ?? false` 与 `updateInfo?.forceUpdate ?? false` 强制改为 `false`，启动仍联网取公告但不弹"安装官方版"按钮，从而**避免定制版被官方更新悄悄覆盖**（根因：官方 `update_presenter` 会下载官方安装包覆盖 `D:\AniBaka\baka\baka.exe`）。**v15.5 已补完**：原改动仍会请求 `version.anibaka.com`（该域名 DNS 被投毒成 1.1.1.1，每次进首页白等约 21s 并触发全局网络错误）；现改为 `checkUpdateInfo()` 直接返回「无更新」，彻底不发请求 | `lib/app/update_presenter.dart` | 直接把两处 `hasUpdate/forceUpdate` 置 false；保留公告能力。注意：这是防御性改动，若以后想接受官方更新须改回 | 上游默认开启更新；若官方改为可配置开关则可舍弃 |
| B10 | **签名 URL 过期自动重解析**：HLS 分片下载失败（403/404 等）时自动重新解析播放列表并重试 3 次，按 `localName` 找回新签名 URL 再下载 | `download_manager.dart` | `_downloadHlsAsset` 包 3 次重试：失败清残留 → `_resolveMediaPlaylist` → `planHlsDownload` → 用 `localName` 匹配新 URL → `_downloadHlsAssetOnce` | 上游已处理签名刷新 |
| B11 | **HLS 分片完整性校验**：有 Content-Range 时校验实际长度 == range 长度，无 range 时校验长度 > 0；不符则抛错触发重试，避免半截分片拼进成品 | `download_manager.dart` | 在 `_downloadHlsAssetOnce` 内下载完成后校验，抛异常给上层 3 次重试 | 上游已校验分片长度 |
| B12 | **磁盘满/只读失败告警**：下载异常时识别磁盘空间不足（Windows errorCode 112/19 及消息关键字），通过 `warning` 悬浮提示"磁盘空间不足"并置任务失败，不再静默卡住 | `download_manager.dart` | `_isDiskFull(e)` 判定 + `_warn(...)`（8 秒自动清除的 ValueNotifier）；DioException 与 catch 两个分支都接入 | 上游已有磁盘错误提示 |
| B13 | **音视频分离告警**：检测到播放列表含 `#EXT-X-MEDIA:TYPE=AUDIO`（分离音轨）时一次性提示"该作品音视频分离，当前仅拼接可能无声"，避免静默产出无声文件 | `download_manager.dart` | `_resolveMediaPlaylist` 命中即调 `_warnAudioSeparated()`（一次性）；根因：`hls_offline_remux.dart` 只做分片拼接、无 ffmpeg 混流 | 上游支持 ffmpeg 混流 |
| B14 | **「清除已完成记录」只清列表、绝不删视频文件**（v14 安全加固）：`clearCompleted()` 仅做 `tasks.removeWhere(completed)` + `_notifyAndSave()` + `task.dispose()`，**已移除** `_deleteTaskFiles()` / `_maybeRemoveSeriesDir()` 调用 | `download_manager.dart` | 事故背景：v13 的 clearCompleted 会永久删除 G 盘视频（Dart `File.delete()` 不进回收站），2026-11-04 用户误点致 3 部作品视频全丢且无法找回。删文件的专用入口是 C4「删除下载文件」多选，两者必须严格区分 | 上游 clearCompleted 本身只清记录 |
| B15 | **「覆盖同名文件」开关**（设置页「下载（定制版）」，`Instances.sp` 键 `download_overwrite_same_name`，默认 false）：打开时按 B8 用纯作品名文件夹、HLS 成品与直链下载遇同名文件直接覆盖、同名作品只留一份；关闭时保留旧文件、新成品另存 `xxx_2.ts` | `app_settings_page.dart`（`SwitchListTile`）、`download_manager.dart`（`_overwriteSameName` getter + `_resolveTargetPath`；`_downloadDirectFile` 与 `_downloadHls` 成品落位两处接入） | 覆盖打开时直链下载须**先删旧文件再从 0 字节重下**，否则 `resumePos=旧长度` 会把两次内容拼在一起；HLS 段沿用原有「dst 存在则先删再 move」；关闭时 `_resolveTargetPath` 用 `_2/_3…` 递增探测不冲突文件名 | 官方提供可配置的同名文件策略 |
| B16 | **播放地址名（线路名）注入下载任务**（v15）：把当前选中的线路名（播放器剧集列表里「播放源1 / 播放源2」）带进任务，供 B8 组装文件夹后缀，区分同一扩展源下不同播放地址下载的同名作品 | `lib/pages/player/player_page.dart`（`_showEpisodePicker`）、`lib/services/download/download_resolve_manager.dart`（`_resolveOne`）、`lib/models/download_task.dart` | 链路：`_showEpisodePicker` 取 `content.sourceNames[content.currUrl-1]`（空名回退 `线路 N`；`sourceNames==null` 则不填）→ 写入 `buildDetailData()` 的 `detail['downloadLineName']` → 经 `EpisodeListDialog._submitDownload` 的 `DownloadResolveJob.detail` → `_resolveOne` 读 `job.detail['downloadLineName']` 存进 `DownloadTask.lineName`。下载模式不允许切线路，取打开面板时的 `currUrl` 即可；全仓下载提交入口仅 `episode_list_dialog.dart` 一处 | 官方按线路区分下载目录 |

### C. UI / 交互

| # | 功能 | 涉及文件 | 重放要点 | 舍弃条件 |
|---|------|----------|----------|----------|
| C1 | 「已缓存」等 SnackBar 提示 3 秒自动消失；`showSnackBar` 加 `replace` 参数防堆积 | `lib/utils/toast_utils.dart` | Timer 兜底 + replace 语义 | 官方提示时长已合理 |
| C2 | 下载页长按多选删除：合集页内保留多选；主页完成分组卡长按多选**已回退**（用户明确否决），但 v13 起主页可通过右上角菜单「删除下载文件」进入多选（见 C4/C5） | `lib/pages/player/download_page.dart` | 勿把主页「长按分组卡」多选加回来；菜单入口可以保留 | 官方提供删除入口 |
| C3 | 下载前可选保存路径（FilePicker，默认目录记忆，键 `download_default_dir`） | `episode_list_dialog.dart`、`app_settings_page.dart` | 注意 file_picker 11.x 的 `getDirectoryPath(initialDirectory:)` 静态 API | 官方支持选路径 |
| C4 | 下载管理界面右上角弹出菜单新增「删除下载文件」项，点击后进入选择任务状态（效果等同长按任务），便于不熟悉长按的用户删除 | `lib/pages/player/download_page.dart` | `normalAppBar` 的 `PopupMenuItem` 加 `value:'delete_files'`，`onSelected` 调 `_enterSelectModeEmpty()`（仅置 `_selectMode=true`）；主页面与 `_AnimeGroupPage` 均需支持 | 官方提供删除入口 |
| C5 | 多选状态栏操作按钮为文字；**v15 起主页「全选」拆成两个**：「全选（下载中）」与「全选（已完成）」，各自只在对应类别有任务时显示（`if (_active.isNotEmpty)` / `if (_completedTasks.isNotEmpty)`），且只增删该类别的选中 id，互不影响；删除按钮按选中 id 统一处理 | `lib/pages/player/download_page.dart` | `_completedTasks` getter 从 `_completed` 分组展开；`_toggleSelectAllActive` / `_toggleSelectAllCompleted` 各自按类别 toggle。主页「已完成」分组卡 `_AnimeGroupCard` 在 v15 也支持多选（Checkbox + 整组勾选 / 长按选中），否则「全选（已完成）」无可见效果 | 官方用文字按钮 |
| C6 | **多选界面取消到一项不剩时仍停留**（v14）：不会自动退回普通界面，退出只能手动按左上角关闭键或 Esc。`_EscapeExitWrapper` 只在多选态挂 `SingleActivator(LogicalKeyboardKey.escape)` → `_exitSelectMode()`，非多选态原样返回 child 以免拦截对话框的 Esc | `lib/pages/player/download_page.dart` | 删掉两处 `_toggleSelect` 里的 `if (_selectedIds.isEmpty) _selectMode = false;`；主页与 `_AnimeGroupPage` 的 `build` 先把 Scaffold 赋给 `page` 变量，再包一层 `_EscapeExitWrapper(enabled:_selectMode, onExit:_exitSelectMode, child:page)`；需 `import 'package:flutter/services.dart'` | 官方提供等价停留/退出逻辑 |
| C7 | **「已完成」作品详情界面只显示已完成任务**（v15）：`_AnimeGroupPage._readTasks` 增加 `task.status == DownloadStatus.completed` 过滤，下载中 / 等待中 / 失败的任务不再混入 | `lib/pages/player/download_page.dart` | 修复前该页按 `task.title == widget.title` 取全部同名任务，导致点「已完成」分组进去看到一排等待中 / 下载中任务 | 官方按状态分组 |
| C8 | **「清除已完成记录」菜单文案改「清除已完成记录（非删除）」+ 二次确认弹窗**（v15）：点击弹 `AlertDialog`，内容「【清除已完成记录】将清除已完成的全部下载任务，且无法还原，是否继续」，底部「否 / 是」按钮，确认后才调 `clearCompleted()` | `lib/pages/player/download_page.dart` | `_confirmClearCompleted()`：`showDialog<bool>` → `if (confirmed == true) await _service.clearCompleted()`。配合 B14（只清记录）避免用户误解为删视频 | 官方有等价确认 |
| C9 | **「已完成」作品详情界面右上角三点菜单**（v15）：与下载管理主页同款 `PopupMenuButton`，含「删除下载文件」项，点击进入多选；多选栏「全选」仅在当前界面有任务时显示（`if (_tasks.isNotEmpty)`），另有「删除」 | `lib/pages/player/download_page.dart` | `_AnimeGroupPageState` 补 `_enterSelectModeEmpty()`；normalAppBar 加 `title: _titleWithHint(...)` 与 `actions: [PopupMenuButton]` | 官方提供删除入口 |
| C10 | **标题右侧长按提示**（v15）：下载管理主页与「已完成」作品详情界面标题后都加「【提示：长按下载任务可进入多选】」 | `lib/pages/player/download_page.dart` | 共用 `_titleWithHint(context, title)`，用 `FittedBox(fit: BoxFit.scaleDown)` 包 `Row`，防窄窗口下 AppBar 标题溢出 | 官方有等价引导 |

### D. 构建

| # | 功能 | 涉及文件 | 重放要点 | 舍弃条件 |
|---|------|----------|----------|----------|
| D1 | `.gitignore` 例外 `!local_deps/ech_http/src/cacert.pem` | `.gitignore` | **编译必需**：上游 CMake 读取该文件，`*.pem` 规则会吞掉它导致 CI 失败。上游若已修则无需 | 上游已修复忽略规则 |

### E. 已废弃/回退的改动（勿重放）

- 主页已完成分组卡长按多选（v4 引入，v6 回退）。
- 解析暂停/继续（v5-v8 引入，v11 彻底删除：暂停状态残留会使后续解析永久卡死，且暂停粒度差——批内 4 集会跑完才检查，实用性低）。

## 历史教训（重放时注意）

1. `SnackBarAction` 用到时记得导入 `package:flutter/material.dart`。
2. file_picker 11.x API 是静态方法，无 `.platform`。
3. 逐文件走 Contents API 上传时 `sha` 必须取自目标分支的最新文件，否则 409。
4. CI 报 `Building native assets failed` 多半是 prebuilt 钩子的 stderr 被 Flutter 吞掉，先查 `.gitignore` 误伤（`git check-ignore -v <file>`）。
5. **「清除已完成记录」这类清列表菜单绝不能顺手删本地文件**：Dart `File.delete()` 是永久删除、不进回收站，误点不可逆（2026-11-04 事故）。删文件只走 C4 多选入口，且带确认框。
6. 恢复 SOP 里「上游 main 为底重放」时，注意 PR #36 分支的修复（clearCompleted 只清记录、成品同名不覆盖）**并未**全部合进 `custom-windows-build`；两边差异以本清单 + 实际部署分支源码为准。
7. HLS 并发的**软上限常量与设置页最大选项必须一致**：v14 软上限 32，若只把设置页加回 48 而不同步 `_kMaxHlsConcurrency`，`_hlsConcurrency` 仍会把 48 截断成 32，改动等于无效。改选项务必同步改软上限。
8. 「扩展源名」≠「播放地址名」：前者是 `sourceDisplayName`（如「七色番」），后者是播放器剧集列表里的线路名（「播放源1 / 播放源2」，来自 `content.sourceNames[currUrl-1]`）。同一扩展源可分多个播放地址，只按扩展源名建文件夹会让不同播放地址下载的同名作品互相覆盖——这正是 v15 补 `lineName` 的原因。

---

## 投稿记录（2026-11-01）

- 已将全部 11 项代码改动整理投稿上游：<https://github.com/AniBakaBaka/AniBaka/pull/36>（PR #36，分支 `a806330/AniBaka-1` 的 `download-improvements`，基于上游 main `e835a0aa`，单提交，LF 行尾）。
- **若上游合并 PR**：官方更新即自带全部定制功能，恢复流程简化为"确认新版本已包含哪些项 + 重放残余"。
- **基线勘误**：本仓库首个提交 `c6585b9ae7` 并非上游原版快照，而是中间状态（含部分定制），因此 `customizations-diff.md`（基线→HEAD）**不能**当作全量定制 diff 使用。权威全量 diff = 上游 main → HEAD，可用 fork 仓库对比：`GET /repos/a806330/AniBaka-1/compare/main...download-improvements`（PR #36 即此内容）。恢复定制时以上游最新 main 为底重放本清单各项，勿直接套用 customizations-diff.md。
- 注意：`download_task.dart`（saveDir 字段）与 `update_dialog.dart`（定制提示）的改动包含在本仓库基线中（早于 32 个提交），其中 saveDir 属于 C3 一部分随 PR 提交，update_dialog 的定制提示为纯个人化内容、不投稿。


---

## F. 网络与更新加固（v15.5，2026-11-07）

背景：用户反馈「搜索番剧弹网络请求失败 / 下载变慢」，且明确「搜索问题是现在才有的，之前是软件更新的网络问题」。实测定位见项目记忆，结论分三层：Baka 官方服务端 521/502 与域名 DNS 污染（外部，本地修不了）、dev-sidar 之类本机代理软件接管全局流量并给出错误 DNS（外部，但可由 Baka 侧免疫）、Baka 自身 3 处瑕疵（本组改动）。

| # | 功能 | 涉及文件 | 重放要点 | 舍弃条件 |
|---|------|----------|----------|----------|
| F1 | **自动绕开本机回环代理**：`SystemProxyService` 检测环境变量代理 / 注册表代理是否指向 `127.*`、`localhost`、`::1`，是则 `findProxy` 恒返回 `DIRECT`；远程代理仍照常跟随并保留 `'; DIRECT'` 失败回退 | `lib/core/system_proxy.dart` | 新增 `bypassLoopbackProxy = true`、`_envProxyLoopback` / `_registryProxyLoopback` 两个标志与 `_isLoopbackServer()`；`initialize()` 里在解析完注册表代理后计算标志；**`SystemProxyHttpOverrides` 仍要安装**（否则第三方库自建的 HttpClient 不受控）。背景：dev-sidecar 装后 `ProxyEnable=1 / 127.0.0.1:31181` 且注入 `HTTP_PROXY`，Baka 全部请求（含 `download_manager.dart` 的 Dio）被接管，其 DNS 把多个番剧源解析到 `1.1.1.1:443` 造成 21–46s 超时 | 官方提供「忽略系统代理」开关，或本机不再装本地代理软件 |
| F2 | **B9 补完：彻底不发官方版本检查请求**：`checkUpdateInfo()` 在 `disableOfficialUpdateCheck = true` 时直接返回 `UpdateInfo(hasUpdate:false, ...)`，不再请求 `https://version.anibaka.com/`；公告获取 `getPostDetail(1)` 照常保留 | `lib/app/update_presenter.dart` | 用**顶层 const bool + if** 短路，不要直接删原逻辑（会产生 dead_code / unused_element 警告，CI `flutter analyze` 可能失败）；`localVersion` 提前到网络请求之前。B9 原改动只把 hasUpdate/forceUpdate 置 false，请求仍发 | 官方把更新检查做成可关闭开关 |
| F3 | **搜索失败显示具体原因**：单源失败在 `_drainSearches` 的 catch 里弹「搜索失败（源名）：<简要错误>」；聚合搜索全失败时统计 `failures` 并提示失败源数量与首个错误 | `lib/pages/search/search_controller.dart` | 需 `import 'package:baka/utils/toast_utils.dart'`；新增 `_briefError()` 把 TimeoutException / SocketException / HandshakeException 映射为中文短句。原实现只 `debugPrint` 并把结果置空，用户只看到「未找到结果」+ 全局红条，无法定位 | 官方自带逐源错误展示 |

### v15.5 部署信息
- 提交：见 `custom-windows-build` 分支 HEAD（本组 3 个 Dart 文件 + 本文档，单次 Git Data API 提交）。
- 构建：workflow `402046819` dispatch，产物 `baka-windows-x64`。
- 验证：`app.so` SHA256 与产物一致 + 启动不崩溃；逻辑层可用 `_isLoopbackServer` 的单元对照（回环/远程代理地址）核实。
- 不改网络超时、不动 DoH/ECH 设置（默认关闭，且默认端点 `https://1.1.1.1/dns-query` 在当前网络下不可用，开启反而更糟）。

### 重放注意
- F1 只绕过**本机**代理；若恢复定制时上游已重写 `system_proxy.dart`，按语义重放而非照抄代码。
- 恢复 SOP 核对清单时，B9 现在包含 F2，勿只做「置 false」两行。


---

## G. 搜索结果按标题归一组（v15.6，2026-11-08）

背景：Hanime1 系列镜像站（自定义源 `id=hanimeone`）每个 `/watch?v=` 都是一个独立视频，搜索同一作品会返回「巨乳女土官・洗脳催眠 1」「… 2」两张独立作品卡片。`anx-rule/2` 规则引擎**没有分组/聚合 op**：`searchList` 逐元素产出 `Series`，`_PipelineContext.addSeries` 只按 `seriesId`（链接 URL）去重，`nameFilter` 只能改标题不能改 id，`replace` 的 replacement 是字面量（Dart `replaceAll` 不支持 `$1` 反向引用），界面层也不做同名归并。站点侧也没有「系列页」：播放页的 `video-playlist-wrapper` 是上传者的全部视频（实测 155 个），不是同一作品的剧集。因此**只改扩展源规则无法合并**，改在 Dart 层。

| # | 功能 | 涉及文件 | 重放要点 | 舍弃条件 |
|---|------|----------|----------|----------|
| G1 | **标题归一分组合并**：搜索结果里把标题末尾的集数后缀（` 1` / ` 2` / `第X集` / `第X話` / `EP.X` / `Part X`）去掉，同名且组内 ≥2 条才合并成一张卡片；被合并掉的其它集链接编码进 `seriesId` 的 `#baka_group=` fragment，详情阶段解码生成「第1集 / 第2集」 | `lib/source/source_adapter.dart` | 白名单 `static const Set<String> _titleGroupingSourceIds = {'hanimeone'}` **只对这一个源生效**，其它源完全不受影响。新增 `_groupSeriesByTitle` / `_decodeGroupedSeries` / `_detailSources`；`search()` 两个返回点都要过 `_groupSeriesByTitle`；`getPlaybackCatalog` 改走 `_detailSources`。安全措施：**无集数后缀的条目不参与分组**（避免「作品」与「作品 2」误并）、`base.length < 2` 不分组、组内 <2 不合并、集数按数字升序、`Uri.decodeComponent` 失败回退原 detail 管线 | 官方在规则引擎提供 group/merge op，或站点改为按系列返回结果 |

### 设计要点
- **不改规则 JSON、不改 GUI、不改 `SourceRule` 模型**：开关按 `rule.id` 白名单判断，用户以后在图源管理页编辑/保存这条规则也不会丢失功能；`Recipes.expand` 用 `copyWith` 保留 id。
- **跨会话稳定**：其它集的 URL 直接编进 `seriesId` 字符串（`Uri.encodeComponent` + `#baka_group=` fragment），不依赖内存 Map；历史记录、下载任务重启后仍能还原剧集。fragment 不会被 HTTP 请求发到服务器，`play` 阶段用的 `episodeId` 是各集干净 URL。
- **调用链已核对**：`source_repository.buildPlaybackRequest` 用 `item.id`、`playback_content` 用 `data['seriesUrl']`（= `seriesId`）、`player_page` 用 `data['seriesId'] ?? data['seriesUrl']`，均原样传递，fragment 不会丢。
- **不采用**「把搜索页所有 href 改成同一值、靠按 ID 去重强行合成一张」的规则层偏方：会把一次搜索里的不同作品错合并，且 `fetch` 走 Dio 拿不到 JS 渲染后的结果列表，其它集会丢失。

### 验证
- 本机无 Dart SDK，提交前用状态机做全文 + 新增块的括号/字符串平衡检查，并用 Python 复刻分组算法做 8 组回归（`1/2` 合并、乱序排序、`第X集`、`EP.X`、不同作品不合并、无后缀不吞并、单条不合并、`1080P/720P` 不误判）与编码往返，全部通过；最终以 CI 构建 + 安装后 `app.so` SHA256 与启动为准。
- 端到端：搜索「巨乳女土官」应只出一张「巨乳女土官・洗脳催眠」卡片，进入详情可见「第1集 / 第2集」，两集都能播放/下载。

### 重放注意
- 若上游重写 `source_adapter.dart`，按语义重放（白名单 + 搜索分组 + 详情解码三处），不要照抄行号。
- 白名单新增源时只改 `_titleGroupingSourceIds` 一行；注意该源的标题是否真以「集数」结尾，避免误并。
