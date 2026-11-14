import 'dart:io';

import 'package:baka/api/post.dart';
import 'package:baka/core/api_transport.dart';
import 'package:baka/core/content_visibility.dart';
import 'package:baka/instance.dart';
import 'package:baka/models/update_info.dart';
import 'package:baka/widgets/dialog/update_dialog.dart';
import 'package:flutter/foundation.dart';

const _kAnnouncementContentKey = 'last_announcement_content';

/// 定制版（B9 补完）：彻底不发官方版本检查请求。
/// B9 只把 hasUpdate/forceUpdate 置 false，仍会请求 version.anibaka.com；
/// 该域名在当前网络下被解析到 1.1.1.1（无效地址），每次进首页都白等
/// 约 21 秒并触发全局「网络连接失败」提示。设为 false 可恢复官方检查
/// （不推荐：官方安装包会覆盖定制版）。
const bool disableOfficialUpdateCheck = true;

/// ????????,remote ? local ???? true?
bool _isVersionNewer(String remoteVersion, String localVersion) {
  var remoteOffset = 0;
  var localOffset = 0;
  while (remoteOffset < remoteVersion.length ||
      localOffset < localVersion.length) {
    final remoteEnd = remoteVersion.indexOf('.', remoteOffset);
    final localEnd = localVersion.indexOf('.', localOffset);
    final r =
        int.tryParse(
          remoteVersion.substring(
            remoteOffset,
            remoteEnd < 0 ? remoteVersion.length : remoteEnd,
          ),
        ) ??
        0;
    final l =
        int.tryParse(
          localVersion.substring(
            localOffset,
            localEnd < 0 ? localVersion.length : localEnd,
          ),
        ) ??
        0;
    if (r > l) return true;
    if (r < l) return false;
    remoteOffset = remoteEnd < 0 ? remoteVersion.length : remoteEnd + 1;
    localOffset = localEnd < 0 ? localVersion.length : localEnd + 1;
  }
  return false;
}

class VersionService {
  static Future<void>? _checkTask;

  static String get _currentPlatform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    return 'unknown';
  }

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
    final platformConfig = platforms[_currentPlatform] as Map<String, dynamic>?;
    if (platformConfig == null) {
      return UpdateInfo(
        hasUpdate: false,
        forceUpdate: false,
        changelog: '',
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

  static Future<void> checkAndShowUpdate() => _checkTask ??=
      _checkAndShowUpdate().whenComplete(() => _checkTask = null);

  static Future<void> _checkAndShowUpdate() async {
    UpdateInfo? updateInfo;
    try {
      updateInfo = await checkUpdateInfo();
    } catch (e) {
      debugPrint('??????: $e');
    }

    String announcementContent = '';
    try {
      final announcement = await getPostDetail(1);
      announcementContent = announcement['content'] as String? ?? '';
      await Instances.sp.setString(
        _kAnnouncementContentKey,
        announcementContent,
      );
    } catch (e) {
      debugPrint('??????: $e');
      announcementContent =
          Instances.sp.getString(_kAnnouncementContentKey) ?? '';
    }

    final hasUpdate = false;
    final forceUpdate = false;
    final announcementId = 'announcement_$host';
    if (contentVisibility.isDismissed(
      Instances.sp,
      id: announcementId,
      content: announcementContent,
    )) {
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
      await contentVisibility.dismiss(
        Instances.sp,
        id: announcementId,
        content: announcementContent,
      );
    }
  }
}
