# 定制改动完整 diff（基线 c6585b9ae7 → HEAD v11）

> 由 `GET /repos/a806330/AniBaka/compare/c6585b9ae7...HEAD` 导出，仅作快速参考。
> 权威版本随时可通过同一 API 重新生成；本文件不包含 cacert.pem（上游自带，重放时只需保留 .gitignore 例外规则，见 CUSTOMIZATIONS.md D1）。

#### FILE: .gitignore (+4/-0)
```diff
@@ -33,6 +33,10 @@
 *.p12
 *.pfx
 *.pem
+# Not a credential: Mozilla CA root bundle compiled into the ech_http native
+# bridge via CMakeLists.txt `file(READ ... cacert.pem ...)`. Without it the
+# native-assets hook fails on CI with an opaque "Building native assets failed".
+!local_deps/ech_http/src/cacert.pem
 *.key
 **/key.properties
 **/local.properties
```

#### FILE: lib/app/app_runtime.dart (+5/-0)
```diff
@@ -187,8 +187,13 @@ class AppRuntime {
     Get.put(party, permanent: true);
     Get.put(links, permanent: true);
     Get.put(mediaSession, permanent: true);
+    // 应用启动即初始化下载服务：加载任务、清理失效记录并压实存储，
+    // 不等用户打开下载管理页才执行。
+    await downloads.init();
     downloads.onCompleted = (task) => showSnackBar(
       '已缓存 ${task.title}',
+      duration: const Duration(seconds: 3),
+      replace: true,
       action: SnackBarAction(
         label: '前往缓存中心',
         onPressed: () {
```

#### FILE: lib/app/baka_app.dart (+7/-1)
```diff
@@ -7,6 +7,7 @@ import 'dart:ui' show PointerDeviceKind;
 import 'package:baka/app_state.dart';
 import 'package:baka/instance.dart';
 import 'package:baka/pages/home/home_page.dart';
+import 'package:baka/services/download/download_resolve_manager.dart';
 import 'package:baka/pages/library/library_page.dart';
 import 'package:baka/pages/login/login_page.dart';
 import 'package:baka/pages/mine/mine_page.dart';
@@ -104,7 +105,12 @@ class BakaApp extends StatelessWidget {
                     mediaQuery.disableAnimations ||
                     appState.reduceVisualEffects,
               ),
-              child: child ?? const SizedBox.shrink(),
+              child: Stack(
+                children: [
+                  child ?? const SizedBox.shrink(),
+                  const DownloadResolveBanner(),
+                ],
+              ),
             );
           }),
         );
```

