import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';

String aiRequestFingerprint({
  required AiSelection selection,
  required String system,
  required Map<String, Object?> schema,
  required MealPhoto photo,
}) => sha256
    .convert(
      utf8.encode(
        jsonEncode({
          'provider': selection.provider.name,
          'endpoint': selection.endpoint,
          'model': selection.modelId,
          'credential': selection.apiKey,
          'system': system,
          'schema': schema,
          'mediaType': photo.mediaType,
          'image': sha256.convert(photo.bytes).toString(),
        }),
      ),
    )
    .toString();

class AiRequestCache<T> {
  final Duration lifetime;
  final int capacity;
  final DateTime Function() clock;
  final _entries = <String, (DateTime, T)>{};
  final _pending = <String, Future<T>>{};

  AiRequestCache({
    this.lifetime = const Duration(minutes: 15),
    this.capacity = 8,
    DateTime Function()? clock,
  }) : assert(capacity > 0),
       clock = clock ?? DateTime.now;

  Future<T> getOrLoad(
    String key,
    Future<T> Function() load, {
    bool refresh = false,
  }) async {
    final now = clock();
    _entries.removeWhere((_, entry) => !now.isBefore(entry.$1));
    if (refresh) _entries.remove(key);
    final cached = _entries[key];
    if (cached != null) return cached.$2;
    final pending = _pending[key];
    if (pending != null) return pending;
    final request = Future<T>.sync(load);
    _pending[key] = request;
    try {
      final value = await request;
      while (_entries.length >= capacity) {
        _entries.remove(_entries.keys.first);
      }
      _entries[key] = (clock().add(lifetime), value);
      return value;
    } finally {
      _pending.remove(key);
    }
  }
}
