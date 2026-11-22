import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/ai_model_catalogue.dart';
import 'package:opennutritracker/features/add_meal/data/nutrition_label_api.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/nutrition_label_draft.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';

const _label = {
  'name': '燕麦片',
  'brand': '测试品牌',
  'basisText': '每份30克',
  'basisQuantity': 30,
  'basisUnit': 'g',
  'energy': 450,
  'energyUnit': 'kJ',
  'protein': 3,
  'fat': 2,
  'carbs': 20,
  'fiber': null,
  'sodiumMg': 15,
};

String _json(Object? value) => jsonEncode(value).replaceAllMapped(
  RegExp(r'[^\x00-\x7F]'),
  (m) => '\\u${m[0]!.codeUnitAt(0).toRadixString(16).padLeft(4, '0')}',
);

void main() {
  test('normalizes a printed 30 g column, kJ and sodium mg exactly once', () {
    final draft = NutritionLabelDraft.fromJson(_label);
    expect(draft.canSave, isTrue);
    final meal = draft.toMeal();
    expect(meal.nutriments.energyKcal100, closeTo(1500 / 4.184, .001));
    expect(meal.nutriments.proteins100, 10);
    expect(meal.nutriments.carbohydrates100, closeTo(200 / 3, .001));
    expect(meal.nutriments.sodium100, 50);
    expect(meal.nutriments.fiber100, isNull);
    expect(meal.source, MealSourceEntity.custom);
    expect(meal.servingQuantity, isNull);
    expect(meal.mealQuantity, isNull);
  });

  test('liquid column remains ml and unknown nutrients stay unknown', () {
    final meal = NutritionLabelDraft.fromJson({
      ..._label,
      'basisUnit': 'ml',
      'basisText': '每100毫升',
      'basisQuantity': 100,
      'sodiumMg': null,
      'energyUnit': 'kcal',
      'energy': 120,
    }).toMeal();
    expect(meal.mealUnit, 'ml');
    expect(meal.isLiquid, isTrue);
    expect(meal.nutriments.energyKcal100, 120);
    expect(meal.nutriments.sodium100, isNull);
  });

  for (final field in ['basisQuantity', 'energy', 'protein', 'fat', 'carbs']) {
    test('missing $field requires review rather than becoming zero', () {
      final draft = NutritionLabelDraft.fromJson({..._label, field: null});
      expect(draft.canSave, isFalse);
      expect(draft.toMeal, throwsFormatException);
    });
  }
  for (final value in [-1, double.nan, double.infinity, 'NRV 25%']) {
    test('invalid label value $value is rejected', () {
      expect(
        () => NutritionLabelDraft.fromJson({..._label, 'fat': value}),
        throwsFormatException,
      );
    });
  }
  test('impossible normalized values and zero basis cannot be saved', () {
    for (final overrides in [
      {'basisQuantity': 0},
      {'basisQuantity': 1},
      {'name': ''},
      {'energy': 999999},
      {'fat': 40},
    ]) {
      expect(
        NutritionLabelDraft.fromJson({..._label, ...overrides}).canSave,
        isFalse,
      );
    }
  });

  final photo = MealPhoto(
    bytes: Uint8List.fromList([1, 2, 3]),
    mediaType: 'image/jpeg',
  );
  for (final provider in AiProvider.values) {
    test('nutrition label request and response for ${provider.name}', () async {
      final id = AiModelCatalogue.defaultFor(provider)?.id ?? 'vision-test';
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['model'], id);
        expect(body.toString(), contains('never estimate'));
        switch (provider) {
          case AiProvider.anthropic:
            expect(request.headers['x-api-key'], 'test-key');
            expect(body['thinking'], {'type': 'disabled'});
            return http.Response(
              _json({
                'content': [
                  {
                    'type': 'tool_use',
                    'name': NutritionLabelApi.toolName,
                    'input': _label,
                  },
                ],
              }),
              200,
            );
          case AiProvider.openai:
            expect(body['store'], isFalse);
            expect(body['tools'][0]['strict'], isFalse);
            return http.Response(
              _json({
                'output': [
                  {
                    'type': 'function_call',
                    'name': NutritionLabelApi.toolName,
                    'arguments': _json(_label),
                  },
                ],
              }),
              200,
            );
          case AiProvider.openrouter:
          case AiProvider.ownServer:
            if (provider == AiProvider.openrouter) {
              expect(body['provider']['data_collection'], 'deny');
              expect(body['provider']['only'], ['anthropic']);
              expect(body.containsKey('tool_choice'), isFalse);
            }
            if (provider == AiProvider.ownServer) {
              expect(
                request.url.toString(),
                'https://vision.example/v1/chat/completions',
              );
              expect(body['tool_choice'], 'required');
              expect(body.containsKey('provider'), isFalse);
            }
            expect(request.headers['authorization'], 'Bearer test-key');
            return http.Response(
              _json({
                'choices': [
                  {
                    'message': {
                      'tool_calls': [
                        {
                          'function': {
                            'name': NutritionLabelApi.toolName,
                            'arguments': _json(_label),
                          },
                        },
                      ],
                    },
                  },
                ],
              }),
              200,
            );
        }
      });
      final draft = await NutritionLabelApi(client).read(
        photo,
        AiSelection(
          provider: provider,
          apiKey: 'test-key',
          modelId: id,
          endpoint: provider == AiProvider.ownServer
              ? 'https://vision.example/v1'
              : null,
        ),
      );
      expect(draft.toMeal().name, '燕麦片');
    });
  }

  test('compatible endpoint accepts fenced JSON without a tool call', () async {
    final api = NutritionLabelApi(
      MockClient(
        (_) async => http.Response(
          _json({
            'choices': [
              {
                'message': {'content': '```json\n${_json(_label)}\n```'},
              },
            ],
          }),
          200,
        ),
      ),
    );
    final result = await api.read(
      photo,
      const AiSelection(
        provider: AiProvider.ownServer,
        endpoint: 'https://vision.example/v1',
        modelId: 'vision-test',
      ),
    );
    expect(result.basisQuantity, 30);
  });

  for (final scenario in [
    (401, '{}', MealInterpreterFailure.auth),
    (402, '{}', MealInterpreterFailure.billing),
    (
      429,
      '{"error":{"code":"insufficient_quota"}}',
      MealInterpreterFailure.billing,
    ),
    (429, '{}', MealInterpreterFailure.transient),
    (415, '{}', MealInterpreterFailure.unsupported),
    (200, '{"choices":[]}', MealInterpreterFailure.transient),
  ]) {
    test(
      'label failure ${scenario.$1} classified without leaking payload',
      () async {
        final api = NutritionLabelApi(
          MockClient((_) async => http.Response(scenario.$2, scenario.$1)),
        );
        await expectLater(
          api.read(
            photo,
            const AiSelection(
              provider: AiProvider.ownServer,
              endpoint: 'https://vision.example/v1',
              modelId: 'vision-test',
            ),
          ),
          throwsA(
            isA<MealInterpreterException>().having(
              (e) => e.failure,
              'failure',
              scenario.$3,
            ),
          ),
        );
      },
    );
  }
}
