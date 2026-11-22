import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class AppUpdateRelease {
  final String version;
  final int buildNumber;
  final String packageName;
  final int bytes;
  final String sha256Hex;
  final Uri apkUrl;

  const AppUpdateRelease({
    required this.version,
    required this.buildNumber,
    required this.packageName,
    required this.bytes,
    required this.sha256Hex,
    required this.apkUrl,
  });

  factory AppUpdateRelease.parse(Map<String, dynamic> json, Uri apkUrl) {
    final version = json['version'];
    final build = json['versionCode'];
    final bytes = json['bytes'];
    final hash = json['sha256'];
    final package = json['packageName'];
    if (json['schemaVersion'] != 1 ||
        version is! String ||
        !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version) ||
        build is! int ||
        build <= 0 ||
        bytes is! int ||
        bytes <= 0 ||
        bytes > AppUpdateService.maxApkBytes ||
        package is! String ||
        package.isEmpty ||
        hash is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('Invalid update metadata');
    }
    return AppUpdateRelease(
      version: version,
      buildNumber: build,
      packageName: package,
      bytes: bytes,
      sha256Hex: hash,
      apkUrl: apkUrl,
    );
  }

  bool isNewerThan(PackageInfo installed) {
    if (packageName != installed.packageName ||
        buildNumber <= (int.tryParse(installed.buildNumber) ?? 0)) {
      return false;
    }
    final current = installed.version.split('.').map(int.tryParse).toList();
    final next = version.split('.').map(int.parse).toList();
    if (current.length != 3 || current.any((part) => part == null)) {
      return false;
    }
    for (var i = 0; i < 3; i++) {
      if (next[i] != current[i]) return next[i] > current[i]!;
    }
    return true;
  }
}

class AppUpdateService {
  static const maxApkBytes = 160 * 1024 * 1024;
  static const _repository = 'daoshi818-crypto/chiyoushu-food-data';
  static const _channel = MethodChannel('diet-diary/app-update');
  final http.Client _client;
  final Future<Directory> Function() _directory;

  AppUpdateService({
    http.Client? client,
    Future<Directory> Function()? directory,
  }) : _client = client ?? http.Client(),
       _directory = directory ?? getTemporaryDirectory;

  Future<Map<String, dynamic>> _json(Uri uri) async {
    final response = await _client
        .send(
          http.Request('GET', uri)
            ..headers['Accept'] = 'application/vnd.github+json',
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw HttpException('Update request failed');
    }
    final data = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 20),
    )) {
      if (data.length + chunk.length > 1024 * 1024) {
        throw const FormatException('Update response too large');
      }
      data.addAll(chunk);
    }
    return jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
  }

  Uri _assetUrl(Map<String, dynamic> asset) {
    final url = Uri.parse(asset['browser_download_url'] as String);
    if (url.scheme != 'https' ||
        url.host != 'github.com' ||
        !url.path.startsWith('/$_repository/releases/download/')) {
      throw const FormatException('Invalid update asset URL');
    }
    return url;
  }

  Future<AppUpdateRelease> check() async {
    try {
      return await _checkDirect();
    } on HttpException {
      return _checkApi();
    } on TimeoutException {
      return _checkApi();
    } on http.ClientException {
      return _checkApi();
    } on SocketException {
      return _checkApi();
    }
  }

  Future<AppUpdateRelease> _checkDirect() async {
    final metadata = await _json(
      Uri.https(
        'github.com',
        '/$_repository/releases/latest/download/UPDATE.json',
      ),
    );
    final build = metadata['versionCode'];
    if (build is! int || build <= 1000) {
      throw const FormatException('Invalid update build');
    }
    final tag = metadata['releaseTag'] ?? 'apk-${build - 1000}';
    if (tag is! String ||
        !RegExp(r'^apk-[1-9][0-9]*$').hasMatch(tag) ||
        int.parse(tag.substring(4)) + 1000 != build) {
      throw const FormatException('Invalid update release tag');
    }
    return AppUpdateRelease.parse(
      metadata,
      Uri.https(
        'github.com',
        '/$_repository/releases/download/$tag/diet-diary.apk',
      ),
    );
  }

  Future<AppUpdateRelease> _checkApi() async {
    final release = await _json(
      Uri.https('api.github.com', '/repos/$_repository/releases/latest'),
    );
    if (release['draft'] == true || release['prerelease'] == true) {
      throw const FormatException('Unpublished update');
    }
    final assets = (release['assets'] as List).cast<Map<String, dynamic>>();
    final manifest = assets.singleWhere(
      (asset) => asset['name'] == 'UPDATE.json',
    );
    final apk = assets.singleWhere(
      (asset) => asset['name'] == 'diet-diary.apk',
    );
    final result = AppUpdateRelease.parse(
      await _json(_assetUrl(manifest)),
      _assetUrl(apk),
    );
    if (result.bytes != apk['size']) {
      throw const FormatException('APK size mismatch');
    }
    return result;
  }

  Future<File> download(
    AppUpdateRelease release,
    void Function(double) progress,
  ) async {
    final directory = Directory('${(await _directory()).path}/app-updates');
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}/diet-diary-${release.buildNumber}.apk',
    );
    if (await file.exists()) {
      if (await _valid(file, release)) {
        progress(1);
        return file;
      }
      await file.delete();
    }
    final partial = File('${file.path}.part');
    final sink = partial.openWrite();
    try {
      final response = await _client
          .send(http.Request('GET', release.apkUrl))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200 ||
          (response.contentLength != null &&
              response.contentLength != release.bytes)) {
        throw const HttpException('APK download failed');
      }
      var count = 0;
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        count += chunk.length;
        if (count > release.bytes || count > maxApkBytes) {
          throw const FormatException('APK download too large');
        }
        sink.add(chunk);
        progress(count / release.bytes);
      }
      await sink.close();
      if (!await _valid(partial, release)) {
        throw const FormatException('APK checksum mismatch');
      }
      return await partial.rename(file.path);
    } catch (_) {
      await sink.close();
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }

  Future<bool> _valid(File file, AppUpdateRelease release) async =>
      await file.length() == release.bytes &&
      (await sha256.bind(file.openRead()).first).toString() ==
          release.sha256Hex;

  Future<String> install(File file, AppUpdateRelease release) async =>
      await _channel.invokeMethod<String>('install', {
        'path': file.path,
        'versionCode': release.buildNumber,
        'sha256': release.sha256Hex,
      }) ??
      'failed';

  void close() => _client.close();
}
