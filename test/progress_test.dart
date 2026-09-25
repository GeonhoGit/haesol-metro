import 'package:flutter_test/flutter_test.dart';
import 'package:haesol_metro/game/progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a clear improves records once and unlocks the next stage', () {
    final first = ProgressData.empty().recordClear('s01', 2, 14);
    final repeated = first.recordClear('s01', 1, 18);
    expect(first.coins, 20);
    expect(repeated.coins, 20);
    expect(repeated.stars['s01'], 2);
    expect(repeated.bestMoves['s01'], 14);
    expect(repeated.unlockedStage, 1);
  });

  test('records and settings survive serialization', () {
    final source = ProgressData.empty()
        .recordClear('s01', 3, 9)
        .copyWith(soundEnabled: false, vibrationEnabled: false);
    final restored = ProgressData.fromJson(source.toJson());
    expect(restored.stars['s01'], 3);
    expect(restored.bestMoves['s01'], 9);
    expect(restored.soundEnabled, isFalse);
    expect(restored.vibrationEnabled, isFalse);
  });

  test('local store reloads completed progress', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await ProgressStore.open();
    final saved = ProgressData.empty().recordClear('s01', 3, 8);
    await store.save(saved);
    final reopened = await ProgressStore.open();
    expect(reopened.data.bestMoves['s01'], 8);
    expect(reopened.data.unlockedStage, 1);
  });

  test(
    'new installation records do not compare against old rotation records',
    () {
      final legacy = ProgressData.empty().recordClear('s01', 3, 3);
      final installation = legacy.recordClear(
        's01',
        3,
        5,
        bestKey: 'install-v2/s01',
      );
      expect(installation.stars['s01'], 3);
      expect(installation.bestMoves['s01'], 3);
      expect(installation.bestMoves['install-v2/s01'], 5);
      expect(installation.unlockedStage, 1);
    },
  );
}