#### FILE: lib/pages/player/download_page.dart (+256/-46)
```diff
@@ -26,6 +26,8 @@ class _DownloadManagerPageState extends State<DownloadManagerPage> {
   final _service = downloads;
   List<DownloadTask> _active = [];
   List<MapEntry<String, List<DownloadTask>>> _completed = [];
+  bool _selectMode = false;
+  final Set<String> _selectedIds = {};
 
   @override
   void initState() {
@@ -57,29 +59,109 @@ class _DownloadManagerPageState extends State<DownloadManagerPage> {
     _completed = grouped.entries.toList(growable: false);
   }
 
+  // ---- 多选删除 ----
+
+  void _enterSelectMode(String id) {
+    setState(() {
+      _selectMode = true;
+      _selectedIds.add(id);
+    });
+  }
+
+  void _toggleSelect(String id) {
+    setState(() {
+      if (!_selectedIds.remove(id)) _selectedIds.add(id);
+      if (_selectedIds.isEmpty) _selectMode = false;
+    });
+  }
+
+  void _exitSelectMode() {
+    setState(() {
+      _selectMode = false;
+      _selectedIds.clear();
+    });
+  }
+
+  bool get _allActiveSelected =>
+      _active.isNotEmpty && _active.every((t) => _selectedIds.contains(t.id));
+
+  void _toggleSelectAll() {
+    setState(() {
+      if (_allActiveSelected) {
+        _selectedIds.clear();
+      } else {
+        _selectedIds
+          ..clear()
+          ..addAll(_active.map((t) => t.id));
+      }
+    });
+  }
+
+  Future<void> _deleteSelected() async {
+    if (_selectedIds.isEmpty) return;
+    final count = _selectedIds.length;
+    final confirmed = await confirmDeleteDialog(
+      context,
+      '确定要删除所选的 $count 项吗？正在下载的任务会被停止，本地文件将被删除且无法恢复。',
+    );
+    if (confirmed != true || !mounted) return;
+    final ids = _selectedIds.toSet();
+    for (final task in _service.tasks.toList()) {
+      if (ids.contains(task.id)) _service.delete(task);
+    }
+    _exitSelectMode();
+  }
+
   @override
   Widget build(BuildContext context) {
     final theme = Theme.of(context);
 
-    return Scaffold(
-      appBar: AppBar(
-        automaticallyImplyLeading: !widget.embedded,
-        title: Text(widget.embedded ? '下载管理' : '缓存'),
-        actions: [
-          PopupMenuButton<String>(
-            onSelected: (val) {
-              if (val == 'pause_all') _service.pauseAll();
-              if (val == 'resume_all') _service.resumeAll();
-              if (val == 'clear_completed') _service.clearCompleted();
-            },
-            itemBuilder: (context) => const [
-              PopupMenuItem(value: 'pause_all', child: Text('全部暂停')),
-              PopupMenuItem(value: 'resume_all', child: Text('全部继续')),
-              PopupMenuItem(value: 'clear_completed', child: Text('清除已完成记录')),
-            ],
-          ),
-        ],
+    final normalAppBar = AppBar(
+      automaticallyImplyLeading: !widget.embedded,
+      title: Text(widget.embedded ? '下载管理' : '缓存'),
+      actions: [
+        PopupMenuButton<String>(
+          onSelected: (val) {
+            if (val == 'pause_all') _service.pauseAll();
+            if (val == 'resume_all') _service.resumeAll();
+            if (val == 'clear_completed') _service.clearCompleted();
+          },
+          itemBuilder: (context) => const [
+            PopupMenuItem(value: 'pause_all', child: Text('全部暂停')),
+            PopupMenuItem(value: 'resume_all', child: Text('全部继续')),
+            PopupMenuItem(value: 'clear_completed', child: Text('清除已完成记录')),
+          ],
+        ),
+      ],
+    );
+
+    final selectAppBar = AppBar(
+      leading: IconButton(
+        icon: const Icon(Icons.close_rounded),
+        tooltip: '退出多选',
+        onPressed: _exitSelectMode,
       ),
+      title: Text('已选 ${_selectedIds.length} 项'),
+      actions: [
+        IconButton(
+          tooltip: '全选 / 取消全选',
+          icon: Icon(
+            _allActiveSelected
+                ? Icons.check_box_rounded
+                : Icons.check_box_outline_blank_rounded,
+          ),
+          onPressed: _active.isEmpty ? null : _toggleSelectAll,
+        ),
+        IconButton(
+          tooltip: '删除所选',
+          icon: const Icon(Icons.delete_outline_rounded),
+          onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
+        ),
+      ],
+    );
+
+    return Scaffold(
+      appBar: _selectMode ? selectAppBar : normalAppBar,
       body: _active.isEmpty && _completed.isEmpty
           ? Center(
               child: Column(
@@ -130,7 +212,14 @@ class _DownloadManagerPageState extends State<DownloadManagerPage> {
                   index--;
                   if (index < _active.length) {
                     final task = _active[index];
-                    return _TaskCard(key: ValueKey(task.id), task: task);
+                    return _TaskCard(
+                      key: ValueKey(task.id),
+                      task: task,
+                      selectMode: _selectMode,
+                      selected: _selectedIds.contains(task.id),
+                      onToggle: () => _toggleSelect(task.id),
+                      onLongPress: () => _enterSelectMode(task.id),
+                    );
                   }
                   index -= _active.length;
                 }
@@ -174,6 +263,29 @@ Widget _dismissBackground(ThemeData theme) {
   );
 }
 
+Future<bool?> confirmDeleteDialog(BuildContext context, String message) {
+  return showDialog<bool>(
+    context: context,
+    builder: (context) => AlertDialog(
+      title: const Text('删除下载'),
+      content: Text(message),
+      actions: [
+        TextButton(
+          onPressed: () => Navigator.pop(context, false),
+          child: const Text('取消'),
+        ),
+        TextButton(
+          onPressed: () => Navigator.pop(context, true),
+          child: Text(
+            '删除',
+            style: TextStyle(color: Theme.of(context).colorScheme.error),
+          ),
+        ),
+      ],
+    ),
+  );
+}
+
 class _Thumbnail extends StatelessWidget {
   const _Thumbnail({this.url});
 
@@ -208,8 +320,19 @@ class _Thumbnail extends StatelessWidget {
 
 class _TaskCard extends StatelessWidget {
   final DownloadTask task;
-
-  const _TaskCard({required this.task, super.key});
+  final bool selectMode;
+  final bool selected;
+  final VoidCallback? onToggle;
+  final VoidCallback? onLongPress;
+
+  const _TaskCard({
+    required this.task,
+    super.key,
+    this.selectMode = false,
+    this.selected = false,
+    this.onToggle,
+    this.onLongPress,
+  });
 
   void _onTap(BuildContext context) {
     final service = downloads;
@@ -265,13 +388,22 @@ class _TaskCard extends StatelessWidget {
 
     return Dismissible(
       key: ValueKey('dismiss_${task.id}'),
-      direction: DismissDirection.endToStart,
+      // 多选模式下禁用右滑删除，避免与勾选状态冲突。
+      direction: selectMode
+          ? DismissDirection.none
+          : DismissDirection.endToStart,
       onDismissed: (_) => downloads.delete(task),
       background: _dismissBackground(theme),
       child: ValueListenableBuilder<DownloadStatus>(
         valueListenable: task.statusNotifier,
         builder: (context, status, _) {
-          final (statusText, actionIcon) = _statusInfo(status);
+          // HLS 任务在分片全部下完后进入拼接阶段（进度定格 0.99），
+          // 显示“合并中”避免看起来像卡死。
+          final merging =
+              status == DownloadStatus.downloading && task.progress >= 0.99;
+          final (statusText, actionIcon) = merging
+              ? ('合并中', Icons.pause_rounded)
+              : _statusInfo(status);
           final statusColor = _statusColor(theme, status);
 
           return Container(
@@ -282,11 +414,19 @@ class _TaskCard extends StatelessWidget {
             ),
             clipBehavior: Clip.antiAlias,
             child: InkWell(
-              onTap: () => _onTap(context),
+              onTap: selectMode ? onToggle : () => _onTap(context),
+              onLongPress: onLongPress,
               child: Padding(
                 padding: const EdgeInsets.all(10),
                 child: Row(
                   children: [
+                    if (selectMode) ...[
+                      Checkbox(
+                        value: selected,
+                        onChanged: (_) => onToggle?.call(),
+                      ),
+                      const SizedBox(width: 4),
+                    ],
                     _Thumbnail(url: task.thumbnail),
                     const SizedBox(width: 12),
                     Expanded(
@@ -373,25 +513,9 @@ class _AnimeGroupCard extends StatelessWidget {
   const _AnimeGroupCard({required this.title, required this.tasks, super.key});
 
   Future<bool?> _confirmDelete(BuildContext context) {
-    return showDialog<bool>(
-      context: context,
-      builder: (context) => AlertDialog(
-        title: const Text('删除合集'),
-        content: Text('确定要删除《$title》的所有已下载剧集吗？这会清除本地文件且无法恢复。'),
-        actions: [
-          TextButton(
-            onPressed: () => Navigator.pop(context, false),
-            child: const Text('取消'),
-          ),
-          TextButton(
-            onPressed: () => Navigator.pop(context, true),
-            child: Text(
-              '删除',
-              style: TextStyle(color: Theme.of(context).colorScheme.error),
-            ),
-          ),
-        ],
-      ),
+    return confirmDeleteDialog(
+      context,
+      '确定要删除《$title》的所有已下载剧集吗？这会清除本地文件且无法恢复。',
     );
   }
 
@@ -478,6 +602,8 @@ class _AnimeGroupPage extends StatefulWidget {
 class _AnimeGroupPageState extends State<_AnimeGroupPage> {
   final _service = downloads;
   List<DownloadTask> _tasks = [];
+  bool _selectMode = false;
+  final Set<String> _selectedIds = {};
 
   @override
   void initState() {
@@ -501,6 +627,59 @@ class _AnimeGroupPageState extends State<_AnimeGroupPage> {
 
   void _onTasksChanged() => setState(_readTasks);
 
+  // ---- 多选删除 ----
+
+  void _enterSelectMode(String id) {
+    setState(() {
+      _selectMode = true;
+      _selectedIds.add(id);
+    });
+  }
+
+  void _toggleSelect(String id) {
+    setState(() {
+      if (!_selectedIds.remove(id)) _selectedIds.add(id);
+      if (_selectedIds.isEmpty) _selectMode = false;
+    });
+  }
+
+  void _exitSelectMode() {
+    setState(() {
+      _selectMode = false;
+      _selectedIds.clear();
+    });
+  }
+
+  bool get _allSelected =>
+      _tasks.isNotEmpty && _tasks.every((t) => _selectedIds.contains(t.id));
+
+  void _toggleSelectAll() {
+    setState(() {
+      if (_allSelected) {
+        _selectedIds.clear();
+      } else {
+        _selectedIds
+          ..clear()
+          ..addAll(_tasks.map((t) => t.id));
+      }
+    });
+  }
+
+  Future<void> _deleteSelected() async {
+    if (_selectedIds.isEmpty) return;
+    final count = _selectedIds.length;
+    final confirmed = await confirmDeleteDialog(
+      context,
+      '确定要删除所选的 $count 集吗？本地文件将被删除且无法恢复。',
+    );
+    if (confirmed != true || !mounted) return;
+    final ids = _selectedIds.toSet();
+    for (final task in _service.tasks.toList()) {
+      if (ids.contains(task.id)) _service.delete(task);
+    }
+    _exitSelectMode();
+  }
+
   @override
   Widget build(BuildContext context) {
     if (_tasks.isEmpty) {
@@ -514,12 +693,43 @@ class _AnimeGroupPageState extends State<_AnimeGroupPage> {
       });
     }
     return Scaffold(
-      appBar: AppBar(title: Text(widget.title)),
+      appBar: _selectMode
+          ? AppBar(
+              leading: IconButton(
+                icon: const Icon(Icons.close_rounded),
+                tooltip: '退出多选',
+                onPressed: _exitSelectMode,
+              ),
+              title: Text('已选 ${_selectedIds.length} 集'),
+              actions: [
+                IconButton(
+                  tooltip: '全选 / 取消全选',
+                  icon: Icon(
+                    _allSelected
+                        ? Icons.check_box_rounded
+                        : Icons.check_box_outline_blank_rounded,
+                  ),
+                  onPressed: _tasks.isEmpty ? null : _toggleSelectAll,
+                ),
+                IconButton(
+                  tooltip: '删除所选',
+                  icon: const Icon(Icons.delete_outline_rounded),
+                  onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
+                ),
+              ],
+            )
+          : AppBar(title: Text(widget.title)),
       body: ListView.builder(
         padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
         itemCount: _tasks.length,
-        itemBuilder: (context, i) =>
-            _TaskCard(key: ValueKey(_tasks[i].id), task: _tasks[i]),
+        itemBuilder: (context, i) => _TaskCard(
+          key: ValueKey(_tasks[i].id),
+          task: _tasks[i],
+          selectMode: _selectMode,
+          selected: _selectedIds.contains(_tasks[i].id),
+          onToggle: () => _toggleSelect(_tasks[i].id),
+          onLongPress: () => _enterSelectMode(_tasks[i].id),
+        ),
       ),
     );
   }
```

