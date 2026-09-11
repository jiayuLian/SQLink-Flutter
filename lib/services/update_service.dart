import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 更新检查的结果。
enum UpdateStatus {
  /// 已是最新（或无法判断新旧，宁可不说）。
  upToDate,

  /// 有新版本可用。
  available,

  /// 检查失败（网络 / 服务端异常），调用方应给一句提示而不是谎报「已是最新」。
  failed,
}

/// 一次更新检查的产物。
class UpdateInfo {
  /// 远端最新版本名，如 `1.0.1`。
  final String latestVersion;

  /// 远端最新构建号，如 `1`（发版时手动 +1，平时不变）。
  final int latestBuild;

  /// 最新的更新记录正文（Markdown 原文，只取最近一个日期小节）。
  final String notes;

  /// APK 直链；发行版里找不到 .apk 资产时为 null。
  final String? apkUrl;

  /// 发行版页面地址（兜底跳转地址）。
  final String releaseUrl;

  /// 本机安装的版本名与构建号。
  final String currentVersion;
  final int currentBuild;

  const UpdateInfo({
    required this.latestVersion,
    required this.latestBuild,
    required this.notes,
    required this.apkUrl,
    required this.releaseUrl,
    required this.currentVersion,
    required this.currentBuild,
  });

  /// 完整版本标签，如 `1.0.1+1`；无构建号时只显示版本名。
  String get latestLabel =>
      latestBuild > 0 ? '$latestVersion+$latestBuild' : latestVersion;

  String get currentLabel =>
      currentBuild > 0 ? '$currentVersion+$currentBuild' : currentVersion;

  /// Android 上优先给 APK 直链（一点即下）；没有资产时回落到发行版页面。
  String get primaryUrl => apkUrl ?? releaseUrl;
}

/// 更新检查结果（状态 + 详情 + 失败原因）。
class UpdateCheckResult {
  final UpdateStatus status;
  final UpdateInfo? info;
  final String? error;

  const UpdateCheckResult(this.status, {this.info, this.error});
}

/// 更新检查服务：向 GitHub Releases 问一句「最新版本号是多少」，
/// 与本机安装的版本号比对。
///
/// 设计取舍（对齐本项目「零后端」的定位）：
/// - 直接匿名请求 GitHub 公共 API，不需要任何服务器与鉴权；
/// - 超时 8 秒、任何异常都只返回 failed，绝不阻塞或影响 App 本身；
/// - 节流交给调用方：每天最多自动检查一次，同一个版本只弹一次提示。
///
/// 版本号由人控制（非 CI 自动 +1）：平时改 bug / 加功能但未测完，pubspec
/// 的版本号保持不变，App 不会提示更新；待用户确认「发版」后，我才手动把
/// pubspec 的版本号 +1 并推送，App 端「检查更新」才会提示。
class UpdateService {
  static const String _apiUrl =
      'https://api.github.com/repos/jiayuLian/SQLink-Flutter/releases/tags/latest';
  static const String _releasePage =
      'https://github.com/jiayuLian/SQLink-Flutter/releases/tag/latest';

  static const String _prefLastCheck = 'sqlink.update.lastCheck';
  static const String _prefNotified = 'sqlink.update.notifiedVersion';

  static const Duration _timeout = Duration(seconds: 8);

  /// 发行版正文里的隐藏标记，由 CI 生成正文时写入（对用户不可见）。
  /// 版本号整体取自 pubspec.yaml，因此构建号可有可无（? 让无 +N 也兼容）。
  static final RegExp _markerRe = RegExp(
    r'<!--\s*app-version:\s*v?([0-9]+(?:\.[0-9]+)*)(?:\+([0-9]+))?\s*-->',
  );

  /// 可见版本行的兜底匹配（万一标记缺失，仍能解析出来）。
  static final RegExp _visibleRe = RegExp(
    r'当前版本：\*\*v?([0-9]+(?:\.[0-9]+)*)(?:\+([0-9]+))?\*\*',
  );

