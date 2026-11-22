import 'package:flutter/material.dart';

import 'package:baka/pages/browse/source_site_page.dart';
import 'package:baka/services/source/source_repository.dart';
import 'package:baka/source/source_registry.dart';
import 'package:baka/source/store/bundled_rule_store.dart';
import 'package:baka/widgets/source/source_widgets.dart';

/// 「浏览」页：只呈现源入口，进入本页不发起任何网络请求。
///
/// 条目来自源目录（与「图源管理」页同一份数据），因此内置源与用户自行
/// 添加的源都会出现；内容全部在 [SourceSitePage] 里按源、按栏目加载，
/// 避免多个源同时抓取把本机配置吃满。
class BrowsePage extends StatelessWidget {
  const BrowsePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _entries();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '源入口',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '共 ${entries.length} 个已启用源；只加载被打开的源。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    '没有已启用的源，请到「图源管理」里添加',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
                  // 与「图源管理」页同尺寸，保证两张网格观感一致（大屏 7 列）。
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent:
                        180 + MediaQuery.textScalerOf(context).scale(32),
                  ),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return SourceGridCard(
                      icon: SourceIcon(
                        name: entry.name,
                        iconUrl: entry.iconUrl,
                        baseUrl: entry.baseUrl,
                      ),
                      title: entry.name,
                      subtitle: entry.subtitle,
                      badge: entry.badge,
                      buttonLabel: '入口',
                      installed: true,
                      enabled: true,
                      onTap: () => _open(context, entry),
                      onButtonPressed: () => _open(context, entry),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// 内置源在前（按用户在「图源管理」里排好的顺序），自定义源在后。
  List<_BrowseEntry> _entries() {
    final entries = <_BrowseEntry>[];
    for (final source in sourceCatalog.enabledBuiltinSources) {
      final override = sourceCatalog.builtinOverrideById(source.key);
      final rule = BundledRuleStore.ruleFor(source.key);
      final baseUrl = _firstNonEmpty([override?.baseUrl, rule?.baseUrl]);
      entries.add(
        _BrowseEntry(
          sourceKey: source.key,
          name: override?.name ?? source.displayName,
          subtitle: _hostOf(baseUrl) ?? '内置源',
          accent: source.color,
          iconUrl: _firstNonEmpty([override?.iconUrl, rule?.iconUrl]),
          baseUrl: baseUrl,
          badge: '内置',
        ),
      );
    }
    for (final source in sourceCatalog.enabledCustomSources) {
      entries.add(
        _BrowseEntry(
          sourceKey: AdapterRegistry.customSourceKey(source.id),
          name: source.name,
          subtitle: _hostOf(source.baseUrl) ?? '自定义源',
          accent: _accentFor(source.name),
          iconUrl: _firstNonEmpty([source.iconUrl]),
          baseUrl: source.baseUrl,
          badge: '自定义',
        ),
      );
    }
    return entries;
  }

  void _open(BuildContext context, _BrowseEntry entry) {
    // Upstream 5.2.5 routes plain pages through MaterialPageRoute so the theme's
    // ContainerPageTransitionsBuilder can animate them.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SourceSitePage(
          sourceKey: entry.sourceKey,
          displayName: entry.name,
          accent: entry.accent,
          iconUrl: entry.iconUrl,
          baseUrl: entry.baseUrl,
        ),
      ),
    );
  }
}

class _BrowseEntry {
  const _BrowseEntry({
    required this.sourceKey,
    required this.name,
    required this.subtitle,
    required this.accent,
    required this.iconUrl,
    required this.baseUrl,
    required this.badge,
  });

  final String sourceKey;
  final String name;
  final String subtitle;
  final Color accent;
  final String? iconUrl;
  final String? baseUrl;
  final String badge;
}

String? _firstNonEmpty(List<String?> values) {
  for (final value in values) {
    if (value != null && value.trim().isNotEmpty) return value;
  }
  return null;
}

String? _hostOf(String? url) {
  if (url == null || url.isEmpty) return null;
  final host = Uri.tryParse(url)?.host ?? '';
  return host.isEmpty ? null : host;
}

/// 自定义源没有预设配色，按名称生成一个稳定的色相，避免每次进入都变色。
Color _accentFor(String seed) {
  final hash = seed.codeUnits.fold<int>(
    7,
    (acc, unit) => (acc * 31 + unit) & 0x7fffffff,
  );
  return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.5, 0.52).toColor();
}