#### FILE: lib/pages/player/player_page.dart (+1/-0)
```diff
@@ -773,6 +773,7 @@ class _PlayerPageState extends State<PlayerPage>
           _fullscreen && (downloadMode || !Instances.isDesktopPlatform),
       postDetail: content.buildDetailData(),
       urlResolver: content.resolveEpisodeUrl,
+      resolveTarget: content,
       startInDownloadMode: downloadMode,
       currentLineIndex: downloadMode ? null : content.currUrl,
       sourceNames: downloadMode ? null : content.sourceNames,
```

#### FILE: lib/pages/setting/app_settings_page.dart (+17/-2)
```diff
@@ -363,7 +363,15 @@ class _AppSettingsPageState extends State<AppSettingsPage> {
               icon: Icons.align_horizontal_left_rounded,
               title: '同时下载任务数',
               value: Instances.sp.getInt('download_max_concurrent') ?? 3,
-              options: const {1: '1', 2: '2', 3: '3', 5: '5'},
+              options: const {
+                1: '1',
+                2: '2',
+                3: '3',
+                4: '4',
+                6: '6',
+                8: '8',
+                10: '10',
+              },
               onChanged: (v) async {
                 await Instances.sp.setInt('download_max_concurrent', v);
                 setState(() {});
@@ -373,7 +381,14 @@ class _AppSettingsPageState extends State<AppSettingsPage> {
               icon: Icons.speed_rounded,
               title: 'HLS 分片并发数',
               value: Instances.sp.getInt('download_hls_concurrency') ?? 16,
-              options: const {4: '4', 8: '8', 16: '16', 24: '24'},
+              options: const {
+                4: '4',
+                8: '8',
+                16: '16',
+                24: '24',
+                32: '32',
+                48: '48',
+              },
               onChanged: (v) async {
                 await Instances.sp.setInt('download_hls_concurrency', v);
                 setState(() {});
```

