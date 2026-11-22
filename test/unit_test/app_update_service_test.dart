import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:opennutritracker/core/utils/app_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const package = 'com.opennutritracker.ont.opennutritracker';
  final bytes = utf8.encode('apk-fixture');
  Map<String, dynamic> metadata() => {
    'schemaVersion': 1,
    'version': '2.8.1',
    'versionCode': 1013,
    'packageName': package,
    'bytes': bytes.length,
    'sha256': sha256.convert(bytes).toString(),
  };
  final apkUrl = Uri.parse(
    'https://github.com/daoshi818-crypto/diet-diary/releases/download/apk-13/diet-diary.apk',
  );
  PackageInfo installed(String version, int build) => PackageInfo(
    appName: 'Diary',
    packageName: package,
    version: version,
    buildNumber: build.toString(),
  );

  test('compares release version and build without allowing downgrades', () {
    final release = AppUpdateRelease.parse(metadata(), apkUrl);
    expect(release.isNewerThan(installed('2.8.0', 1012)), isTrue);
    expect(release.isNewerThan(installed('2.8.1', 1012)), isTrue);
    expect(release.isNewerThan(installed('2.8.1', 1013)), isFalse);
    expect(release.isNewerThan(installed('2.8.2', 1000)), isFalse);
    expect(release.isNewerThan(installed('2.8.0', 1014)), isFalse);
  });

  test('rejects malformed metadata and oversized APK', () {
    for (final changed in [
      {'schemaVersion': 2},
      {'sha256': 'bad'},
      {'bytes': 0},
      {'bytes': AppUpdateService.maxApkBytes + 1},
      {'versionCode': -1},
      {'version': 'garbage'},
    ]) {
      expect(
        () => AppUpdateRelease.parse({...metadata(), ...changed}, apkUrl),
        throwsFormatException,
      );
    }
  });

  test('reads published metadata and validates asset size', () async {
    final service = AppUpdateService(
      client: MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response(
            jsonEncode({
              'draft': false,
              'prerelease': false,
              'assets': [
                {
                  'name': 'UPDATE.json',
                  'browser_download_url': apkUrl
                      .resolve('UPDATE.json')
                      .toString(),
                },
                {
                  'name': 'diet-diary.apk',
                  'browser_download_url': apkUrl.toString(),
                  'size': bytes.length,
                },
              ],
            }),
            200,
          );
        }
        return http.Response(jsonEncode(metadata()), 200);
      }),
    );
    addTearDown(service.close);
    expect((await service.check()).buildNumber, 1013);
  });

  test(
    'downloads only a complete checksum-valid APK and reuses it on install retry',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'app-update-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      var requests = 0;
      final service = AppUpdateService(
        directory: () async => directory,
        client: MockClient((_) async {
          requests++;
          return http.Response.bytes(bytes, 200);
        }),
      );
      addTearDown(service.close);
      final release = AppUpdateRelease.parse(metadata(), apkUrl);
      final progress = <double>[];
      final file = await service.download(release, progress.add);
      expect(await file.readAsBytes(), bytes);
      expect(progress.last, 1);
      await service.download(release, (_) {});
      expect(requests, 1);
    },
  );

  test('corrupt download is removed and never becomes installable', () async {
    final directory = await Directory.systemTemp.createTemp('app-update-bad');
    addTearDown(() => directory.delete(recursive: true));
    final service = AppUpdateService(
      directory: () async => directory,
      client: MockClient(
        (_) async => http.Response.bytes(List.filled(bytes.length, 0), 200),
      ),
    );
    addTearDown(service.close);
    await expectLater(
      service.download(AppUpdateRelease.parse(metadata(), apkUrl), (_) {}),
      throwsFormatException,
    );
    expect(
      await Directory('${directory.path}/app-updates').list().toList(),
      isEmpty,
    );
  });

  test(
    'installer receives verified path, version, checksum and permission state',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('diet-diary/app-update');
      MethodCall? captured;
      messenger.setMockMethodCallHandler(channel, (call) async {
        captured = call;
        return 'permission_required';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final service = AppUpdateService();
      addTearDown(service.close);
      expect(
        await service.install(
          File('/cache/app-updates/test.apk'),
          AppUpdateRelease.parse(metadata(), apkUrl),
        ),
        'permission_required',
      );
      expect(captured!.method, 'install');
      expect(captured!.arguments['versionCode'], 1013);
      expect(captured!.arguments['sha256'], metadata()['sha256']);
    },
  );
}
