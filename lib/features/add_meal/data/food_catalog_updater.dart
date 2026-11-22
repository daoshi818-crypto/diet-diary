import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/chinese_food_data_source.dart';

class FoodCatalogManifest {
  final Map<String, dynamic> json;
  final int sequence;
  final String version;
  final String commit;
  final String hash;
  final int bytes;
  final int count;
  FoodCatalogManifest._(
    this.json,
    this.sequence,
    this.version,
    this.commit,
    this.hash,
    this.bytes,
    this.count,
  );

  factory FoodCatalogManifest.parse(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    final f = j['file'] as Map;
    if (j['manifest_version'] != 1 ||
        j['dataset_id'] != 'chiyoushu-cn-foods' ||
        j['catalog_schema_version'] != 1 ||
        f['path'] != 'dist/catalog.json' ||
        j['release_seq'] is! int ||
        (j['release_seq'] as int) < 1 ||
        j['catalog_version'] is! String ||
        (j['catalog_version'] as String).isEmpty ||
        !RegExp(
          r'^[a-f0-9]{40}$',
        ).hasMatch(j['source_commit'] as String? ?? '') ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(f['sha256'] as String? ?? '') ||
        f['bytes'] is! int ||
        (f['bytes'] as int) < 1 ||
        (f['bytes'] as int) > FoodCatalogUpdater.maxCatalogBytes ||
        f['food_count'] is! int ||
        (f['food_count'] as int) < 1 ||
        DateTime.tryParse(j['published_at'] as String? ?? '') == null) {
      throw const FormatException('Unsupported food catalogue manifest');
    }
    return FoodCatalogManifest._(
      j,
      j['release_seq'],
      j['catalog_version'],
      j['source_commit'],
      f['sha256'],
      f['bytes'],
      f['food_count'],
    );
  }

  bool sameContent(FoodCatalogManifest other) =>
      hash == other.hash &&
      bytes == other.bytes &&
      count == other.count &&
      commit == other.commit &&
      version == other.version;
}

enum FoodCatalogUpdatePhase {
  idle,
  checking,
  downloading,
  current,
  updated,
  failed,
}

class FoodCatalogUpdater extends ChangeNotifier {
  static const repository = 'daoshi818-crypto/chiyoushu-food-data';
  static const manifestUrl =
      'https://daoshi818-crypto.github.io/chiyoushu-food-data/manifest.json';
  static const maxCatalogBytes = 15 * 1024 * 1024;
  final http.Client client;
  final Future<Directory> Function() directory;
  final Future<void> Function(String) activate;
  final DateTime Function() clock;
  Future<String?>? _installed;
  Future<void>? _running;
  DateTime? _lastAttempt;
  DateTime? lastCheck;
  DateTime? lastInstall;
  FoodCatalogManifest? current;
  FoodCatalogUpdatePhase phase = FoodCatalogUpdatePhase.idle;
  String? error;
  Duration _interval = const Duration(hours: 1);

  FoodCatalogUpdater({
    required this.client,
    required this.activate,
    Future<Directory> Function()? directory,
    DateTime Function()? clock,
  }) : directory = directory ?? _defaultDirectory,
       clock = clock ?? DateTime.now;

  static Future<Directory> _defaultDirectory() async => Directory(
    '${(await getApplicationSupportDirectory()).path}/food-catalog',
  );

  Future<String?> readInstalledCatalog() =>
      _installed ??= _readInstalled().catchError((Object _) => null);

  Future<String?> _readInstalled() async {
    final root = await directory();
    try {
      final saved =
          jsonDecode(await File('${root.path}/state.json').readAsString())
              as Map;
      lastCheck = DateTime.tryParse(saved['last_check'] as String? ?? '');
      lastInstall = DateTime.tryParse(saved['last_install'] as String? ?? '');
    } catch (_) {}
    for (final pointer in ['current.json', 'previous.json']) {
      try {
        final m = FoodCatalogManifest.parse(
          await File('${root.path}/$pointer').readAsString(),
        );
        final data = await File(
          '${root.path}/versions/${m.sequence}/catalog.json',
        ).readAsBytes();
        final text = await _verify(data, m);
        current = m;
        return text;
      } catch (_) {}
    }
    return null;
  }

  Future<void> check({bool manual = false}) {
    if (_running != null) return _running!;
    final work = _check(manual);
    _running = work;
    return work.whenComplete(() => _running = null);
  }