#### FILE: lib/services/download/download_manager.dart (+198/-37)
```diff
@@ -16,6 +16,36 @@ import 'package:saver_gallery/saver_gallery.dart';
 
 late DownloadService downloads;
 
+///  async 信号量：跨任务共享的 HLS 分片下载并发上限。
+///
+/// 每个任务内部有 N 个 worker，若不限流，6 任务 × 32 分片 = 192 路并发请求
+/// 会把主 isolate 的事件循环塞满，导致界面明显卡顿。全局闸门把同时在飞的
+/// 分片请求压回设置值。
+class _Semaphore {
+  _Semaphore(this.max);
+  final int max;
+  int _held = 0;
+  final _waiters = <void Function()>[];
+
+  Future<void> acquire() {
+    if (_held < max) {
+      _held++;
+      return Future<void>.value();
+    }
+    final c = Completer<void>();
+    _waiters.add(c.complete);
+    return c.future;
+  }
+
+  void release() {
+    if (_waiters.isNotEmpty) {
+      _waiters.removeAt(0)();
+    } else if (_held > 0) {
+      _held--;
+    }
+  }
+}
+
 class DownloadService {
   static const String _storageKey = 'download_tasks';
   DownloadService();
@@ -68,6 +98,34 @@ class DownloadService {
     }
   }
 
+  /// 是否在下载完成后一并缓存弹幕（默认关闭，只下载视频）。
+  bool get _downloadDanmaku {
+    try {
+      return Instances.sp.getBool('download_danmaku') ?? false;
+    } catch (_) {
+      return false;
+    }
+  }
+
+  /// 跨任务共享的 HLS 分片并发闸门（首次使用时按设置值创建）。
+  ///
+  /// 上限压到 16：分片请求的处理（TLS 解密、分块事件）全在主 isolate，
+  /// 32 路以上会挤占 UI 帧调度造成明显掉帧；16 路足以跑满常见带宽。
+  _Semaphore? _hlsGate;
+  _Semaphore get _gate =>
+      _hlsGate ??= _Semaphore(_hlsConcurrency > 16 ? 16 : _hlsConcurrency);
+
+  /// 分片拼接（remux）串行锁：拼接是磁盘大块读写，多个一起跑会形成
+  /// 磁盘寻道风暴（系统级卡顿），串行反而总吞吐更高。
+  Future<void> _enqueueRemux(Future<void> Function() action) {
+    final prev = _remuxLock.catchError((_) {});
+    final completer = Completer<void>();
+    _remuxLock = completer.future;
+    return prev.then((_) => action()).whenComplete(completer.complete);
+  }
+
+  Future<void> _remuxLock = Future<void>.value();
+
   Future<void> init() =>
       _initialization ??= AppStorage.open(AppStorage.downloadTasksBoxName)
           .then((_) {
@@ -113,11 +171,38 @@ class DownloadService {
     try {
       final storedTasks = AppStorage.downloadTasksBox.get(_storageKey);
       if (storedTasks is List) {
-        _tasks.value = _restoreTasks(storedTasks);
+        var removed = 0;
+        final restored = _restoreTasks(storedTasks);
+        // 清理无效任务：失败的任务，以及记录指向的本地文件已不存在的
+        // 任务（文件被外部移动/删除）。waiting 且尚未落盘的不受影响。
+        final valid = <DownloadTask>[];
+        for (final task in restored) {
+          final path = task.filePath;
+          final fileGone =
+              path != null && path.isNotEmpty && !File(path).existsSync();
+          if (task.status == DownloadStatus.failed || fileGone) {
+            removed++;
+            task.dispose();
+            continue;
+          }
+          valid.add(task);
+        }
+        if (removed > 0) {
+          debugPrint('DownloadService: dropped $removed stale task(s)');
+        }
+        _tasks.value = valid;
         for (final task in tasks) {
           if (task.status == DownloadStatus.waiting) _waiting[task.id] = task;
         }
+        if (removed > 0) _scheduleSave();
       }
+      // Hive 是追加写：任务状态每次变化都会留下一帧死数据，文件只增不减。
+      // 启动时压实一次，避免长期使用后无谓膨胀。
+      unawaited(
+        (AppStorage.downloadTasksBox as dynamic)
+            .compact()
+            .catchError((_) {}),
+      );
     } catch (e) {
       if (kDebugMode) debugPrint('DownloadService load error: $e');
     }
@@ -277,7 +362,10 @@ class DownloadService {
 
   void _processQueue() {
     if (_closed || _waiting.isEmpty) return;
-    while (_activeRuns.length < _maxConcurrent && _waiting.isNotEmpty) {
+    // 合并中的任务不占下载槽：只有还在跑网络下载的任务计入并发。
+    int activeDownloads() =>
+        _activeRuns.where((run) => !run.merging).length;
+    while (activeDownloads() < _maxConcurrent && _waiting.isNotEmpty) {
       final task = _waiting.remove(_waiting.keys.first)!;
       _running = _downloadFile(task);
     }
@@ -363,7 +451,7 @@ class DownloadService {
       }
       _throwIfCancelled(cancelToken);
       final filePath = task.kind == DownloadTaskKind.hls
-          ? await _downloadHls(task, cancelToken)
+          ? await _downloadHls(task, cancelToken, run)
           : await _downloadDirectFile(task, cancelToken);
 
       _throwIfCancelled(cancelToken);
@@ -413,7 +501,7 @@ class DownloadService {
     task.downloadedBytes = resumePos;
 
     final progressClock = Stopwatch()..start();
-    var lastProgress = -150;
+    var lastProgress = -300;
     await client.download(
       task.url,
       filePath,
@@ -425,7 +513,7 @@ class DownloadService {
       onReceiveProgress: (received, total) {
         if (cancelToken.isCancelled) return;
         final now = progressClock.elapsedMilliseconds;
-        if (received != total && now - lastProgress < 150) return;
+        if (received != total && now - lastProgress < 300) return;
         lastProgress = now;
         final currentBytes = resumePos + received;
         task.downloadedBytes = currentBytes;
@@ -442,6 +530,7 @@ class DownloadService {
   Future<String> _downloadHls(
     DownloadTask task,
     CancelToken cancelToken,
+    _DownloadRun run,
   ) async {
     final manifestPath = await _resolveHlsManifestPath(task);
     _throwIfCancelled(cancelToken);
@@ -466,20 +555,79 @@ class DownloadService {
     // 分片下完后合并为单一视频，播放时走普通文件 seek，不再依赖 m3u8。
     task.progress = 0.99;
     _notifyAndSave();
-    final remuxed = await HlsOfflineRemux.remuxManifest(
-      manifestPath,
-      checkCancelled: () => _throwIfCancelled(cancelToken),
-    );
+
+    // 拼接是纯本地 IO，不再占用下载槽：立刻补位下一个等待任务，
+    // 并用全局串行锁保证同一时间只有一个视频在拼接（磁盘友好）。
+    run.merging = true;
+    _processQueue();
+    String? remuxed;
+    await _enqueueRemux(() async {
+      remuxed = await HlsOfflineRemux.remuxManifest(
+        manifestPath,
+        checkCancelled: () => _throwIfCancelled(cancelToken),
+      );
+    });
     _throwIfCancelled(cancelToken);
-    final playablePath = remuxed ?? manifestPath;
-    task.filePath = playablePath;
-    if (remuxed != null) {
-      final length = await File(remuxed).length();
-      task.downloadedBytes = length;
-      task.totalBytes = length;
+    if (remuxed == null) {
+      // 无法拼接（如加密流），保留本地 m3u8 结构，行为与旧版一致。
+      task.filePath = manifestPath;
+      task.progress = 1;
+      return manifestPath;
     }
+
+    // 成品移出 .hls 缓存文件夹，直接放到用户选择的保存目录，
+    // 文件名与任务一致（xxx.mp4 / xxx.ts），本地播放器可直接连续播放。
+    final dir = await _taskDirectory(task);
+    final base = _stripExtension(task.filename);
+    final ext = remuxed!.toLowerCase().endsWith('.ts') ? '.ts' : '.mp4';
+    final finalPath = _joinPath(dir.path, '$base$ext');
+    final src = File(remuxed!);
+    final dst = File(finalPath);
+
+    // 移动必须成功：失败重试（Windows 句柄释放有延迟）。在成品安全
+    // 落位之前，绝不能删除缓存文件夹——否则唯一成品会被一起删掉。
+    var moved = false;
+    for (var attempt = 0; attempt < 3 && !moved; attempt++) {
+      if (attempt > 0) {
+        await Future<void>.delayed(const Duration(milliseconds: 500));
+      }
+      if (await dst.exists()) {
+        try {
+          await dst.delete();
+        } catch (_) {}
+      }
+      try {
+        await src.rename(finalPath);
+        moved = true;
+      } catch (_) {
+        try {
+          await src.copy(finalPath);
+          await src.delete();
+          moved = true;
+        } catch (_) {}
+      }
+    }
+
+    // 只有成品已安全移出才清理缓存文件夹；删除失败也重试，
+    // 避免留下空文件夹。
+    if (moved) {
+      for (var attempt = 0; attempt < 3; attempt++) {
+        try {
+          await File(manifestPath).parent.delete(recursive: true);
+          break;
+        } catch (_) {
+          await Future<void>.delayed(const Duration(milliseconds: 500));
+        }
+      }
+    }
+
+    final usedPath = moved ? finalPath : remuxed!;
+    task.filePath = usedPath;
+    final length = await File(usedPath).length();
+    task.downloadedBytes = length;
+    task.totalBytes = length;
     task.progress = 1;
-    return playablePath;
+    return usedPath;
   }
 
   Future<_M3u8Playlist> _resolveMediaPlaylist(
@@ -525,7 +673,7 @@ class DownloadService {
     final received = List.filled(concurrency, 0);
     final fractions = List.filled(concurrency, 0.0);
     final clock = Stopwatch()..start();
-    var lastPublish = -150;
+    var lastPublish = -300;
     final assetToken = CancelToken();
     unawaited(cancelToken.whenCancel.then((error) => assetToken.cancel(error)));
     Object? failure;
@@ -551,25 +699,32 @@ class DownloadService {
         while (next < totalUnits) {
           _throwIfCancelled(assetToken);
           final asset = assets[next++];
-          final bytes = await _downloadHlsAsset(
-            asset,
-            cacheDir,
-            assetToken,
-            onProgress: (count, total) {
-              if (assetToken.isCancelled) return;
-              received[slot] = count;
-              fractions[slot] = total > 0
-                  ? (count / total).clamp(0.0, 1.0)
-                  : 0.5;
-              publish();
-            },
-          );
-          _throwIfCancelled(assetToken);
-          downloadedBytes += bytes;
-          completedUnits++;
-          received[slot] = 0;
-          fractions[slot] = 0;
-          publish();
+          // 全局闸门：多任务并行时把同时在飞的分片请求压回设置值，
+          // 避免几十上百路并发请求挤爆主 isolate 的事件循环卡住界面。
+          await _gate.acquire();
+          try {
+            final bytes = await _downloadHlsAsset(
+              asset,
+              cacheDir,
+              assetToken,
+              onProgress: (count, total) {
+                if (assetToken.isCancelled) return;
+                received[slot] = count;
+                fractions[slot] = total > 0
+                    ? (count / total).clamp(0.0, 1.0)
+                    : 0.5;
+                publish();
+              },
+            );
+            _throwIfCancelled(assetToken);
+            downloadedBytes += bytes;
+            completedUnits++;
+            received[slot] = 0;
+            fractions[slot] = 0;
+            publish();
+          } finally {
+            _gate.release();
+          }
         }
       } catch (error, stack) {
         failure ??= error;
@@ -666,7 +821,9 @@ class DownloadService {
       }
     }
 
-    if (task.bgmId != null && task.episodeIndex != null) {
+    if (_downloadDanmaku &&
+        task.bgmId != null &&
+        task.episodeIndex != null) {
       try {
         final danmuList = await DanmakuController.fetchDanmaku(
           subjectId: task.bgmId!,
@@ -741,6 +898,10 @@ class _DownloadRun {
   final DownloadTask task;
   final token = CancelToken();
   bool deleteOnFinish = false;
+
+  /// true = 已进入分片拼接阶段（纯本地 IO，不再占用网络下载槽），
+  /// 让后续任务可以继续下载，避免"合并时全部排队等待"。
+  bool merging = false;
   Future<void>? future;
 }
 
```

