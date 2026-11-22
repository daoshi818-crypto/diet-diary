import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/ai_model_catalogue.dart';
import 'package:opennutritracker/core/utils/gemini_endpoint.dart';
import 'package:opennutritracker/core/utils/plaintext_destination_guard.dart';
import 'package:opennutritracker/features/add_meal/data/meal_items_api_factory.dart';
import 'package:opennutritracker/features/add_meal/data/openai_compatible_meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';

class AiStructuredApi {
  final http.Client client;
  const AiStructuredApi(this.client);

  Future<Map<String, dynamic>> request({
    required AiSelection selection,
    required String system,
    required String input,
    required String toolName,
    required Map<String, Object?> schema,
    MealPhoto? photo,
  }) async {
    final curated = AiModelCatalogue.resolve(
      selection.provider,
      selection.modelId,
    );
    final model = curated?.id ?? selection.modelId;
    if (model == null || model.isEmpty) {
      throw const MealInterpreterException(
        'No model',
        failure: MealInterpreterFailure.unsupported,
      );
    }
    final data = photo == null ? null : base64Encode(photo.bytes);
    final imageUrl = photo == null
        ? null
        : 'data:${photo.mediaType};base64,$data';
    final headers = <String, String>{'content-type': 'application/json'};
    final key = selection.apiKey;
    late Uri endpoint;
    late Map<String, Object?> body;
    switch (selection.provider) {
      case AiProvider.anthropic:
        endpoint = Uri.parse('https://api.anthropic.com/v1/messages');
        headers.addAll({
          'x-api-key': key ?? '',
          'anthropic-version': '2023-06-01',
        });
        body = {
          'model': model,
          'max_tokens': curated?.toolCall == AiToolCall.auto ? 9000 : 6000,
          'system': system,
          'messages': [
            {
              'role': 'user',
              'content': [
                if (photo != null)
                  {
                    'type': 'image',
                    'source': {
                      'type': 'base64',
                      'media_type': photo.mediaType,
                      'data': data,
                    },
                  },
                {'type': 'text', 'text': input},
              ],
            },
          ],
          'tools': [
            {
              'name': toolName,
              'description': 'Return structured food analysis',
              'input_schema': schema,
            },
          ],
          ...switch (curated?.toolCall ?? AiToolCall.forced) {
            AiToolCall.forced => {
              'tool_choice': {'type': 'tool', 'name': toolName},
            },
            AiToolCall.forcedThinkingOff => {
              'tool_choice': {'type': 'tool', 'name': toolName},
              'thinking': {'type': 'disabled'},
            },
            AiToolCall.auto => {
              'tool_choice': {'type': 'auto'},
              'thinking': {'type': 'between_tools'},
            },
          },
        };
      case AiProvider.openai:
        endpoint = Uri.parse('https://api.openai.com/v1/responses');
        headers['authorization'] = 'Bearer ${key ?? ''}';
        body = {
          'model': model,
          'store': false,
          'instructions': system,
          'max_output_tokens': 6000,
          'input': [
            {
              'role': 'user',
              'content': [
                if (photo != null)
                  {'type': 'input_image', 'image_url': imageUrl},
                {'type': 'input_text', 'text': input},
              ],
            },
          ],
          'tools': [
            {
              'type': 'function',
              'name': toolName,
              'description': 'Return structured food analysis',
              'parameters': schema,
              'strict': false,
            },
          ],
          'tool_choice': {'type': 'function', 'name': toolName},
        };
      case AiProvider.openrouter:
      case AiProvider.ownServer:
        final router = selection.provider == AiProvider.openrouter;
        endpoint = router
            ? Uri.parse('https://openrouter.ai/api/v1/chat/completions')
            : AiCredentialStorage.resolveEndpoint(selection.endpoint ?? '') ??
                  (throw const MealInterpreterException('Invalid endpoint'));
        if (key != null && key.isNotEmpty) {
          headers['authorization'] = 'Bearer $key';
        }
        if (router) headers['x-openrouter-metadata'] = 'enabled';
        body = {
          'model': model,
          'max_tokens': curated?.toolCall == AiToolCall.auto ? 9000 : 6000,
          if (curated?.toolCall == AiToolCall.forcedThinkingOff)
            'reasoning': {'enabled': false},
          'messages': [
            {'role': 'system', 'content': system},
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': input},
                if (photo != null)
                  {
                    'type': 'image_url',
                    'image_url': {'url': imageUrl},
                  },
              ],
            },
          ],
          'tools': [
            {
              'type': 'function',
              'function': {
                'name': toolName,
                'description': 'Return structured food analysis',
                'parameters': schema,
              },
            },
          ],
          if (!router &&
              ownServerToolChoice(endpoint) == ToolChoiceMode.anyTool)
            'tool_choice': 'required'
          else if (curated?.toolCall != AiToolCall.auto)
            'tool_choice': {
              'type': 'function',
              'function': {'name': toolName},
            },
          if (router)
            'provider': {
              'data_collection': 'deny',
              if (curated?.toolCall != AiToolCall.forcedThinkingOff)
                'require_parameters': true,
              if (curated?.providers case final providers?
                  when providers.isNotEmpty) ...{
                'only': providers,
                'allow_fallbacks': false,
              },
            },
        };
    }
    final http.Response response;
    try {
      final guarded = GuardedPlaintextClient(client);
      response = await guarded
          .post(endpoint, headers: headers, body: jsonEncode(body))
          .timeout(
            Duration(
              seconds: selection.provider == AiProvider.ownServer ? 120 : 45,
            ),
          );
    } on InsecureDestinationException {
      throw const MealInterpreterException(
        'Use HTTPS',
        failure: MealInterpreterFailure.insecureDestination,
      );
    } on TimeoutException {
      throw MealInterpreterException(
        'Structured AI request timed out',
        failure: selection.provider == AiProvider.ownServer
            ? MealInterpreterFailure.timeout
            : MealInterpreterFailure.transient,
      );
    } catch (_) {
      throw const MealInterpreterException('Structured AI request failed');
    }
    if (response.statusCode != 200) {
      throw MealInterpreterException(
        'Structured AI HTTP error',
        failure: _failureFor(
          response.statusCode,
          response.body,
          endpoint,
          selection.provider,
        ),
        statusCode: response.statusCode,
      );
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException();
      if (decoded['error'] != null) {
        throw MealInterpreterException(
          'Structured AI provider error',
          failure: _failureFor(
            400,
            response.body,
            endpoint,
            selection.provider,
          ),
        );
      }
      Object? result;
      if (selection.provider == AiProvider.anthropic) {
        for (final entry in decoded['content'] as List) {
          if (entry is Map &&
              entry['type'] == 'tool_use' &&
              entry['name'] == toolName) {
            result = entry['input'];
            break;
          }
        }
      } else if (selection.provider == AiProvider.openai) {
        for (final entry in decoded['output'] as List) {
          if (entry is Map &&
              entry['type'] == 'function_call' &&
              entry['name'] == toolName) {
            result = jsonDecode(entry['arguments'] as String);
            break;
          }
        }
      } else {
        final choice = decoded['choices'][0];
        if (choice['finish_reason'] == 'error') {
          final code = choice['error']?['code'];
          throw MealInterpreterException(
            'Structured AI generation failed',
            failure: _failureFor(
              code is int ? code : 500,
              response.body,
              endpoint,
              selection.provider,
            ),
          );
        }
        final message = choice['message'];
        for (final entry in message['tool_calls'] as List? ?? []) {
          if (entry is Map && entry['function']?['name'] == toolName) {
            final arguments = entry['function']['arguments'];
            result = arguments is String ? jsonDecode(arguments) : arguments;
            break;
          }
        }
        // Some compatible vision models return JSON content instead of a tool call.
        if (result == null && message['content'] is String) {
          var content = (message['content'] as String).trim();
          if (content.startsWith('```')) {
            content = content
                .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
                .replaceFirst(RegExp(r'\s*```$'), '');
          }
          result = jsonDecode(content);
        }
      }
      return Map<String, dynamic>.from(result as Map);
    } on MealInterpreterException {
      rethrow;
    } catch (_) {
      throw const MealInterpreterException('Unreadable structured AI response');
    }
  }

  MealInterpreterFailure _failureFor(
    int code,
    String body,
    Uri endpoint,
    AiProvider provider,
  ) {
    if (isGeminiEndpoint(endpoint)) {
      if (geminiFailureFromBody(body) case final failure?) return failure;
    }
    if (body.contains('insufficient_quota') ||
        body.contains('insufficient_balance')) {
      return MealInterpreterFailure.billing;
    }
    if (provider == AiProvider.openrouter) {
      return OpenAiCompatibleMealItemsApi.openRouterFailureFor(code);
    }
    return switch (code) {
      401 || 403 => MealInterpreterFailure.auth,
      402 => MealInterpreterFailure.billing,
      400 || 404 || 415 || 422 => MealInterpreterFailure.unsupported,
      _ => MealInterpreterFailure.transient,
    };
  }
}