  Future<void> _check(bool manual) async {
    try {
      await readInstalledCatalog();
      final now = clock();
      if (_lastAttempt != null &&
          now.difference(_lastAttempt!) < const Duration(seconds: 10)) {
        return;
      }
      if (!manual) {
        if (_lastAttempt != null &&
            now.difference(_lastAttempt!) < const Duration(minutes: 5)) {
          return;
        }
        if (lastCheck != null && now.difference(lastCheck!) < _interval) return;
      }
      _lastAttempt = now;
      phase = FoodCatalogUpdatePhase.checking;
      error = null;
      notifyListeners();
      final notification = await _download(
        Uri.parse(manifestUrl),
        64 * 1024,
        const Duration(seconds: 15),
      );
      final next = FoodCatalogManifest.parse(utf8.decode(notification));
      if (current != null && next.sequence < current!.sequence) {
        throw const FormatException('Older release');
      }
      if (current != null && next.sequence == current!.sequence) {
        if (!next.sameContent(current!)) {
          throw const FormatException('Conflicting release');
        }
        phase = FoodCatalogUpdatePhase.current;
      } else {
        phase = FoodCatalogUpdatePhase.downloading;
        notifyListeners();
        String? text;
        final urls = [
          'https://cdn.jsdelivr.net/gh/$repository@${next.commit}/dist/catalog.json',
          'https://raw.githubusercontent.com/$repository/${next.commit}/dist/catalog.json',
        ];
        for (final url in urls) {
          try {
            final data = await _download(
              Uri.parse(url),
              next.bytes,
              const Duration(seconds: 60),
            );
            text = await _verify(data, next);
            break;
          } catch (_) {}
        }
        if (text == null) {
          throw const FormatException(
            'Catalogue download or validation failed',
          );
        }
        final root = await directory();
        final version = Directory('${root.path}/versions/${next.sequence}');
        await version.create(recursive: true);
        final candidate = File('${version.path}/catalog.json.part');
        await candidate.writeAsString(text, flush: true);
        await candidate.rename('${version.path}/catalog.json');
        if (current != null) {
          await _writeAtomic(root, 'previous.json', jsonEncode(current!.json));
        }
        await _writeAtomic(root, 'current.json', jsonEncode(next.json));
        try {
          await activate(text);
        } catch (_) {
          if (current != null) {
            await _writeAtomic(root, 'current.json', jsonEncode(current!.json));
          } else {
            await File('${root.path}/current.json').delete();
          }
          rethrow;
        }
        current = next;
        _installed = Future.value(text);
        lastInstall = clock();
        phase = FoodCatalogUpdatePhase.updated;
        final versions = Directory('${root.path}/versions');
        int? previous;
        try {
          previous = FoodCatalogManifest.parse(
            await File('${root.path}/previous.json').readAsString(),
          ).sequence;
        } catch (_) {}
        try {
          await for (final entry in versions.list()) {
            final name = entry.uri.pathSegments.where((p) => p.isNotEmpty).last;
            final seq = int.tryParse(name);
            if (entry is Directory &&
                seq != null &&
                seq != next.sequence &&
                seq != previous) {
              await entry.delete(recursive: true);
            }
          }
        } catch (_) {}
      }
      lastCheck = clock();
      _interval = Duration(minutes: 60 + Random().nextInt(6));
      try {
        await _writeAtomic(
          await directory(),
          'state.json',
          jsonEncode({
            'last_check': lastCheck!.toUtc().toIso8601String(),
            'last_install': lastInstall?.toUtc().toIso8601String(),
          }),
        );
      } catch (_) {}
    } catch (_) {
      phase = FoodCatalogUpdatePhase.failed;
      error = '食物库更新失败，继续使用当前离线数据';
    }
    notifyListeners();
  }

  Future<void> _writeAtomic(Directory root, String name, String text) async {
    await root.create(recursive: true);
    final pending = File('${root.path}/$name.part');
    await pending.writeAsString(text, flush: true);
    await pending.rename('${root.path}/$name');
  }

  Future<String> _verify(List<int> data, FoodCatalogManifest manifest) async {
    if (data.length != manifest.bytes ||
        sha256.convert(data).toString() != manifest.hash) {
      throw const FormatException('Catalogue integrity check failed');
    }
    final text = utf8.decode(data);
    if (await ChineseFoodDataSource.validateCatalog(text) != manifest.count) {
      throw const FormatException('Catalogue count mismatch');
    }
    return text;
  }

  Future<Uint8List> _download(Uri url, int limit, Duration budget) async {
    final started = Stopwatch()..start();
    final response = await client
        .send(http.Request('GET', url)..headers['Cache-Control'] = 'no-cache')
        .timeout(const Duration(seconds: 5));
    final iterator = StreamIterator(response.stream);
    try {
      if (response.statusCode != 200 || (response.contentLength ?? 0) > limit) {
        throw const FormatException('Invalid catalogue response');
      }
      final out = BytesBuilder(copy: false);
      while (true) {
        final remaining = budget - started.elapsed;
        if (remaining <= Duration.zero) {
          throw TimeoutException('Catalogue request timed out');
        }
        if (!await iterator.moveNext().timeout(remaining)) break;
        out.add(iterator.current);
        if (out.length > limit) {
          throw const FormatException('Catalogue response too large');
        }
      }
      return out.takeBytes();
    } finally {
      await iterator.cancel();
    }
  }
}