#### FILE: lib/services/download/download_resolve_manager.dart (+456/-0)
```diff
@@ -0,0 +1,456 @@
+import 'dart:async';
+
+import 'package:baka/api/bgm.dart';
+import 'package:baka/instance.dart';
+import 'package:baka/models/bgm.dart';
+import 'package:baka/models/download_task.dart';
+import 'package:baka/models/playback_episode.dart';
+import 'package:baka/services/download/download_manager.dart';
+import 'package:baka/services/playback/playback_content.dart';
+import 'package:flutter/foundation.dart';
+import 'package:flutter/material.dart';
+
+/// 一次批量下载解析任务的全部数据快照。
+///
+/// 播放页退出后 [PlaybackContent] 会被 dispose；通过 [keepAlive] 的
+/// retain/release 让解析期间实例保持存活，解析因此不依赖播放页。
+class DownloadResolveJob {
+  DownloadResolveJob({
+    required this.indices,
+    required this.saveDir,
+    required this.resolver,
+    this.keepAlive,
+    required this.detail,
+    required this.videoList,
+    required this.taskIdPrefix,
+  });
+
+  final List<int> indices;
+  final String saveDir;
+  final Future<String?> Function(int episodeIndex) resolver;
+  final PlaybackContent? keepAlive;
+  final Map<String, dynamic> detail;
+  final List<PlaybackEpisode> videoList;
+  final String taskIdPrefix;
+
+  String taskId(int index) => '$taskIdPrefix${index + 1}';
+}
+
+/// 悬浮条右侧的一个操作按钮。
+class ResolveBannerAction {
+  const ResolveBannerAction(this.label, this.onPressed);
+  final String label;
+  final VoidCallback onPressed;
+}
+
+/// 解析进度悬浮条的状态快照。
+class ResolveBanner {
+  const ResolveBanner({
+    required this.text,
+    this.isError = false,
+    this.actions = const [],
+    this.autoHideAfter,
+  });
+
+  final String text;
+  final bool isError;
+
+  /// 右侧操作按钮（取消/重试）。
+  final List<ResolveBannerAction> actions;
+
+  /// 非 null 时由悬浮条在此时长后自动隐藏（用于"完成"这类短暂提示）。
+  final Duration? autoHideAfter;
+}
+
+/// 批量下载解析管理器：独立于播放页/弹窗生命周期运行。
+///
+/// - 播放页退出不影响解析（解析前 retain 住 PlaybackContent）。
+/// - 进度通过 [banner] 通知常驻悬浮条（数字原地更新，不闪不排队）。
+class DownloadResolveManager {
+  DownloadResolveManager._();
+  static final DownloadResolveManager instance = DownloadResolveManager._();
+
+  /// 首次解析 + 最多 3 次重试。
+  static const int _maxAttempts = 4;
+
+  /// 单轮内并发解析的集数：逐集串行时一集一个 15 秒超时，重试会拖很久。
+  static const int _resolveConcurrency = 4;
+
+  /// 解析进度悬浮条：数字原地更新，替代 SnackBar（SnackBar 每次更新
+  /// 都要整条重建，既闪烁又与操作按钮存在关闭竞态）。
+  final ValueNotifier<ResolveBanner?> banner = ValueNotifier(null);
+  bool _cancelled = false;
+
+  final _queue = <DownloadResolveJob>[];
+  bool _draining = false;
+  String _currentTitle = '';
+  DownloadResolveJob? _lastAbandoned;
+  List<int> _remaining = const [];
+  List<int> _failed = const [];
+  int _totalOfCurrentJob = 0;
+  int _resolvedCount = 0;
+
+  // ---- 对外操作 ----
+
+  void enqueue(DownloadResolveJob job) {
+    // 必须在入队时同步 retain：此刻弹窗还开在播放页上，content 一定存活；
+    // 若推迟到 job 开始执行，播放页可能已退出、content 已被销毁。
+    job.keepAlive?.retain();
+    _queue.add(job);
+    if (!_draining) unawaited(_drain());
+  }
+
+  /// 取消解析：正在解析 → 中断并丢弃全部已解析结果；
+  /// 放弃待重试态 → 关闭提示条并不再重试。
+  void cancel() {
+    if (_draining && !_cancelled) {
+      _cancelled = true;
+      _showBanner('正在取消解析…');
+      return;
+    }
+    // 放弃待重试态（或空闲）：直接清掉提示并释放。
+    if (_lastAbandoned != null) {
+      _lastAbandoned?.keepAlive?.release();
+      _lastAbandoned = null;
+    }
+    _failed = const [];
+    banner.value = null;
+  }
+
+  /// 对最终放弃的集重新发起解析（重置重试计数）。
+  void retry() {
+    if (_failed.isEmpty) return;
+    final job = _lastAbandoned;
+    if (job == null) return;
+    _queue.add(
+      DownloadResolveJob(
+        indices: List<int>.from(_failed),
+        saveDir: job.saveDir,
+        resolver: job.resolver,
+        keepAlive: job.keepAlive,
+        detail: job.detail,
+        videoList: job.videoList,
+        taskIdPrefix: job.taskIdPrefix,
+      ),
+    );
+    _failed = const [];
+    _lastAbandoned = null;
+    if (!_draining) unawaited(_drain());
+  }
+
+  // ---- 内部执行 ----
+
+  Future<void> _drain() async {
+    _draining = true;
+    while (_queue.isNotEmpty) {
+      final job = _queue.removeAt(0);
+      await _runJob(job);
+    }
+    _draining = false;
+    _remaining = const [];
+  }
+
+  Future<void> _runJob(DownloadResolveJob job) async {
+    try {
+      await downloads.init();
+      _currentTitle = job.detail['title'] as String? ?? '';
+      final bgmId = await _resolveBgmId(job);
+      final total = job.indices.length;
+      _totalOfCurrentJob = total;
+      _resolvedCount = 0;
+      _remaining = List<int>.from(job.indices);
+      _showRunningBanner();
+
+      final tasks = <DownloadTask>[];
+      for (
+        var attempt = 1;
+        attempt <= _maxAttempts && _remaining.isNotEmpty && !_cancelled;
+        attempt++
+      ) {
+        if (attempt > 1) {
+          if (_cancelled) break;
+          _showBanner(
+            '正在解析《$_currentTitle》：第 ${episodeNumbers(_remaining)} 集解析失败，开始第 ${attempt - 1} 次重试（${_resolvedCount.clamp(0, total)}/$total）${_queueSuffix()}',
+            actions: [
+              ResolveBannerAction('取消', cancel),
+            ],
+          );
+          await Future<void>.delayed(_retryDelay(attempt - 1));
+        }
+        final retry = <int>[];
+        for (
+          var start = 0;
+          start < _remaining.length && !_cancelled;
+          start += _resolveConcurrency
+        ) {
+          if (_cancelled) break;
+          final end = start + _resolveConcurrency > _remaining.length
+              ? _remaining.length
+              : start + _resolveConcurrency;
+          final chunk = _remaining.sublist(start, end);
+          final resolved = await Future.wait(
+            chunk.map((index) => _resolveOne(job, index, bgmId)),
+          );
+          for (var i = 0; i < chunk.length; i++) {
+            final task = resolved[i];
+            if (task == null) {
+              retry.add(chunk[i]);
+            } else {
+              tasks.add(task);
+            }
+          }
+          // 每批解析完刷新一次进度（X/N）。
+          _resolvedCount = tasks.length;
+          if (_remaining.length > end || retry.isNotEmpty) {
+            _showRunningBanner();
+          }
+        }
+        _remaining = retry;
+      }
+
+      if (_cancelled) {
+        // 用户取消：全部丢弃。解析中的任务从未入队，不会留下任何记录。
+        _cancelled = false;
+        _failed = const [];
+        _lastAbandoned = null;
+        for (final task in tasks) {
+          task.dispose();
+        }
+        _showBanner(
+          '解析已取消',
+          autoHideAfter: const Duration(seconds: 3),
+        );
+        job.keepAlive?.release();
+        return;
+      }
+
+      if (_remaining.isEmpty) {
+        final added = downloads.addTasks(tasks);
+        _failed = const [];
+        _lastAbandoned = null;
+        _showBanner(
+          added > 0 ? '解析完成，$added 集已加入下载队列' : '解析完成，所选剧集已在下载队列中',
+          autoHideAfter: const Duration(seconds: 3),
+        );
+        job.keepAlive?.release();
+        return;
+      }
+
+      _failed = List<int>.from(_remaining);
+      _lastAbandoned = job;
+      _showBanner(
+        '解析完成：第 ${episodeNumbers(_failed)} 集解析失败，已放弃',
+        isError: true,
+        actions: [
+          ResolveBannerAction('重试', retry),
+          ResolveBannerAction('取消', cancel),
+        ],
+      );
+      // 保留 retain：用户随时可能点「重试」；放弃的实例在本会话内
+      // 不再销毁，重启应用后自然回收。
+    } catch (error) {
+      debugPrint('DownloadResolveManager: job failed: $error');
+      job.keepAlive?.release();
+      _showBanner(
+        '解析失败：$error',
+        isError: true,
+        autoHideAfter: const Duration(seconds: 5),
+      );
+    }
+  }
+
+  Future<DownloadTask?> _resolveOne(
+    DownloadResolveJob job,
+    int index,
+    int? bgmId,
+  ) async {
+    try {
+      final resolvedUrl = await job.resolver(index);
+      if (resolvedUrl == null || resolvedUrl.isEmpty) return null;
+      final episodeTitle = job.videoList[index].title;
+      final kind = DownloadTask.inferKind(resolvedUrl);
+      final extension = kind == DownloadTaskKind.hls ? 'm3u8' : 'mp4';
+      final sourceName =
+          job.detail['sourceDisplayName'] as String? ?? '';
+      final title = job.detail['title'] as String? ?? '';
+      final filenamePrefix = sourceName.isNotEmpty
+          ? '${title}_[$sourceName]_'
+          : '${title}_';
+      final subtitlePrefix = sourceName.isNotEmpty ? '$sourceName · ' : '';
+      final thumbnail = resolveCoverImage(job.detail);
+      return DownloadTask(
+        id: job.taskId(index),
+        url: resolvedUrl,
+        filename: '$filenamePrefix${episodeTitle}_${index + 1}.$extension',
+        title: title,
+        subtitle: '$subtitlePrefix$episodeTitle',
+        thumbnail: thumbnail,
+        bgmId: bgmId,
+        episodeIndex: index + 1,
+        kind: kind,
+        saveDir: job.saveDir,
+      );
+    } catch (error) {
+      debugPrint('resolve download episode ${index + 1}: $error');
+      return null;
+    }
+  }
+
+  /// 仅在开启「下载弹幕」时才请求 Bangumi，避免无谓的网络等待拖慢解析。
+  Future<int?> _resolveBgmId(DownloadResolveJob job) async {
+    if (Instances.sp.getBool('download_danmaku') != true) return null;
+    try {
+      return (await resolveBgmFromData(job.detail)).subjectId;
+    } catch (error) {
+      debugPrint('resolve bgm for download: $error');
+      return null;
+    }
+  }
+
+  /// 队列等待提示：不同作品串行解析，展示还有几部作品在排队。
+  String _queueSuffix() {
+    final waiting = _queue.length;
+    return waiting > 0
+        ? '【剩余$waiting部作品排队中】'
+        : '【剩余0部作品排队中】';
+  }
+
+  void _showRunningBanner() {
+    if (_cancelled) return;
+    final total = _totalOfCurrentJob;
+    final done = _resolvedCount.clamp(0, total);
+    final title = _currentTitle.isNotEmpty ? _currentTitle : '$total 集';
+    _showBanner(
+      '正在解析《$title》（$done/$total）${_queueSuffix()}',
+      actions: [
+        ResolveBannerAction('取消', cancel),
+      ],
+    );
+  }
+
+  void _showBanner(
+    String text, {
+    bool isError = false,
+    List<ResolveBannerAction> actions = const [],
+    Duration? autoHideAfter,
+  }) {
+    banner.value = ResolveBanner(
+      text: text,
+      isError: isError,
+      actions: actions,
+      autoHideAfter: autoHideAfter,
+    );
+  }
+
+  String episodeNumbers(List<int> indexes) =>
+      indexes.map((index) => '${index + 1}').join('、');
+
+  Duration _retryDelay(int retryRound) {
+    if (retryRound <= 1) return const Duration(seconds: 1);
+    if (retryRound <= 2) return const Duration(seconds: 2);
+    return const Duration(seconds: 3);
+  }
+}
+
+/// 解析进度的常驻悬浮条：监听 [DownloadResolveManager.banner]，
+/// 数字变化时只重建文本（SnackBar 则要整条拆除重建——闪烁且与
+/// 按钮点击存在关闭竞态）。挂在 MaterialApp.builder 的最外层。
+class DownloadResolveBanner extends StatefulWidget {
+  const DownloadResolveBanner({super.key});
+
+  @override
+  State<DownloadResolveBanner> createState() => _DownloadResolveBannerState();
+}
+
+class _DownloadResolveBannerState extends State<DownloadResolveBanner> {
+  static const _hideDelay = Duration(milliseconds: 220);
+  ResolveBanner? _last;
+  Timer? _autoHide;
+
+  @override
+  void initState() {
+    super.initState();
+    DownloadResolveManager.instance.banner.addListener(_onChanged);
+  }
+
+  @override
+  void dispose() {
+    DownloadResolveManager.instance.banner.removeListener(_onChanged);
+    _autoHide?.cancel();
+    super.dispose();
+  }
+
+  void _onChanged() {
+    _autoHide?.cancel();
+    _autoHide = null;
+    final banner = DownloadResolveManager.instance.banner.value;
+    if (banner != null) _last = banner;
+    if (banner?.autoHideAfter != null) {
+      _autoHide = Timer(banner!.autoHideAfter!, () {
+        DownloadResolveManager.instance.banner.value = null;
+      });
+    }
+    if (mounted) setState(() {});
+  }
+
+  @override
+  Widget build(BuildContext context) {
+    final current = DownloadResolveManager.instance.banner.value;
+    final banner = current ?? _last;
+    final visible = current != null && banner != null;
+    return Positioned(
+      left: 24,
+      right: 24,
+      bottom: 24,
+      child: IgnorePointer(
+        ignoring: !visible,
+        child: AnimatedOpacity(
+          opacity: visible ? 1 : 0,
+          duration: _hideDelay,
+          curve: Curves.easeOut,
+          child: AnimatedSlide(
+            offset: visible ? Offset.zero : const Offset(0, 0.3),
+            duration: _hideDelay,
+            curve: Curves.easeOut,
+            child: banner == null
+                ? const SizedBox.shrink()
+                : Material(
+                    color: banner.isError
+                        ? const Color(0xFFD32F2F)
+                        : const Color(0xFF323232),
+                    borderRadius: BorderRadius.circular(10),
+                    elevation: 6,
+                    child: Padding(
+                      padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
+                      child: Row(
+                        children: [
+                          Expanded(
+                            child: Text(
+                              banner.text,
+                              style: const TextStyle(
+                                color: Colors.white,
+                                fontSize: 14,
+                              ),
+                            ),
+                          ),
+                          for (final action in banner.actions)
+                            TextButton(
+                              onPressed: action.onPressed,
+                              style: TextButton.styleFrom(
+                                foregroundColor: Colors.white,
+                                padding: const EdgeInsets.symmetric(
+                                  horizontal: 10,
+                                ),
+                              ),
+                              child: Text(action.label),
+                            ),
+                        ],
+                      ),
+                    ),
+                  ),
+          ),
+        ),
+      ),
+    );
+  }
+}
```

