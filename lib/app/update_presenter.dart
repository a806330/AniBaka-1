import 'dart:io';
import 'dart:math' as math;

import 'package:baka/api/post.dart';
import 'package:baka/core/api_transport.dart';
import 'package:baka/core/app_logger.dart';
import 'package:baka/core/content_filter.dart';
import 'package:baka/instance.dart';
import 'package:baka/models/update_info.dart';
import 'package:baka/widgets/dialog/update_dialog.dart';

const _kAnnouncementContentKey = 'last_announcement_content';

/// 定制版：完全不请求官方版本接口。
///
/// 官方版本域名 version.anibaka.com 在当前网络下常被解析到无效地址，每次进
/// 首页会白等约 20 秒并弹出「网络连接失败」。置为 false 可恢复官方检查，但
/// 官方安装包会整体覆盖定制版，所以这里默认关闭。
const bool disableOfficialUpdateCheck = true;


bool _isVersionNewer(String remote, String local) {
  if (remote == local) return false;
  final latest = remote.split('.');
  final installed = local.split('.');
  for (var i = 0; i < math.max(latest.length, installed.length); i++) {
    final r = i < latest.length ? int.tryParse(latest[i]) ?? 0 : 0;
    final l = i < installed.length ? int.tryParse(installed[i]) ?? 0 : 0;
    if (r != l) return r > l;
  }
  return false;
}

abstract final class VersionService {
  static Future<void>? _checkTask;

  static Future<UpdateInfo> checkUpdateInfo() async {
    final localVersion = Instances.appVersion;
    // 定制版：官方更新检查已禁用，直接返回「无更新」，不再发起网络请求。
    // 公告获取（getPostDetail）在 _checkAndShowUpdate 中照常执行，不受影响。
    if (disableOfficialUpdateCheck) {
      return UpdateInfo(
        hasUpdate: false,
        forceUpdate: false,
        changelog: '',
        downloadUrl: '',
        latestVersion: localVersion,
      );
    }
    final appInfo = await apiTransport.getJson<Map<String, dynamic>>(
      'https://version.anibaka.com/',
    );

    final appUpdate = appInfo['app_update'] as Map<String, dynamic>;
    final platforms = appUpdate['platforms'] as Map<String, dynamic>;
    final platformConfig =
        platforms[Platform.operatingSystem] as Map<String, dynamic>?;
    if (platformConfig == null) {
      return UpdateInfo(
        hasUpdate: false,
        downloadUrl: '',
        latestVersion: localVersion,
      );
    }
    final latestVersion = platformConfig['latest_version'] as String;

    return UpdateInfo(
      hasUpdate: _isVersionNewer(latestVersion, localVersion),
      forceUpdate: platformConfig['force'] as bool,
      changelog: platformConfig['changelog'] as String,
      downloadUrl: platformConfig['download_url'] as String,
      latestVersion: latestVersion,
    );
  }

  static Future<void> checkAndShowUpdate([UpdateInfo? info]) => _checkTask ??=
      _checkAndShowUpdate(info).whenComplete(() => _checkTask = null);

  static Future<void> _checkAndShowUpdate(UpdateInfo? updateInfo) async {
    try {
      updateInfo ??= await checkUpdateInfo();
    } catch (e) {
      Log.w('Update', '版本检查失败: $e');
    }

    final cached = Instances.sp.getString(_kAnnouncementContentKey) ?? '';
    var announcementContent = cached;
    try {
      final announcement = await getPostDetail(1);
      announcementContent = announcement['content'] as String? ?? '';
      if (announcementContent != cached) {
        await Instances.sp.setString(
          _kAnnouncementContentKey,
          announcementContent,
        );
      }
    } catch (e) {
      Log.w('Update', '公告获取失败: $e');
    }

    final hasUpdate = false;
    final forceUpdate = false;
    final announcementId = 'announcement_$host';
    if (contentVisibility.isDismissed(announcementId, announcementContent)) {
      announcementContent = '';
    }

    if (!forceUpdate && !hasUpdate && announcementContent.isEmpty) {
      return;
    }

    final shown = await showAnnouncementDialog(
      content: announcementContent,
      updateInfo:
          updateInfo ??
          UpdateInfo(hasUpdate: false, latestVersion: Instances.appVersion),
    );
    if (shown && announcementContent.isNotEmpty) {
      await contentVisibility.dismiss(announcementId, announcementContent);
    }
  }
}
