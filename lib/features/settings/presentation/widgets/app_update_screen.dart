import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:opennutritracker/core/utils/app_update_service.dart';
import 'package:opennutritracker/generated/l10n.dart';

class AppUpdateScreen extends StatefulWidget {
  const AppUpdateScreen({super.key});
  @override
  State<AppUpdateScreen> createState() => _AppUpdateScreenState();
}

class _AppUpdateScreenState extends State<AppUpdateScreen> {
  final _service = AppUpdateService();
  PackageInfo? _installed;
  AppUpdateRelease? _release;
  File? _apk;
  bool _busy = false;
  bool _failed = false;
  bool _checked = false;
  bool _permissionNeeded = false;
  bool _installerOpened = false;
  double? _progress;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _service.close();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _failed = false;
      _checked = false;
    });
    try {
      final installed = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _installed = installed);
      final release = await _service.check();
      if (!mounted) return;
      setState(() {
        _release = release.isNewerThan(installed) ? release : null;
        _checked = true;
        _apk = null;
        _permissionNeeded = false;
        _installerOpened = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadAndInstall() async {
    final release = _release;
    if (release == null) return;
    setState(() {
      _busy = true;
      _failed = false;
      _installerOpened = false;
    });
    try {
      _apk ??= await _service.download(release, (progress) {
        if (mounted) setState(() => _progress = progress);
      });
      if (!mounted) return;
      final result = await _service.install(_apk!, release);
      if (mounted) {
        setState(() {
          _permissionNeeded = result == 'permission_required';
          _installerOpened = result == 'opened';
          _failed = !_permissionNeeded && !_installerOpened;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.appUpdateTitle)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.system_update_rounded, size: 56),
          const SizedBox(height: 20),
          Text(
            s.appUpdateCurrentVersion,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Text(
            _installed == null
                ? '—'
                : '${_installed!.version} (${_installed!.buildNumber})',
          ),
          const SizedBox(height: 20),
          if (_busy) ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 12),
            Text(
              _progress == null ? s.appUpdateChecking : s.appUpdateDownloading,
            ),
          ],
          if (_failed) Text(s.appUpdateFailed),
          if (_checked && _release == null) Text(s.appUpdateLatest),
          if (_release case final release?) ...[
            Text(
              s.appUpdateAvailable,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${release.version} (${release.buildNumber}) · ${(release.bytes / 1024 / 1024).toStringAsFixed(1)} MB',
            ),
            const SizedBox(height: 12),
            if (_permissionNeeded) Text(s.appUpdateInstallPermission),
            if (_installerOpened) Text(s.appUpdateInstallerOpened),
            const SizedBox(height: 12),
            Semantics(
              identifier: 'app-update-install',
              child: FilledButton.icon(
                onPressed: _busy || !Platform.isAndroid
                    ? null
                    : _downloadAndInstall,
                icon: const Icon(Icons.download_rounded),
                label: Text(
                  _apk == null ? s.appUpdateDownload : s.appUpdateInstall,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Semantics(
            identifier: 'app-update-check',
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _check,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(s.appUpdateCheck),
            ),
          ),
        ],
      ),
    );
  }
}
