import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/learning_set.dart';

class ApiClient {
  static const String _baseUrl =
      'https://sa03-api-gxd7gve7a9gafnaz.polandcentral-01.azurewebsites.net/api';

  static const String _apiKey = 'ElvisPresly';

  Future<Map<String, dynamic>> getSet(int setId) async {
    final uri = Uri.parse('$_baseUrl/sets/$setId/items');

    final response = await http.get(
      uri,
      headers: {'X-API-Key': _apiKey, 'Accept': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Не удалось загрузить набор $setId. '
        'HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final dynamic decoded = jsonDecode(utf8.decode(response.bodyBytes));

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Ответ API должен содержать JSON-объект.');
    }

    return decoded;
  }

  Future<LearningSet> getLearningSet(int setId) async {
    final json = await getSet(setId);
    return LearningSet.fromJson(json);
  }

  Future<List<int>> getItemAudio({
    required int setId,
    required int itemId,
    required String audioType,
  }) async {
    if (audioType != 'phrase' && audioType != 'translate') {
      throw ArgumentError.value(
        audioType,
        'audioType',
        'Допустимые значения: phrase или translate.',
      );
    }

    final uri = Uri.parse(
      '$_baseUrl/sets/$setId/items/$itemId/mobile-audio/$audioType',
    );

    final response = await http.get(
      uri,
      headers: {'X-API-Key': _apiKey, 'Accept': 'audio/mpeg'},
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Не удалось загрузить аудио $audioType '
        'для элемента $itemId. '
        'HTTP ${response.statusCode}: ${response.body}',
      );
    }

    if (response.bodyBytes.isEmpty) {
      throw Exception('Сервер вернул пустой аудиофайл для элемента $itemId.');
    }

    return response.bodyBytes;
  }
}
