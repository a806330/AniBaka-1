import 'package:flutter/material.dart';

import 'package:baka/app/navigation.dart';
import 'package:baka/pages/browse/site_profiles.dart';
import 'package:baka/services/source/source_repository.dart';
import 'package:baka/source/models/series.dart';
import 'package:baka/source/models/source_rule.dart';
import 'package:baka/source/models/source_search_result.dart';
import 'package:baka/source/source_adapter.dart';
import 'package:baka/widgets/source/source_widgets.dart';

/// 单个源的「站点页」：原生渲染，套用该源的站点外观与栏目结构。
///
/// 进入时只创建这一个源的适配器，只请求当前栏目的内容；切栏目才请求对应
/// 分类，站内搜索只打这个源。页面关闭即释放，不做全量预加载。
class SourceSitePage extends StatefulWidget {
  const SourceSitePage({
    required this.sourceKey,
    required this.displayName,
    required this.accent,
    this.iconUrl,
    this.baseUrl,
    super.key,
  });

  final String sourceKey;
  final String displayName;
  final Color accent;

  /// 站点图标的原始地址（自定义源没有内置配色与图标时由入口页传入）。
  final String? iconUrl;

  /// 站点主页，用于顶栏显示域名；为空时回退到适配器读到的规则地址。
  final String? baseUrl;

  @override
  State<SourceSitePage> createState() => _SourceSitePageState();
}

