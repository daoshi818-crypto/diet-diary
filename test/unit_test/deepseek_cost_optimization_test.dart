import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/ai_request_cache.dart';
import 'package:opennutritracker/core/utils/deepseek_endpoint.dart';
import 'package:opennutritracker/features/add_meal/data/ai_food_analysis_api.dart';
import 'package:opennutritracker/features/add_meal/data/nutrition_label_api.dart';
import 'package:opennutritracker/features/add_meal/data/openai_compatible_meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/nutrition_label_draft.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';

const selection = AiSelection(
  provider: AiProvider.ownServer,
  endpoint: 'https://api.deepseek.com',
  modelId: 'deepseek-flash',
  apiKey: 'unit-test-key',
);
const label = <String, Object?>{
  'name': '燕麦片',
  'basisText': '每100克',
  'basisQuantity': 100,
  'basisUnit': 'g',
  'energy': 1520,
  'energyUnit': 'kJ',
  'protein': 12.5,
  'fat': 8,
  'carbs': 62,
  'fiber': null,
  'sodiumMg': 40,
};
http.Response reply(Map<String, Object?> data, {String reason = 'stop'}) =>
    http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'choices': [
            {
              'finish_reason': reason,
              'message': {'content': jsonEncode(data)},
            },
          ],
        }),
      ),
      200,
    );

