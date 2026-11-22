import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/ai_model_catalogue.dart';
import 'package:opennutritracker/features/add_meal/data/ai_food_analysis_api.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/ai_food_draft.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';

const _food = <String, Object?>{
  'name': '熟米饭',
  'brand': '',
  'amount': 220,
  'basisUnit': 'g',
  'amountEstimated': false,
  'energy': 116,
  'protein': 2.6,
  'fat': .3,
  'carbs': 25.9,
  'notes': '熟重',
};
http.Response _response(Object value) => http.Response.bytes(
  utf8.encode(jsonEncode(value)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  final photo = MealPhoto(
    bytes: Uint8List.fromList([1, 2, 3]),
    mediaType: 'image/jpeg',
  );
  for (final provider in AiProvider.values) {
    final modelId =
        AiModelCatalogue.defaultFor(provider)?.id ?? 'user-selected-model';
    for (final hasPhoto in [false, true]) {
      test(
        'saved model and nutrition for ${provider.name}, photo=$hasPhoto',
        () async {
          final api = AiFoodAnalysisApi(
            MockClient((request) async {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              expect(body['model'], modelId);
              expect(request.body, contains('220g'));
              expect(request.body, contains('PER 100 g/ml'));
              expect(request.body, contains('dry rice/grains and cooked rice'));
              expect(request.body, contains('Do not double count'));
              expect(
                request.body.contains('data:image/jpeg;base64,'),
                hasPhoto && provider != AiProvider.anthropic,
              );
              final result = {
                'items': [_food],
              };
              if (provider == AiProvider.anthropic) {
                expect(request.headers['x-api-key'], 'saved-key');
                final content = body['messages'][0]['content'] as List;
                expect(
                  content.where((v) => v['type'] == 'image').isNotEmpty,
                  hasPhoto,
                );
                return _response({
                  'content': [
                    {
                      'type': 'tool_use',
                      'name': AiFoodAnalysisApi.toolName,
                      'input': result,
                    },
                  ],
                });
              }
              expect(request.headers['authorization'], 'Bearer saved-key');
              if (provider == AiProvider.openai) {
                expect(body['store'], false);
                return _response({
                  'output': [
                    {
                      'type': 'function_call',
                      'name': AiFoodAnalysisApi.toolName,
                      'arguments': jsonEncode(result),
                    },
                  ],
                });
              }
              if (provider == AiProvider.ownServer) {
                expect(
                  request.url.toString(),
                  'https://relay.example/api/v1/chat/completions',
                );
              }
              return _response({
                'choices': [
                  {
                    'message': {
                      'tool_calls': [
                        {
                          'function': {
                            'name': AiFoodAnalysisApi.toolName,
                            'arguments': jsonEncode(result),
                          },
                        },
                      ],
                    },
                  },
                ],
              });
            }),
          );
          final items = await api.analyze(
            selection: AiSelection(
              provider: provider,
              apiKey: 'saved-key',
              modelId: modelId,
              endpoint: 'https://relay.example/api/v1',
            ),
            text: '熟米饭220g',
            photo: hasPhoto ? photo : null,
          );
          expect(items.single.amount, 220);
          expect(items.single.amountEstimated, false);
          expect(items.single.meal.name, '熟米饭');
          expect(items.single.meal.nutriments.energyKcal100, 116);
          expect(
            items.single.meal.nutriments.energyPerUnit! * items.single.amount,
            closeTo(255.2, .001),
          );
        },
      );
    }
  }
  test(
    'compatible endpoint accepts JSON content and empty recognition',
    () async {
      for (final items in [
        <Object>[],
        <Object>[_food],
      ]) {
        final api = AiFoodAnalysisApi(
          MockClient(
            (_) async => _response({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({'items': items}),
                  },
                },
              ],
            }),
          ),
        );
        final result = await api.analyze(
          selection: const AiSelection(
            provider: AiProvider.ownServer,
            modelId: 'selected',
            endpoint: 'https://relay.example/v1',
          ),
          text: '米饭220g',
        );
        expect(result, hasLength(items.length));
      }
    },
  );
  for (final overrides in [
    {'amount': 0},
    {'amount': -1},
    {'amount': double.infinity},
    {'energy': null},
    {'protein': 101},
    {'basisUnit': 'serving'},
    {'name': ''},
    {'protein': 80, 'fat': 80},
  ]) {
    test('rejects invalid AI nutrition ${overrides.keys.join()}', () {
      expect(
        () => AiFoodDraft.fromJson({..._food, ...overrides}),
        throwsFormatException,
      );
    });
  }
  test('ml remains ml and missing amount is rejected', () {
    final food = AiFoodDraft.fromJson({
      ..._food,
      'name': '牛奶',
      'basisUnit': 'ml',
      'amount': 250,
    });
    expect(food.meal.isLiquid, true);
    expect(food.amount, 250);
    expect(
      () => AiFoodDraft.fromJson({..._food, 'amount': null}),
      throwsFormatException,
    );
  });
  for (final status in [401, 402, 415, 429]) {
    test('HTTP $status is classified without credential leakage', () async {
      final api = AiFoodAnalysisApi(
        MockClient(
          (_) async =>
              http.Response('private server payload saved-key', status),
        ),
      );
      final expected = switch (status) {
        401 => MealInterpreterFailure.auth,
        402 => MealInterpreterFailure.billing,
        415 => MealInterpreterFailure.unsupported,
        _ => MealInterpreterFailure.transient,
      };
      await expectLater(
        api.analyze(
          selection: const AiSelection(
            provider: AiProvider.ownServer,
            modelId: 'selected',
            apiKey: 'saved-key',
            endpoint: 'https://relay.example/v1',
          ),
          text: '米饭220g',
        ),
        throwsA(
          isA<MealInterpreterException>()
              .having((e) => e.failure, 'failure', expected)
              .having(
                (e) => e.toString(),
                'public error',
                isNot(contains('saved-key')),
              ),
        ),
      );
    });
  }
  test('no model is invented when none was selected', () async {
    var requests = 0;
    final api = AiFoodAnalysisApi(
      MockClient((_) async {
        requests++;
        return _response({});
      }),
    );
    await expectLater(
      api.analyze(
        selection: const AiSelection(
          provider: AiProvider.ownServer,
          endpoint: 'https://relay.example/v1',
        ),
        text: '米饭220g',
      ),
      throwsA(isA<MealInterpreterException>()),
    );
    expect(requests, 0);
  });
}