  /// 读取本机安装的版本名 / 构建号（来自打包时写入的平台版本信息）。
  static Future<({String version, int build})> localVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return (
        version: info.version.isEmpty ? '1.0.0' : info.version,
        build: int.tryParse(info.buildNumber) ?? 0,
      );
    } catch (_) {
      return (version: '1.0.0', build: 0);
    }
  }

  /// 请求发行版并判断是否有新版本。
  static Future<UpdateCheckResult> check() async {
    final local = await localVersion();
    // 拿不到本机版本名就无法判断新旧，直接按「已是最新」处理，避免误报。
    if (local.version.isEmpty) {
      return const UpdateCheckResult(UpdateStatus.upToDate);
    }

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = _timeout;
      final request = await client.getUrl(Uri.parse(_apiUrl)).timeout(_timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'SQLink-Flutter');
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != 200) {
        return UpdateCheckResult(
          UpdateStatus.failed,
          error: '服务器返回 ${response.statusCode}',
        );
      }
      final body = await response.transform(utf8.decoder).join().timeout(_timeout);
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        return const UpdateCheckResult(UpdateStatus.failed, error: '返回内容无法解析');
      }

      final text = (decoded['body'] as String?) ?? '';
      final remote = _parseVersion(text);
      if (remote == null) {
        // 正文里没有版本标记（旧发行版或格式异常）：不猜，按已是最新处理。
        return const UpdateCheckResult(UpdateStatus.upToDate);
      }

      final info = UpdateInfo(
        latestVersion: remote.version,
        latestBuild: remote.build,
        notes: _latestSection(text),
        apkUrl: _findApkUrl(decoded['assets']),
        releaseUrl: (decoded['html_url'] as String?) ?? _releasePage,
        currentVersion: local.version,
        currentBuild: local.build,
      );

      return UpdateCheckResult(
        _isNewer(remote.version, remote.build, local.version, local.build)
            ? UpdateStatus.available
            : UpdateStatus.upToDate,
        info: info,
      );
    } on TimeoutException {
      return const UpdateCheckResult(UpdateStatus.failed, error: '网络超时，请稍后重试');
    } on SocketException {
      return const UpdateCheckResult(UpdateStatus.failed,
          error: '网络不可用，或无法访问 GitHub');
    } catch (e) {
      return UpdateCheckResult(UpdateStatus.failed, error: '检查更新失败：$e');
    } finally {
      client?.close(force: true);
    }
  }

  /// 启动时是否该静默检查（每天最多一次，避免每次开 App 都打一次网络）。
  static Future<bool> shouldAutoCheck() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefLastCheck) != _todayKey();
  }

  /// 记录本次检查日期。仅在检查成功（非 failed）时调用，
  /// 这样断网当天仍有机会在下次启动时补上。
  static Future<void> markChecked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefLastCheck, _todayKey());
  }

  /// 该版本（版本名 + 构建号）是否已经提示过（同一个版本只弹一次窗）。
  /// 注意：不能只按构建号去重——发版时可能只升版本名、构建号保持 +1，
  /// 那样构建号不变会误判「已提示过」而漏弹。故按完整版本标签去重。
  static Future<bool> alreadyNotified(String label) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_prefNotified) ?? '') == label;
  }

  static Future<void> markNotified(String label) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefNotified, label);
  }

  /// 从正文里解析（版本名, 构建号）：先找隐藏标记，再退回可见版本行。
  static ({String version, int build})? _parseVersion(String body) {
    for (final re in <RegExp>[_markerRe, _visibleRe]) {
      final m = re.firstMatch(body);
      if (m == null) continue;
      final rawBuild = m.group(2);
      final build = rawBuild == null ? 0 : (int.tryParse(rawBuild) ?? 0);
      final version = m.group(1);
      if (version != null && version.isNotEmpty) {
        return (version: version, build: build);
      }
    }
    return null;
  }

  /// 版本名按「数字段」逐段比较（避免 "1.0.10" < "1.0.2" 这类字典序误判）。
  /// 返回 >0 表示 a 比 b 新；=0 时再用构建号兜底。
  static int _compareVersion(String a, String b) {
    final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    while (pa.length < pb.length) pa.add(0);
    while (pb.length < pa.length) pb.add(0);
    for (var i = 0; i < pa.length; i++) {
      if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
    }
    return 0;
  }

  /// 远端是否比本机新：版本名更大，或版本名相同且构建号更大。
  static bool _isNewer(
    String remoteVersion, int remoteBuild, String localVersion, int localBuild) {
    final cmp = _compareVersion(remoteVersion, localVersion);
    return cmp > 0 || (cmp == 0 && remoteBuild > localBuild);
  }

  /// 取「更新记录」里最近一个日期小节（`### 日期` 到下一个 `###` 之前）。
  static String _latestSection(String body) {
    const heading = '## 更新记录';
    final start = body.indexOf(heading);
    if (start < 0) return '';
    final lines = body.substring(start + heading.length).split('\n');
    final picked = <String>[];
    var inside = false;
    for (final line in lines) {
      final trimmed = line.trimRight();
      if (trimmed.startsWith('### ')) {
        if (inside) break; // 到了下一个日期小节，收工
        inside = true;
      }
      if (inside) picked.add(trimmed);
    }
    final text = picked.join('\n').trim();
    // 弹窗里放不下太长的内容，超长截断（更新记录本身也很少超过这个量）。
    return text.length > 1200 ? '${text.substring(0, 1200)}…' : text;
  }

  /// 在发行版资产里找 APK 直链（Android 一点即下）。
  static String? _findApkUrl(dynamic assets) {
    if (assets is! List) return null;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = (asset['name'] as String?)?.toLowerCase() ?? '';
      if (!name.endsWith('.apk')) continue;
      final url = asset['browser_download_url'] as String?;
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  static String _todayKey() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }
}
