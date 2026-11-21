import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'voice_alarm_parser.dart';

class GeminiParseOutcome {
  final StructuredVoiceAlarmResult? result;
  final bool networkError;
  final String? errorMessage;

  const GeminiParseOutcome({
    this.result,
    this.networkError = false,
    this.errorMessage,
  });
}

/// LLM-based Egyptian Arabic alarm parser using the Gemini API with strict JSON schema output.
/// Never hardcodes API keys; callers pass a key from SharedPreferences or --dart-define.
class GeminiVoiceParser {
  static const String defaultModel = 'gemini-2.5-flash';
  static const Duration requestTimeout = Duration(seconds: 8);

  /// Optional compile-time key via `--dart-define=GEMINI_API_KEY=...`
  static const String envApiKey = String.fromEnvironment('GEMINI_API_KEY');

  static String resolveApiKey(String? userSavedKey) {
    final trimmed = userSavedKey?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
    return envApiKey.trim();
  }

  static Future<GeminiParseOutcome> parseEgyptianArabic({
    required String transcript,
    required String apiKey,
    DateTime? nowLocal,
    String timezoneId = 'Africa/Cairo',
    String? previousContextSummary,
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty || transcript.trim().isEmpty) {
      return const GeminiParseOutcome(result: null);
    }

    final now = nowLocal ?? DateTime.now();
    final nowIso = _formatLocalIso(now);
    const weekdayNames = {
      DateTime.monday: 'Monday (الاثنين)',
      DateTime.tuesday: 'Tuesday (الثلاثاء)',
      DateTime.wednesday: 'Wednesday (الأربعاء)',
      DateTime.thursday: 'Thursday (الخميس)',
      DateTime.friday: 'Friday (الجمعة)',
      DateTime.saturday: 'Saturday (السبت)',
      DateTime.sunday: 'Sunday (الأحد)',
    };
    final todayWeekday = weekdayNames[now.weekday] ?? '';

    final systemPrompt = '''
You are an Egyptian Arabic (and mixed English) alarm & reminder parser for the "U3m Alarm" Android app.
Current local date/time: $nowIso ($todayWeekday)
User timezone: $timezoneId

Extract the alarm details from the user's utterance and return ONLY valid JSON matching the schema:
{
  "title": string,
  "datetime": string or null (ISO-8601 local format YYYY-MM-DDTHH:MM:SS),
  "repeat": "none" | "daily" | "weekly" | "custom",
  "custom_weekdays": array of integers (ISO-8601: 1=Monday .. 7=Sunday),
  "needs_clarification": boolean,
  "question": string or null (short Egyptian Arabic question if needs_clarification is true)
}

Rules:
1. Understand Egyptian Arabic trigger phrases: فكرني، نبهني، صحيني، ظبطلي منبه، حطلي منبه، عايز منبه، ذكرني.
2. Understand Arabic-Indic digits (٠١٢٣٤٥٦٧٨٩), Arabic number words (واحدة، اتنين، تلاتة، ستة، سبعة، تسعة، عشرة...), and mixed forms.
3. Day words: النهارده/اليوم/الليلة (today), بكره (tomorrow), بعد بكره (+2 days), يوم الخميس (next Thursday), الأسبوع الجاي (+7 days or next week's day), كل يوم (daily), كل اتنين وخميس (repeat="custom", custom_weekdays=[1,4]).
4. Day periods for AM/PM:
   - الصبح / الفجر / صباحاً => AM
   - الضهر => 12:00 (or 13..16 for 1..4 الضهر)
   - العصر / المغرب / العشا / بالليل / مساءً => PM
   - بعد نص الليل => 00:00..05:59 AM
   - If NO period is given and no future date is given, pick the next upcoming occurrence of that clock time.
5. Relative times: بعد ساعة (+60m), كمان ساعتين (+120m), كمان ١٠ دقايق (+10m), بعد نص ساعة (+30m), كمان ساعة ونص (+90m).
6. Fractions: ونص (:30), وربع (:15), وتلت (:20), وخمسة (:05), إلا ربع (hour-1 :45), إلا تلت (hour-1 :40).
7. Clean the task title by removing trigger/date/time filler words (e.g. "فكرني بكره الساعه ٧ الصبح اخد الدوا" -> title: "اخد الدوا").
8. If NO time is provided (e.g. "فكرني اشتري عيش"), set datetime=null, needs_clarification=true, question="تحب أفكرك امتى؟".
9. If the user explicitly said today ("النهارده"/"اليوم") with a time that has ALREADY PASSED relative to $nowIso, set needs_clarification=true and ask a short Egyptian Arabic question (e.g. asking if they want it tomorrow at the same time).
10. Keep questions short, friendly, and in natural Egyptian Arabic.
''';

    final userPrompt = previousContextSummary != null && previousContextSummary.isNotEmpty
        ? 'Previous draft context: $previousContextSummary\nUser follow-up: $transcript'
        : transcript;

    final body = {
      'systemInstruction': {
        'parts': [
          {'text': systemPrompt}
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': userPrompt}
          ],
        }
      ],
      'generationConfig': {
        'temperature': 0.1,
        'responseMimeType': 'application/json',
        'responseSchema': {
          'type': 'OBJECT',
          'properties': {
            'title': {'type': 'STRING'},
            'datetime': {'type': 'STRING', 'nullable': true},
            'repeat': {
              'type': 'STRING',
              'enum': ['none', 'daily', 'weekly', 'custom'],
            },
            'custom_weekdays': {
              'type': 'ARRAY',
              'items': {'type': 'INTEGER'},
            },
            'needs_clarification': {'type': 'BOOLEAN'},
            'question': {'type': 'STRING', 'nullable': true},
          },
          'required': [
            'title',
            'datetime',
            'repeat',
            'needs_clarification',
            'question',
          ],
        },
      },
    };

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = requestTimeout;
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$defaultModel:generateContent?key=${Uri.encodeQueryComponent(key)}',
      );
      final req = await client.postUrl(uri).timeout(requestTimeout);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      req.add(utf8.encode(jsonEncode(body)));

      final res = await req.close().timeout(requestTimeout);
      final responseBody = await res.transform(utf8.decoder).join().timeout(requestTimeout);

      if (res.statusCode < 200 || res.statusCode >= 300) {
        return GeminiParseOutcome(
          result: null,
          errorMessage: 'HTTP ${res.statusCode}',
        );
      }

      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
      final candidates = decoded['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) {
        return const GeminiParseOutcome(result: null);
      }
      final parts = (candidates.first['content']?['parts'] as List<dynamic>?);
      if (parts == null || parts.isEmpty) {
        return const GeminiParseOutcome(result: null);
      }
      final rawJsonText = parts.first['text']?.toString() ?? '';
      if (rawJsonText.trim().isEmpty) {
        return const GeminiParseOutcome(result: null);
      }

      final parsedMap = jsonDecode(rawJsonText) as Map<String, dynamic>;
      return GeminiParseOutcome(
        result: StructuredVoiceAlarmResult.fromJson(parsedMap),
      );
    } on SocketException {
      return const GeminiParseOutcome(
        result: null,
        networkError: true,
        errorMessage: 'لا يوجد اتصال بالإنترنت، تم استخدام التحليل المحلي',
      );
    } on TimeoutException {
      return const GeminiParseOutcome(
        result: null,
        networkError: true,
        errorMessage: 'انتهت مهلة الاتصال، تم استخدام التحليل المحلي',
      );
    } catch (e) {
      return GeminiParseOutcome(
        result: null,
        errorMessage: e.toString(),
      );
    } finally {
      client?.close(force: true);
    }
  }

  static String _formatLocalIso(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y-$mo-${d}T$h:$mi:$s';
  }
}