#### FILE: lib/services/download/hls_offline_remux.dart (+17/-3)
```diff
@@ -227,19 +227,33 @@ abstract final class HlsOfflineRemux {
     Directory dir, {
     required String keepFileName,
   }) async {
+    final victims = <File>[];
     await for (final entity in dir.list(followLinks: false)) {
       if (entity is! File) continue;
       final name = entity.uri.pathSegments.isEmpty
           ? entity.path
           : entity.uri.pathSegments.last;
       if (name == keepFileName) continue;
       if (name.endsWith('_danmaku.json') || name.endsWith('.json')) continue;
-      try {
-        await entity.delete();
-      } catch (_) {}
+      victims.add(entity);
+    }
+    // 串行逐个删在 Windows 上是几百次同步等待；分批并发删除能明显缩短
+    // 下载收尾（界面停在最后进度）的时间。
+    const batch = 64;
+    for (var i = 0; i < victims.length; i += batch) {
+      final end = i + batch > victims.length ? victims.length : i + batch;
+      await Future.wait([
+        for (final f in victims.sublist(i, end)) _deleteQuietly(f),
+      ]);
     }
   }
 
+  static Future<void> _deleteQuietly(File f) async {
+    try {
+      await f.delete();
+    } catch (_) {}
+  }
+
   static Future<bool> _looksLikeFmp4(File file) async {
     if (!await file.exists()) return false;
     final raf = await file.open();
```

