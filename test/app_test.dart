import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haesol_metro/game/catalog.dart';
import 'package:haesol_metro/game/progress.dart';
import 'package:haesol_metro/main.dart';
import 'package:haesol_metro/game/puzzle.dart';
import 'package:haesol_metro/ui/game_board.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> launch(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final catalog = await PuzzleCatalog.load();
    final store = await ProgressStore.open();
    await tester.pumpWidget(HaesolApp(catalog: catalog, store: store));
    await tester.pump();
  }

  testWidgets('mobile play and desktop stage map stay usable', (tester) async {
    await launch(tester, const Size(360, 640));
    expect(find.text('지하철 노선 복구'), findsWidgets);
    await tester.tap(find.text('이어하기').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('운행 시작'), findsOneWidget);
    expect(find.text('설치'), findsWidgets);
    expect(tester.widget<GameBoard>(find.byType(GameBoard)).state.maskAt(7), 0);
    expect(tester.takeException(), isNull);
    final tile = find.byKey(const ValueKey('tile-7'));
    final vertical = find.byKey(const ValueKey('rail-direction-0'));
    await tester.ensureVisible(vertical);
    await tester.tap(vertical);
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pump();
    expect(
      tester.widget<GameBoard>(find.byType(GameBoard)).state.maskAt(7),
      north | south,
    );
    final horizontal = find.byKey(const ValueKey('rail-direction-1'));
    await tester.ensureVisible(horizontal);
    await tester.tap(horizontal);
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pump();
    expect(find.textContaining('1 /'), findsOneWidget);
    expect(
      tester.widget<GameBoard>(find.byType(GameBoard)).state.maskAt(7),
      east | west,
    );
    final recover = find.byKey(const ValueKey('rail-remove'));
    await tester.ensureVisible(recover);
    await tester.tap(recover);
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pump();
    expect(tester.widget<GameBoard>(find.byType(GameBoard)).state.maskAt(7), 0);
    expect(find.text('직선 3개'), findsOneWidget);
    for (final size in [
      const Size(390, 844),
      const Size(430, 932),
      const Size(768, 1024),
    ]) {
      tester.view.physicalSize = size;
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    tester.view.physicalSize = const Size(1280, 720);
    await tester.pump();
    await tester.tap(find.byTooltip('뒤로'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('구도심 노선도'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('첫 출발'));
    await tester.pump();
    for (final index in [7, 8, 9]) {
      final track = find.byKey(ValueKey('tile-$index'));
      await tester.ensureVisible(track);
      await tester.tap(track);
      await tester.pump();
    }
    await tester.tap(find.text('운행 시작'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('노선 복구 완료!'), findsOneWidget);
  });

  testWidgets('construction is visible and empty build sites accept taps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final puzzle = Puzzle.fromNetwork(
      id: 'display',
      title: '공사 구역',
      route: [12, 13, 7, 8, 9, 10, 16, 22, 23],
      detours: [
        [7, 1, 2, 3, 4, 10],
      ],
      walls: [14, 15, 20, 21],
      lockedRails: [13, 16],
      scrambleSeed: 4,
    );
    final state = BoardState.initial(puzzle);
    var tapped = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: GameBoard(
                state: state,
                onCellTap: (index) => tapped = index,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.construction_rounded), findsNWidgets(4));
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tile-13')));
    await tester.pump();
    expect(tapped, 13);
    expect(state.maskAt(13), 0);
    expect(tester.takeException(), isNull);
  });
}
