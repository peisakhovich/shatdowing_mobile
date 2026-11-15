import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

class UpdateService {
  static const String _releaseApiUrl =
      'https://api.github.com/repos/peisakhovich/shatdowing_mobile/releases/latest';

  static const String latestReleaseUrl =
      'https://github.com/peisakhovich/shatdowing_mobile/releases/latest';

  Future<UpdateCheckResult> checkForUpdates() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    final response = await http.get(
      Uri.parse(_releaseApiUrl),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'Shadowing-Mobile',
      },
    );

    if (response.statusCode == 404) {
      return UpdateCheckResult(
        currentVersion: currentVersion,
        release: null,
        hasUpdate: false,
        noReleases: true,
      );
    }

    if (response.statusCode != 200) {
      throw Exception('GitHub API error: HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final tagName = data['tag_name'] as String? ?? '';

    if (tagName.trim().isEmpty) {
      throw const FormatException('GitHub release has no tag_name.');
    }

    final releaseName = data['name'] as String? ?? tagName;
    final version = _normalizeVersion(tagName);
    final releaseNotes = data['body'] as String? ?? '';
    final assets = data['assets'] as List<dynamic>? ?? [];

    final apkAssets = assets
        .whereType<Map<String, dynamic>>()
        .where(
          (asset) => (asset['name'] as String? ?? '')
              .toLowerCase()
              .endsWith('.apk'),
        )
        .toList();

    final apkAsset = apkAssets.isEmpty ? null : apkAssets.first;
    final digest = apkAsset?['digest'] as String?;
    final sha256 = digest != null && digest.startsWith('sha256:')
        ? digest.substring('sha256:'.length)
        : null;

    final release = GitHubRelease(
      version: version,
      name: releaseName,
      notes: releaseNotes,
      pageUrl: data['html_url'] as String? ?? latestReleaseUrl,
      apkUrl: apkAsset?['browser_download_url'] as String?,
      apkSize: apkAsset?['size'] as int?,
      sha256Checksum: sha256,
    );

    return UpdateCheckResult(
      currentVersion: currentVersion,
      release: release,
      hasUpdate: _compareVersions(version, currentVersion) > 0,
      noReleases: false,
    );
  }

  Stream<OtaEvent> downloadAndInstall(GitHubRelease release) {
    final apkUrl = release.apkUrl;

    if (apkUrl == null || apkUrl.isEmpty) {
      throw Exception('APK file is not available in this release.');
    }

    if (!apkUrl.startsWith('https://')) {
      throw Exception('Invalid APK download URL.');
    }

    // OtaUpdate caches its event stream inside the instance.
    // Create a fresh instance for every download attempt.
    return OtaUpdate().execute(
      apkUrl,
      destinationFilename: 'shadowing_mobile_update.apk',
      sha256checksum: release.sha256Checksum,
      usePackageInstaller: false,
    );
  }

  String _normalizeVersion(String version) {
    return version.trim().replaceFirst(RegExp(r'^[vV]'), '');
  }

  int _compareVersions(String first, String second) {
    final firstParts = _versionParts(first);
    final secondParts = _versionParts(second);
    final length = firstParts.length > secondParts.length
        ? firstParts.length
        : secondParts.length;

    for (var i = 0; i < length; i++) {
      final a = i < firstParts.length ? firstParts[i] : 0;
      final b = i < secondParts.length ? secondParts[i] : 0;
      if (a != b) return a.compareTo(b);
    }

    return 0;
  }

  List<int> _versionParts(String version) {
    final normalized = _normalizeVersion(version);
    final core = normalized.split(RegExp(r'[-+]')).first;

    if (!RegExp(r'^\\d+(\\.\\d+)*$').hasMatch(core)) {
      throw FormatException('Unsupported version format: $version');
    }

    return core.split('.').map(int.parse).toList();
  }
}

class UpdateCheckResult {
  final String currentVersion;
  final GitHubRelease? release;
  final bool hasUpdate;
  final bool noReleases;

  const UpdateCheckResult({
    required this.currentVersion,
    required this.release,
    required this.hasUpdate,
    required this.noReleases,
  });
}

class GitHubRelease {
  final String version;
  final String name;
  final String notes;
  final String pageUrl;
  final String? apkUrl;
  final int? apkSize;
  final String? sha256Checksum;

  const GitHubRelease({
    required this.version,
    required this.name,
    required this.notes,
    required this.pageUrl,
    required this.apkUrl,
    required this.apkSize,
    required this.sha256Checksum,
  });
}