#### FILE: lib/services/playback/playback_content.dart (+22/-1)
```diff
@@ -747,7 +747,28 @@ class PlaybackContent {
   }
 
   Future<void>? _disposing;
-  Future<void> dispose() => _disposing ??= _dispose();
+  bool _disposeRequested = false;
+  int _retainCount = 0;
+
+  /// 下载解析期间延长生命周期：播放页退出后解析仍能继续。
+  void retain() => _retainCount++;
+
+  void release() {
+    if (_retainCount > 0) _retainCount--;
+    if (_retainCount == 0 && _disposeRequested && _disposing == null) {
+      unawaited(dispose());
+    }
+  }
+
+  Future<void> dispose() {
+    if (_retainCount > 0) {
+      // 有解析任务还在使用本实例：推迟销毁，等全部 release 后再真正清理。
+      _disposeRequested = true;
+      return _disposing ?? Future<void>.value();
+    }
+    return _disposing ??= _dispose();
+  }
+
   Future<void> _dispose() async {
     if (_disposed) return;
     _disposed = true;
```

#### FILE: lib/utils/toast_utils.dart (+18/-2)
```diff
@@ -9,26 +9,42 @@ import 'package:fluttertoast/fluttertoast.dart';
 final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
     GlobalKey<ScaffoldMessengerState>();
 
+Timer? _snackDismissTimer;
+int _snackSeq = 0;
+
 void showSnackBar(
   String text, {
   ToastGravity gravity = ToastGravity.BOTTOM,
   bool isError = false,
   SnackBarAction? action,
   Duration? duration,
+  bool replace = false,
 }) {
   if (action != null ||
       Platform.isWindows ||
       Platform.isMacOS ||
       Platform.isLinux) {
-    scaffoldMessengerKey.currentState?.showSnackBar(
+    final messenger = scaffoldMessengerKey.currentState;
+    if (messenger == null) return;
+    if (replace) messenger.removeCurrentSnackBar();
+    final effective = duration ?? Duration(seconds: action == null ? 2 : 4);
+    final seq = ++_snackSeq;
+    messenger.showSnackBar(
       SnackBar(
         content: Text(text),
-        duration: duration ?? Duration(seconds: action == null ? 2 : 4),
+        duration: effective,
         behavior: SnackBarBehavior.floating,
         backgroundColor: isError ? const Color(0xFFD32F2F) : null,
         action: action,
       ),
     );
+    // SnackBar 自带的计时依赖帧调度：窗口失焦、被遮挡或无障碍模式打开时
+    // 可能永不触发自动关闭。这里用一个真实的 Timer 兜底，保证到点一定消失。
+    _snackDismissTimer?.cancel();
+    _snackDismissTimer = Timer(effective, () {
+      if (seq != _snackSeq) return;
+      scaffoldMessengerKey.currentState?.removeCurrentSnackBar();
+    });
   } else {
     Fluttertoast.showToast(
       msg: text,
```

