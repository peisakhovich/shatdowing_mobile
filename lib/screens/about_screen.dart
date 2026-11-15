import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_service.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  static const String _mobileReadmeUrl =
      'https://github.com/peisakhovich/shatdowing_mobile#readme';
  static const String _desktopReadmeUrl =
      'https://github.com/peisakhovich/ShatdowingPlayer_SA_03#readme';

  final UpdateService _updateService = UpdateService();

  String _currentVersion = '…';
  bool _checking = false;
  bool _downloading = false;
  double? _downloadProgress;
  String? _statusMessage;
  UpdateCheckResult? _checkResult;
  StreamSubscription<OtaEvent>? _downloadSubscription;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _currentVersion = info.version);
    } catch (_) {
      if (!mounted) return;
      setState(() => _currentVersion = 'Unavailable');
    }
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the link.')),
      );
    }
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _checking = true;
      _statusMessage = null;
      _checkResult = null;
    });

    try {
      final result = await _updateService.checkForUpdates();
      if (!mounted) return;

      setState(() {
        _checkResult = result;
        _currentVersion = result.currentVersion;
        _checking = false;

        if (result.noReleases) {
          _statusMessage = 'No public releases have been published yet.';
        } else if (!result.hasUpdate) {
          _statusMessage = 'You are using the latest version.';
        } else if (result.release?.apkUrl == null) {
          _statusMessage =
              'A new version is available, but its APK is not attached yet.';
        } else {
          _statusMessage = 'A new version is available.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _statusMessage = 'Could not check for updates: $error';
      });
    }
  }

  void _downloadAndInstall() {
    final release = _checkResult?.release;
    if (release == null || release.apkUrl == null || _downloading) return;

    setState(() {
      _downloading = true;
      _downloadProgress = null;
      _statusMessage = 'Downloading update…';
    });

    try {
      _downloadSubscription = _updateService
          .downloadAndInstall(release)
          .listen(
        (event) {
          if (!mounted) return;

          setState(() {
            switch (event.status) {
              case OtaStatus.DOWNLOADING:
                final rawValue = event.value ?? '';
                final number = double.tryParse(
                  rawValue.replaceAll('%', '').trim(),
                );
                if (number != null) {
                  _downloadProgress =
                      (number > 1 ? number / 100 : number).clamp(0.0, 1.0);
                }
                _statusMessage = 'Downloading update…';
                break;

              case OtaStatus.INSTALLING:
                _downloading = false;
                _downloadProgress = 1;
                _statusMessage =
                    'Download complete. Follow the Android installer instructions.';
                break;

              case OtaStatus.INSTALLATION_DONE:
                _downloading = false;
                _statusMessage = 'Installation completed.';
                break;

              case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                _downloading = false;
                _statusMessage =
                    'Allow this app to install unknown apps in Android settings, then try again.';
                break;

              case OtaStatus.DOWNLOAD_ERROR:
              case OtaStatus.CHECKSUM_ERROR:
              case OtaStatus.INSTALLATION_ERROR:
              case OtaStatus.INTERNAL_ERROR:
              case OtaStatus.ALREADY_RUNNING_ERROR:
                _downloading = false;
                _statusMessage =
                    'Update failed: ${event.value ?? event.status.name}';
                break;

              case OtaStatus.CANCELED:
                _downloading = false;
                _statusMessage = 'Update canceled.';
                break;
            }
          });
        },
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _downloading = false;
            _statusMessage = 'Update failed: $error';
          });
        },
        onDone: () {
          if (!mounted) return;
          if (_downloading) {
            setState(() {
              _downloading = false;
              _statusMessage ??= 'Update download finished.';
            });
          }
        },
      );
    } catch (error) {
      setState(() {
        _downloading = false;
        _statusMessage = 'Could not start update: $error';
      });
    }
  }

  Widget _buildReadmeLink(String label, String url) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.open_in_new),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openLink(url),
    );
  }

  Widget _buildUpdateSection() {
    final result = _checkResult;
    final release = result?.release;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Software updates',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _checking || _downloading ? null : _checkForUpdates,
              icon: _checking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.system_update),
              label: const Text('Check for Updates'),
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 12),
              Text(_statusMessage!),
            ],
            if (result?.hasUpdate == true && release != null) ...[
              const SizedBox(height: 12),
              Text(
                'Version ${release.version} is available',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (release.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Release notes',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                SelectableText(release.notes),
              ],
              if (release.apkUrl != null) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _downloading ? null : _downloadAndInstall,
                  icon: const Icon(Icons.download),
                  label: const Text('Download Update'),
                ),
                if (_downloading) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: _downloadProgress),
                ],
              ],
              TextButton(
                onPressed: () => _openLink(release.pageUrl),
                child: const Text('View release on GitHub'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 8),
                Center(
                  child: Image.asset(
                    'assets/icons/sls256.png',
                    width: 104,
                    height: 104,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Shadowing Mobile',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Version $_currentVersion',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Shadowing Mobile is a thin mobile client for Sound Language Studio. It provides access to your language-learning sessions on mobile devices, while the main application and backend services handle the preparation and management of learning content.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        _buildReadmeLink('Mobile application README',
                            _mobileReadmeUrl),
                        const Divider(height: 1),
                        _buildReadmeLink('Desktop application README',
                            _desktopReadmeUrl),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          'Download the app',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Scan this QR code to open the latest GitHub release.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        QrImageView(
                          data: UpdateService.latestReleaseUrl,
                          size: 176,
                          backgroundColor: Colors.white,
                        ),
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: () =>
                              _openLink(UpdateService.latestReleaseUrl),
                          child: const Text('Open GitHub Releases'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildUpdateSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
