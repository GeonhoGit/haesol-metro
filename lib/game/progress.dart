import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ProgressData {
  const ProgressData({
    required this.stars,
    required this.bestMoves,
    required this.coins,
    required this.hints,
    required this.soundEnabled,
    required this.vibrationEnabled,
    required this.tutorialSeen,
  });

  factory ProgressData.empty() => const ProgressData(
    stars: {},
    bestMoves: {},
    coins: 0,
    hints: 3,
    soundEnabled: true,
    vibrationEnabled: true,
    tutorialSeen: false,
  );

  final Map<String, int> stars;
  final Map<String, int> bestMoves;
  final int coins;
  final int hints;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final bool tutorialSeen;

  int get unlockedStage {
    for (var i = 1; i <= 30; i++) {
      if ((stars['s${i.toString().padLeft(2, '0')}'] ?? 0) == 0) {
        return i - 1;
      }
    }
    return 29;
  }

  int get totalStars => stars.entries
      .where((entry) => entry.key.startsWith('s'))
      .fold(0, (sum, entry) => sum + entry.value);

  ProgressData recordClear(
    String id,
    int earnedStars,
    int moves, {
    String? bestKey,
  }) {
    final previous = stars[id] ?? 0;
    final nextStars = Map<String, int>.of(stars);
    nextStars[id] = earnedStars > previous ? earnedStars : previous;
    final nextMoves = Map<String, int>.of(bestMoves);
    final recordId = bestKey ?? id;
    if (moves < (nextMoves[recordId] ?? 1 << 30)) nextMoves[recordId] = moves;
    final gained = earnedStars > previous ? earnedStars - previous : 0;
    return copyWith(
      stars: nextStars,
      bestMoves: nextMoves,
      coins: coins + gained * 10,
      hints: hints + (earnedStars == 3 && previous < 3 ? 1 : 0),
    );
  }

  ProgressData copyWith({
    Map<String, int>? stars,
    Map<String, int>? bestMoves,
    int? coins,
    int? hints,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? tutorialSeen,
  }) => ProgressData(
    stars: stars ?? this.stars,
    bestMoves: bestMoves ?? this.bestMoves,
    coins: coins ?? this.coins,
    hints: hints ?? this.hints,
    soundEnabled: soundEnabled ?? this.soundEnabled,
    vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
    tutorialSeen: tutorialSeen ?? this.tutorialSeen,
  );

  String toJson() => jsonEncode({
    'version': 1,
    'stars': stars,
    'bestMoves': bestMoves,
    'coins': coins,
    'hints': hints,
    'soundEnabled': soundEnabled,
    'vibrationEnabled': vibrationEnabled,
    'tutorialSeen': tutorialSeen,
  });

  factory ProgressData.fromJson(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    if (json['version'] != 1) {
      throw const FormatException('Unknown save version');
    }
    return ProgressData(
      stars: (json['stars'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, value as int),
      ),
      bestMoves: (json['bestMoves'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, value as int),
      ),
      coins: json['coins'] as int,
      hints: json['hints'] as int,
      soundEnabled: json['soundEnabled'] as bool,
      vibrationEnabled: json['vibrationEnabled'] as bool,
      tutorialSeen: json['tutorialSeen'] as bool,
    );
  }
}

class ProgressStore {
  ProgressStore._(this._preferences, this.data);

  static const _key = 'haesol_progress_v1';
  final SharedPreferences _preferences;
  ProgressData data;

  static Future<ProgressStore> open() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_key);
    ProgressData data;
    try {
      data = saved == null
          ? ProgressData.empty()
          : ProgressData.fromJson(saved);
    } on FormatException {
      data = ProgressData.empty();
    } on TypeError {
      data = ProgressData.empty();
    }
    return ProgressStore._(preferences, data);
  }

  Future<void> save(ProgressData next) async {
    final stored = await _preferences.setString(_key, next.toJson());
    if (!stored) throw StateError('Unable to save progress');
    data = next;
  }

  Future<void> reset() => save(ProgressData.empty());
}
