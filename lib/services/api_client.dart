import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../models/learning_set.dart';
import '../models/user_account.dart';
import '../models/user_set.dart';

class ApiClient {
  static const String _baseUrl =
      'https://sa03-api-gxd7gve7a9gafnaz.polandcentral-01.azurewebsites.net/api';

  static const String _apiKey = 'ElvisPresly';

  Future<UserAccount> login({
    required String nickname,
    required String password,
  }) async {
    final uri = Uri.parse('$_baseUrl/login');

    final response = await http.post(
      uri,
      headers: {
        'X-API-Key': _apiKey,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'nickname': nickname, 'password': password}),
    );

    final dynamic decoded = jsonDecode(utf8.decode(response.bodyBytes));

    if (response.statusCode != 200) {
      final message = decoded is Map<String, dynamic>
          ? decoded['error']?.toString() ?? 'Ошибка входа'
          : 'Ошибка входа';

      throw Exception('$message (HTTP ${response.statusCode})');
    }

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Некорректный ответ сервера при входе.');
    }

    return UserAccount.fromJson(decoded);
  }

  Future<List<UserSet>> getUserSets(int userId) async {
    final uri = Uri.parse('$_baseUrl/sets')
        .replace(queryParameters: {'user_id': userId.toString()});

    final response = await http.get(
      uri,
      headers: {'X-API-Key': _apiKey, 'Accept': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Не удалось получить список наборов. '
        'HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final dynamic decoded = jsonDecode(utf8.decode(response.bodyBytes));

    if (decoded is! List) {
      throw const FormatException(
        'Ответ сервера должен содержать список наборов.',
      );
    }

    return decoded
        .map((item) => UserSet.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<List<UserSet>> getMobileReadySets(int userId) async {
    final uri = Uri.parse('$_baseUrl/mobile/sets')
        .replace(queryParameters: {'user_id': userId.toString()});

    final response = await http.get(
      uri,
      headers: {'X-API-Key': _apiKey, 'Accept': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Не удалось получить список готовых мобильных наборов. '
        'HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final dynamic decoded = jsonDecode(utf8.decode(response.bodyBytes));

    if (decoded is! List) {
      throw const FormatException(
        'Ответ сервера должен содержать список наборов.',
      );
    }

    return decoded
        .map((item) => UserSet.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

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

    debugPrint('[API] ===== AUDIO DOWNLOAD START =====');
    debugPrint('[API] GET $uri');
    debugPrint('[API] Set ID: $setId');
    debugPrint('[API] Item ID: $itemId');
    debugPrint('[API] Audio type: $audioType');

    final response = await http.get(
      uri,
      headers: {'X-API-Key': _apiKey, 'Accept': 'audio/mpeg'},
    );

    debugPrint('[API] HTTP ${response.statusCode}');
    debugPrint('[API] Content-Type: ${response.headers['content-type']}');
    debugPrint('[API] Received bytes: ${response.bodyBytes.length}');

    if (response.statusCode != 200) {
      debugPrint(
        '[API] BODY: ${utf8.decode(response.bodyBytes, allowMalformed: true)}',
      );

      throw Exception(
        'Не удалось загрузить аудио $audioType '
        'для элемента $itemId. '
        'HTTP ${response.statusCode}: ${response.body}',
      );
    }

    if (response.bodyBytes.isEmpty) {
      throw Exception('Сервер вернул пустой аудиофайл для элемента $itemId.');
    }

    debugPrint('[API] Audio download successful.');
    debugPrint('[API] ===== AUDIO DOWNLOAD END =====');

    return response.bodyBytes;
  }

  /// Отправляет WAV-запись на сервер для оценки произношения.
  ///
  /// Сервер возвращает JSON с общей оценкой, распознанным текстом
  /// и детализацией ошибок произношения.
  Future<Map<String, dynamic>> assessVoice({
    required String referenceText,
    required String locale,
    required String audioPath,
  }) async {
    final uri = Uri.parse('$_baseUrl/voice-test');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll({'X-API-Key': _apiKey, 'Accept': 'application/json'})
      ..fields['reference_text'] = referenceText
      ..fields['locale'] = locale
      ..files.add(await http.MultipartFile.fromPath('audio', audioPath));

    debugPrint('[API] ===== VOICE ASSESSMENT START =====');
    debugPrint('[API] POST $uri');
    debugPrint('[API] Locale: $locale');
    debugPrint('[API] Reference length: ${referenceText.length}');

    final response = await http.Response.fromStream(await request.send())
        .timeout(const Duration(seconds: 60));

    debugPrint('[API] Voice assessment HTTP ${response.statusCode}');
    debugPrint(
      '[API] Voice assessment response bytes: ${response.bodyBytes.length}',
    );
    debugPrint('[API] ===== VOICE ASSESSMENT END =====');

    final responseBody = utf8.decode(
      response.bodyBytes,
      allowMalformed: true,
    );

    final dynamic decoded;
    try {
      decoded = jsonDecode(responseBody);
    } on FormatException {
      if (kDebugMode) {
        debugPrint('[VOICE TEST JSON] ===== RAW RESPONSE START =====');
        debugPrint(responseBody);
        debugPrint('[VOICE TEST JSON] ===== RAW RESPONSE END =====');
      }

      throw FormatException(
        'Сервер оценки произношения вернул некорректный JSON '
        '(HTTP ${response.statusCode}).',
      );
    }

    if (kDebugMode) {
      debugPrint('[VOICE TEST JSON] ===== RESPONSE START =====');
      debugPrint(const JsonEncoder.withIndent('  ').convert(decoded));
      debugPrint('[VOICE TEST JSON] ===== RESPONSE END =====');
    }

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Ответ сервера оценки произношения должен быть JSON-объектом.',
      );
    }

    return decoded;
  }
}