class _SourceSitePageState extends State<SourceSitePage>
    with TickerProviderStateMixin {
  late final SiteProfile _profile = SiteProfile.forSource(widget.sourceKey);
  final TextEditingController _searchField = TextEditingController();
  TabController? _tabs;
  SourceAdapter? _adapter;
  List<SourceCategory> _categories = const [];
  String _host = '';
  String _origin = '';

  String _query = '';
  bool _searching = false;
  List<Series> _results = const [];
  String? _searchError;

  @override
  void initState() {
    super.initState();
    // 复用仓库里的共享适配器：与播放链路同一 Cookie / 同一缓存，且由仓库
    // 统一回收，这里不持有它的生命周期。
    final adapter = sourceRepository.adapterFor(widget.sourceKey);
    _adapter = adapter;
    _categories = adapter?.rule.categories ?? const <SourceCategory>[];
    final baseUrl = widget.baseUrl ?? adapter?.baseUrl ?? '';
    _host = Uri.tryParse(baseUrl)?.host ?? baseUrl;
    // 封面大多放在源站自己的 /upload 下并校验 Referer，带上源站 Origin 才能出图。
    final parsed = Uri.tryParse(baseUrl);
    _origin = parsed == null ? '' : '${parsed.scheme}://${parsed.host}';
    _tabs = TabController(length: _categories.length + 1, vsync: this);
  }

  @override
  void dispose() {
    _tabs?.dispose();
    _searchField.dispose();
    super.dispose();
  }

  Color get _onAccent =>
      ThemeData.estimateBrightnessForColor(widget.accent) == Brightness.dark
      ? Colors.white
      : Colors.black87;

  Future<void> _runSearch(String raw) async {
    final keyword = raw.trim();
    final adapter = _adapter;
    if (keyword.isEmpty || adapter == null) {
      _clearSearch();
      return;
    }
    setState(() {
      _query = keyword;
      _searching = true;
      _searchError = null;
      _results = const [];
    });
    try {
      final list = await adapter.search(keyword, enhanceWithBgm: false);
      if (!mounted || _query != keyword) return;
      setState(() {
        _results = list;
        _searching = false;
      });
    } catch (error) {
      debugPrint('site search failed: $error');
      if (!mounted || _query != keyword) return;
      setState(() {
        _searching = false;
        _searchError = '搜索失败，请稍后重试';
      });
    }
  }

  void _clearSearch() {
    _searchField.clear();
    setState(() {
      _query = '';
      _searching = false;
      _results = const [];
      _searchError = null;
    });
  }

  Future<void> _openSeries(Series series) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final request = await sourceRepository.buildPlaybackRequest(
        SourceSearchResult(
          series,
          source: widget.sourceKey,
          displayName: widget.displayName,
        ),
      );
      if (!mounted) return;
      if (request != null) {
        NavigationService.toPlayback(context, request, autoMatch: false);
        return;
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text('未找到剧集数据'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (error) {
      debugPrint('open series failed: $error');
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('打开失败，请稍后重试'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final adapter = _adapter;
    if (adapter == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.displayName)),
        body: Center(
          child: Text(
            '该源未内置规则，无法打开',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    final onAccent = _onAccent;
    return Scaffold(
      body: Column(
        children: [
          _header(context, onAccent),
          if (_categories.isNotEmpty) _tabBar(onAccent),
          Expanded(
            child: _query.isEmpty ? _tabBody(adapter) : _searchBody(),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, Color onAccent) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            widget.accent,
            Color.lerp(widget.accent, Colors.black, 0.32) ?? widget.accent,
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 12),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  tooltip: '返回',
                  icon: Icon(Icons.arrow_back_rounded, color: onAccent),
                ),
                SourceIcon(
                  name: widget.displayName,
                  iconUrl: widget.iconUrl,
                  baseUrl: widget.baseUrl,
                  size: 36,
                  radius: 11,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: onAccent,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      Text(
                        _host.isEmpty
                            ? _profile.tagline
                            : '${_profile.tagline} · $_host',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: onAccent.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_profile.showSearch) ...[
              const SizedBox(height: 10),
              _searchBox(onAccent),
            ],
          ],
        ),
      ),
    );
  }

  Widget _searchBox(Color onAccent) {
    final hint = onAccent.withValues(alpha: 0.62);
    return TextField(
      controller: _searchField,
      textInputAction: TextInputAction.search,
      onSubmitted: _runSearch,
      style: TextStyle(color: onAccent, fontSize: 14),
      cursorColor: onAccent,
      decoration: InputDecoration(
        isDense: true,
        hintText: '在 ${widget.displayName} 内搜索',
        hintStyle: TextStyle(color: hint, fontSize: 13),
        prefixIcon: Icon(Icons.search_rounded, size: 18, color: hint),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                onPressed: _clearSearch,
                tooltip: '清除搜索',
                icon: Icon(Icons.close_rounded, size: 18, color: hint),
              ),
        filled: true,
        fillColor: onAccent.withValues(alpha: 0.14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _tabBar(Color onAccent) {
    final tabs = _tabs;
    if (tabs == null) return const SizedBox.shrink();
    return Material(
      color: widget.accent,
      child: TabBar(
        controller: tabs,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: onAccent,
        unselectedLabelColor: onAccent.withValues(alpha: 0.62),
        indicatorColor: onAccent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 13),
        tabs: [
          const Tab(text: '首页'),
          for (final category in _categories) Tab(text: category.name),
        ],
      ),
    );
  }

  Widget _tabBody(SourceAdapter adapter) {
    final tabs = _tabs;
    final profile = _profile;
    final accent = widget.accent;
    final key = widget.sourceKey;
    final empty = '该源这个栏目暂时没有内容';
    if (tabs == null) return const SizedBox.shrink();
    return TabBarView(
      controller: tabs,
      children: [
        _SeriesTab(
          cacheKey: '$key|home',
          loader: () => adapter.fetchHome(enhanceWithBgm: false),
          profile: profile,
          accent: accent,
          referer: _origin,
          emptyHint: empty,
          onOpen: _openSeries,
        ),
        for (final category in _categories)
          _SeriesTab(
            cacheKey: '$key|cat:${category.id}',
            loader: () =>
                adapter.fetchCategory(category.id, enhanceWithBgm: false),
            profile: profile,
            accent: accent,
            referer: _origin,
            emptyHint: empty,
            onOpen: _openSeries,
          ),
      ],
    );
  }

  Widget _searchBody() {
    final theme = Theme.of(context);
    final Widget content;
    if (_searching) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_searchError != null) {
      content = _hintBlock(theme, _searchError!);
    } else if (_results.isEmpty) {
      content = _hintBlock(theme, '「$_query」没有找到结果');
    } else {
      content = _SeriesGrid(
        items: _results,
        profile: _profile,
        accent: widget.accent,
        referer: _origin,
        onOpen: _openSeries,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '「$_query」· 本站搜索结果',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor,
                  ),
                ),
              ),
              TextButton(
                onPressed: _clearSearch,
                child: const Text('返回栏目'),
              ),
            ],
          ),
        ),
        Expanded(child: content),
      ],
    );
  }

  Widget _hintBlock(ThemeData theme, String message) => Center(
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
    ),
  );
}