void main() {
  test(
    'printed basis evidence rejects count, net weight and mixed columns',
    () {
      for (final basis in [
        {'basisText': '每份(2片)', 'basisQuantity': 2},
        {'basisText': '净含量450克', 'basisQuantity': 450},
        {'basisText': '每份2片 净含量200g', 'basisQuantity': 200},
        {'basisText': '每100g / 每30g', 'basisQuantity': 100},
        {'basisText': '每30克', 'basisQuantity': 100},
        {'basisText': '每100毫升', 'basisQuantity': 100},
      ]) {
        final draft = NutritionLabelDraft.fromJson({...label, ...basis});
        expect(draft.basisQuantity, isNull);
        expect(draft.canSave, isFalse);
      }
      final valid = NutritionLabelDraft.fromJson({
        ...label,
        'basisText': '每份(2片，30g)',
        'basisQuantity': 30,
      });
      expect(valid.basisQuantity, 30);
    },
  );
  final photo = MealPhoto(
    bytes: Uint8List.fromList([1, 2, 3]),
    mediaType: 'image/png',
  );
  test(
    'official endpoint match does not include relays or lookalike hosts',
    () {
      for (final url in [
        'https://api.deepseek.com/chat/completions',
        'https://api.deepseek.com/v1/chat/completions',
        'https://api.deepseek.com/beta/chat/completions',
      ]) {
        expect(isDeepSeekEndpoint(Uri.parse(url)), isTrue);
      }
      for (final url in [
        'http://api.deepseek.com/chat/completions',
        'https://api.deepseek.com.evil.test/chat/completions',
        'https://api.deepseek.com:8443/chat/completions',
        'https://relay.example/v1/chat/completions',
        'https://api.deepseek.com/some-other-api',
      ]) {
        expect(isDeepSeekEndpoint(Uri.parse(url)), isFalse);
      }
    },
  );
  test(
    'label uses one JSON call, no thinking, stable prefix and nulls',
    () async {
      var calls = 0;
      String? prefix;
      final client = MockClient((request) async {
        calls++;
        expect(
          request.url.toString(),
          'https://api.deepseek.com/v1/chat/completions',
        );
        final body = jsonDecode(request.body) as Map;
        expect(body['model'], 'deepseek-flash');
        expect(body['thinking'], {'type': 'disabled'});
        expect(body['response_format'], {'type': 'json_object'});
        expect(body.containsKey('tools'), isFalse);
        expect(body.containsKey('tool_choice'), isFalse);
        expect(body['messages'], hasLength(2));
        final next = body['messages'][0]['content'] as String;
        expect(next, contains('never estimate'));
        if (prefix != null) expect(next, prefix);
        prefix = next;
        return reply(label);
      });
      final api = NutritionLabelApi(client);
      final first = await api.read(photo, selection);
      final again = await NutritionLabelApi(client).read(photo, selection);
      expect(identical(first, again), isTrue);
      expect(calls, 1);
      expect(again.fiber, isNull);
      expect(
        again.toMeal().nutriments.energyKcal100,
        closeTo(1520 / 4.184, .001),
      );
      await api.read(photo, selection, forceRefresh: true);
      expect(calls, 2);
      await api.read(
        MealPhoto(bytes: Uint8List.fromList([4]), mediaType: 'image/png'),
        selection,
      );
      expect(calls, 3);
    },
  );
  test('incomplete output is rejected once, never retried or cached', () async {
    var calls = 0;
    final api = NutritionLabelApi(
      MockClient((_) async {
        calls++;
        return reply(label, reason: calls == 1 ? 'length' : 'stop');
      }),
    );
    await expectLater(
      api.read(photo, selection),
      throwsA(isA<MealInterpreterException>()),
    );
    expect(calls, 1);
    await api.read(photo, selection);
    expect(calls, 2);
  });
  test(
    'nutrition estimates retain model thinking and use JSON without tool retry',
    () async {
      var calls = 0;
      final api = AiFoodAnalysisApi(
        MockClient((request) async {
          calls++;
          final body = jsonDecode(request.body) as Map;
          expect(body.containsKey('thinking'), isFalse);
          expect(body.containsKey('tools'), isFalse);
          return reply({'items': <Object>[]});
        }),
      );
      expect(await api.analyze(selection: selection, text: '一盘炒饭'), isEmpty);
      expect(calls, 1);
    },
  );
  test('text extraction tool disables incompatible default thinking', () async {
    final api = OpenAiCompatibleMealItemsApi(
      MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        expect(body['thinking'], {'type': 'disabled'});
        expect(body['tools'], isNotEmpty);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'tool_calls': [
                    {
                      'function': {
                        'name': 'log_meal_items',
                        'arguments': jsonEncode({
                          'items': [
                            {'query': 'corn', 'quantity': 50, 'unit': 'g'},
                          ],
                        }),
                      },
                    },
                  ],
                },
              },
            ],
          }),
          200,
        );
      }),
      () => 'unit-test-key',
      model: 'deepseek-flash',
      endpoint: Uri.parse('https://api.deepseek.com/v1/chat/completions'),
      toolChoice: ToolChoiceMode.anyTool,
    );
    final result = await api.requestItems(
      content: const MealTextContent('corn 50g'),
      system: 'Extract foods.',
    );
    expect(result.items.single.query, 'corn');
  });
  test(
    'fingerprint changes for account, model, endpoint, image and prompt',
    () {
      String key(AiSelection s, {String prompt = 'read', MealPhoto? image}) =>
          aiRequestFingerprint(
            selection: s,
            system: prompt,
            schema: const {},
            photo: image ?? photo,
          );
      final keys = {
        key(selection),
        key(
          const AiSelection(
            provider: AiProvider.ownServer,
            endpoint: 'https://api.deepseek.com',
            modelId: 'deepseek-flash',
            apiKey: 'other-key',
          ),
        ),
        key(
          const AiSelection(
            provider: AiProvider.ownServer,
            endpoint: 'https://api.deepseek.com',
            modelId: 'deepseek-v4-pro',
            apiKey: 'unit-test-key',
          ),
        ),
        key(
          const AiSelection(
            provider: AiProvider.ownServer,
            endpoint: 'https://relay.example',
            modelId: 'deepseek-flash',
            apiKey: 'unit-test-key',
          ),
        ),
        key(selection, prompt: 'different'),
        key(
          selection,
          image: MealPhoto(
            bytes: Uint8List.fromList([9]),
            mediaType: 'image/png',
          ),
        ),
      };
      expect(keys, hasLength(6));
      expect(keys.every((k) => RegExp(r'^[a-f0-9]{64}$').hasMatch(k)), isTrue);
    },
  );
  test(
    'cache merges pending requests and evicts expired, failed and old entries',
    () async {
      var now = DateTime(2026, 11, 22);
      final cache = AiRequestCache<int>(
        capacity: 2,
        lifetime: const Duration(minutes: 1),
        clock: () => now,
      );
      final gate = Completer<int>();
      var calls = 0;
      Future<int> load() {
        calls++;
        return gate.future;
      }

      final a = cache.getOrLoad('a', load);
      final duplicate = cache.getOrLoad('a', load);
      gate.complete(1);
      expect(await a, 1);
      expect(await duplicate, 1);
      expect(calls, 1);
      await cache.getOrLoad('b', () async => 2);
      await cache.getOrLoad('c', () async => 3);
      expect(await cache.getOrLoad('a', () async => 4), 4);
      now = now.add(const Duration(minutes: 1));
      expect(await cache.getOrLoad('a', () async => 5), 5);
      await expectLater(
        cache.getOrLoad('failed', () async => throw const FormatException()),
        throwsFormatException,
      );
      expect(await cache.getOrLoad('failed', () async => 6), 6);
    },
  );
}
