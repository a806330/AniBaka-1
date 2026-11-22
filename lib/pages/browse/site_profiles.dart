/// 单个源站点的外观配置。
///
/// 只描述「怎么显示」，不描述「取什么内容」——栏目清单来自规则里的
/// `categories`，内容来自 `home` / `category` / `search` 管线。因此这里改
/// 数值不会影响抓取逻辑，新增源即使没有条目也会落到 [SiteProfile.fallback]。
class SiteProfile {
  const SiteProfile({
    required this.tagline,
    this.maxCrossAxisExtent = 180,
    this.cardAspect = 0.62,
    this.showSearch = true,
  });

  /// 站点副标题，显示在顶部站点色标题栏里。
  final String tagline;

  /// 内容网格单卡最大宽度，越小每行排得越多、观感越紧凑。
  final double maxCrossAxisExtent;

  /// 单卡宽高比，海报类站点偏窄长（0.6 左右），列表类可调宽。
  final double cardAspect;

  /// 是否在顶栏显示站内搜索框。
  final bool showSearch;

  /// 无配置源的兜底外观。
  static const SiteProfile fallback = SiteProfile(tagline: '全部内容');

  static const Map<String, SiteProfile> _profiles = {
    'akianime': SiteProfile(
      tagline: '新番速递',
      maxCrossAxisExtent: 176,
    ),
    '7sefun': SiteProfile(tagline: '番剧库', maxCrossAxisExtent: 168),
    '2kdm': SiteProfile(tagline: '影视库', maxCrossAxisExtent: 196),
    'dm84': SiteProfile(tagline: '每日更新', maxCrossAxisExtent: 172),
    'fsdm02': SiteProfile(tagline: '全站资源', maxCrossAxisExtent: 164),
    'girigirilove': SiteProfile(tagline: '番剧与专题', maxCrossAxisExtent: 184),
    'girigirilove_beta': SiteProfile(tagline: '新版站点', maxCrossAxisExtent: 188),
    'lm6': SiteProfile(tagline: '动漫与电影', maxCrossAxisExtent: 200),
    'mgnacg': SiteProfile(tagline: '资源目录', maxCrossAxisExtent: 160),
    'ios_mifun': SiteProfile(tagline: '视频库', maxCrossAxisExtent: 192),
    'xifanacg': SiteProfile(tagline: '动漫站点', maxCrossAxisExtent: 180),
    'tvtfun': SiteProfile(tagline: '今日更新', maxCrossAxisExtent: 204),
    'moonci': SiteProfile(tagline: '新番 · 番剧 · 剧场', maxCrossAxisExtent: 176),
    'silisili': SiteProfile(tagline: '弹幕站点', maxCrossAxisExtent: 168),
  };

  static SiteProfile forSource(String key) => _profiles[key] ?? fallback;
}