/// 单个栏目的内容网格。
///
/// 自带 10 分钟内存缓存：切栏目、滑出视口、返回再进入都不会重复请求；只缓存
/// 已经看过的栏目，不做预加载。
class _SeriesTab extends StatefulWidget {
  const _SeriesTab({
    required this.cacheKey,
    required this.loader,
    required this.profile,
    required this.accent,
    required this.referer,
    required this.emptyHint,
    required this.onOpen,
  });

  final String cacheKey;
  final Future<List<Series>> Function() loader;
  final SiteProfile profile;
  final Color accent;

  /// 封面请求要带的 Referer（源站 Origin），否则多数站会 403。
  final String referer;
  final String emptyHint;
  final void Function(Series series) onOpen;

  @override
  State<_SeriesTab> createState() => _SeriesTabState();
}

class _SeriesTabState extends State<_SeriesTab>
    with AutomaticKeepAliveClientMixin {
  static final Map<String, _TabCacheEntry> _cache = {};

  List<Series>? _items;
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final cached = _cache[widget.cacheKey];
    if (cached != null && cached.isFresh) {
      _items = cached.items;
      _loading = false;
    } else {
      _fetch();
    }
  }

  Future<void> _retry() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await _fetch();
  }

  /// 下拉刷新：保留当前已显示的内容，直接换新，避免整页闪成加载圈。
  Future<void> _refresh() async {
    try {
      final items = await widget.loader();
      _cache[widget.cacheKey] = _TabCacheEntry(items);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      debugPrint('site tab refresh failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('刷新失败，请稍后重试'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _fetch() async {
    try {
      final items = await widget.loader();
      _cache[widget.cacheKey] = _TabCacheEntry(items);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      debugPrint('site tab load failed: $error');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '内容加载失败';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              error,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.hintColor,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _retry, child: const Text('重试')),
          ],
        ),
      );
    }
    final items = _items ?? const <Series>[];
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.22),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.inbox_outlined,
                    size: 28,
                    color: theme.hintColor.withValues(alpha: 0.7),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.emptyHint,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _retry,
                    child: const Text('重新加载'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: _SeriesGrid(
        items: items,
        profile: widget.profile,
        accent: widget.accent,
        referer: widget.referer,
        onOpen: widget.onOpen,
      ),
    );
  }
}

class _TabCacheEntry {
  _TabCacheEntry(this.items) : createdAt = DateTime.now();

  final List<Series> items;
  final DateTime createdAt;

  static const Duration _ttl = Duration(minutes: 10);

  bool get isFresh => DateTime.now().difference(createdAt) < _ttl;
}

class _SeriesGrid extends StatelessWidget {
  const _SeriesGrid({
    required this.items,
    required this.profile,
    required this.accent,
    required this.referer,
    required this.onOpen,
  });

  final List<Series> items;
  final SiteProfile profile;
  final Color accent;
  final String referer;
  final void Function(Series series) onOpen;

  @override
  Widget build(BuildContext context) => GridView.builder(
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
    // 内容不足一屏时也要能下拉，否则 RefreshIndicator 触发不了。
    physics: const AlwaysScrollableScrollPhysics(),
    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: profile.maxCrossAxisExtent,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: profile.cardAspect,
    ),
    itemCount: items.length,
    itemBuilder: (context, index) {
      final item = items[index];
      return _SeriesTile(
        series: item,
        accent: accent,
        referer: referer,
        onTap: () => onOpen(item),
      );
    },
  );
}

class _SeriesTile extends StatelessWidget {
  const _SeriesTile({
    required this.series,
    required this.accent,
    required this.referer,
    required this.onTap,
  });

  final Series series;
  final Color accent;
  final String referer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = series.image ?? '';
    final badge = (series.description ?? '').trim();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  cover.isEmpty
                      ? _coverFallback()
                      : Image.network(
                          cover,
                          fit: BoxFit.cover,
                          headers: referer.isEmpty
                              ? null
                              : {'Referer': '$referer/'},
                          errorBuilder: (_, _, _) => _coverFallback(),
                        ),
                  if (badge.isNotEmpty)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      left: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.78),
                            ],
                          ),
                        ),
                        child: Text(
                          badge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            height: 1.1,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            series.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  Widget _coverFallback() => Container(
    color: accent.withValues(alpha: 0.12),
    alignment: Alignment.center,
    child: Icon(Icons.movie_outlined, color: accent, size: 22),
  );
}