#### FILE: lib/widgets/episode/episode_list_dialog.dart (+24/-51)
```diff
@@ -3,12 +3,12 @@ import 'package:flutter/services.dart';
 
 import 'package:file_picker/file_picker.dart';
 import 'package:baka/instance.dart';
-import 'package:baka/models/download_task.dart';
-import 'package:baka/models/bgm.dart';
-import 'package:baka/api/bgm.dart';
+import 'package:baka/models/playback_episode.dart';
 import 'package:baka/services/download/download_manager.dart';
+import 'package:baka/services/download/download_resolve_manager.dart';
 import 'package:baka/services/playback/history_repository.dart';
-import 'package:baka/models/playback_episode.dart';
+import 'package:baka/services/playback/playback_content.dart';
+import 'package:baka/utils/toast_utils.dart';
 import 'package:baka/widgets/episode/episode_widgets.dart';
 
 const _kSearchThreshold = 12;
@@ -23,6 +23,7 @@ Future<int?> showEpisodeListDialog({
   bool isFullScreen = false,
   Map<String, dynamic>? postDetail,
   Future<String?> Function(int episodeIndex)? urlResolver,
+  PlaybackContent? resolveTarget,
   bool startInDownloadMode = false,
   int? currentLineIndex,
   List<String>? sourceNames,
@@ -35,6 +36,7 @@ Future<int?> showEpisodeListDialog({
     isFullScreen: isFullScreen,
     postDetail: postDetail,
     urlResolver: urlResolver,
+    resolveTarget: resolveTarget,
     startInDownloadMode: startInDownloadMode,
     currentLineIndex: currentLineIndex,
     sourceNames: sourceNames,
@@ -73,12 +75,17 @@ class EpisodeListDialog extends StatefulWidget {
   final bool isFullScreen;
   final Map<String, dynamic>? postDetail;
   final Future<String?> Function(int episodeIndex)? urlResolver;
+
+  /// 解析所依赖的播放内容实例：下载解析期间会被 retain，
+  /// 播放页退出不会中断解析。
+  final PlaybackContent? resolveTarget;
   final bool startInDownloadMode;
   final int? currentLineIndex;
   final List<String>? sourceNames;
   final ValueChanged<int>? onLineChanged;
 
-  bool get canDownload => postDetail != null && urlResolver != null;
+  bool get canDownload =>
+      postDetail != null && urlResolver != null && resolveTarget != null;
 
   const EpisodeListDialog({
     required this.videoList,
@@ -88,6 +95,7 @@ class EpisodeListDialog extends StatefulWidget {
     super.key,
     this.postDetail,
     this.urlResolver,
+    this.resolveTarget,
     this.startInDownloadMode = false,
     this.currentLineIndex,
     this.sourceNames,
@@ -245,53 +253,18 @@ class _EpisodeListDialogState extends State<EpisodeListDialog> {
       }
     }
     if (!mounted) return;
-    ScaffoldMessenger.of(
-      context,
-    ).showSnackBar(SnackBar(content: Text('开始在后台解析 ${indices.length} 集')));
     Navigator.pop(context);
-    _resolveAndEnqueue(indices, saveDir).ignore();
-  }
-
-  Future<void> _resolveAndEnqueue(List<int> indices, String saveDir) async {
-    final service = downloads;
-    final detail = widget.postDetail!;
-    final bgmId = (await resolveBgmFromData(detail)).subjectId;
-
-    final sourceName = detail['sourceDisplayName'] as String? ?? '';
-    final title = detail['title'] as String? ?? '';
-    final thumbnail = resolveCoverImage(detail);
-    final filenamePrefix = sourceName.isNotEmpty
-        ? '${title}_[$sourceName]_'
-        : '${title}_';
-    final subtitlePrefix = sourceName.isNotEmpty ? '$sourceName · ' : '';
-
-    final tasks = <DownloadTask>[];
-    for (final index in indices) {
-      try {
-        final resolvedUrl = await widget.urlResolver!(index);
-        if (resolvedUrl == null || resolvedUrl.isEmpty) continue;
-        final episodeTitle = widget.videoList[index].title;
-        final kind = DownloadTask.inferKind(resolvedUrl);
-        final extension = kind == DownloadTaskKind.hls ? 'm3u8' : 'mp4';
-        tasks.add(
-          DownloadTask(
-            id: _taskId(index),
-            url: resolvedUrl,
-            filename: '$filenamePrefix${episodeTitle}_${index + 1}.$extension',
-            title: title,
-            subtitle: '$subtitlePrefix$episodeTitle',
-            thumbnail: thumbnail,
-            bgmId: bgmId,
-            episodeIndex: index + 1,
-            kind: kind,
-            saveDir: saveDir,
-          ),
-        );
-      } catch (error) {
-        debugPrint('resolve download episode ${index + 1}: $error');
-      }
-    }
-    service.addTasks(tasks);
+    DownloadResolveManager.instance.enqueue(
+      DownloadResolveJob(
+        indices: indices,
+        saveDir: saveDir,
+        resolver: widget.urlResolver!,
+        keepAlive: widget.resolveTarget,
+        detail: widget.postDetail!,
+        videoList: widget.videoList,
+        taskIdPrefix: _taskIdPrefix,
+      ),
+    );
   }
 
   @override
```

#### FILE: local_deps/ech_http/src/cacert.pem (patch not available via API)
