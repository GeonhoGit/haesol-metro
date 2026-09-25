import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/catalog.dart';
import '../game/progress.dart';
import '../game/puzzle.dart';
import 'game_board.dart';

class HaesolApp extends StatelessWidget {
  const HaesolApp({super.key, required this.catalog, required this.store});

  final PuzzleCatalog catalog;
  final ProgressStore store;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '지하철 노선 복구',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: paper,
      colorScheme: ColorScheme.fromSeed(seedColor: mint, primary: ink),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: ink,
          fontWeight: FontWeight.w900,
          height: 1.12,
        ),
        headlineMedium: TextStyle(color: ink, fontWeight: FontWeight.w900),
        bodyMedium: TextStyle(color: ink),
      ),
    ),
    home: _Shell(catalog: catalog, store: store),
  );
}

enum _Screen { home, stages, game, result, daily, collection, settings }

class _Shell extends StatefulWidget {
  const _Shell({required this.catalog, required this.store});
  final PuzzleCatalog catalog;
  final ProgressStore store;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  late ProgressData progress = widget.store.data;
  _Screen screen = _Screen.home;
  Puzzle? puzzle;
  BoardState? board;
  PuzzleResult? result;
  DateTime? dailyDate;
  DateTime? started;
  Timer? trainTimer;
  int? trainCell;
  int? hintCell;
  int tutorialStep = -1;
  Set<int> broken = {};
  String? notice;
  TrackKind? selectedKind = TrackKind.straight;
  int selectedRotation = 1;

  @override
  void dispose() {
    trainTimer?.cancel();
    super.dispose();
  }

  void go(_Screen next) {
    trainTimer?.cancel();
    setState(() {
      screen = next;
      trainCell = null;
    });
  }

  void openPuzzle(Puzzle next, {DateTime? forDate}) {
    trainTimer?.cancel();
    setState(() {
      puzzle = next;
      dailyDate = forDate;
      board = BoardState.initial(next);
      result = null;
      broken = {};
      notice = null;
      hintCell = null;
      trainCell = null;
      started = DateTime.now();
      tutorialStep = next.id == 's01' && !progress.tutorialSeen ? 0 : -1;
      screen = _Screen.game;
      selectedKind = TrackKind.straight;
      selectedRotation = 1;
    });
  }

  Future<void> save(ProgressData next) async {
    setState(() => progress = next);
    try {
      await widget.store.save(next);
    } catch (_) {
      if (mounted) showMessage('저장에 실패했습니다. 저장 공간을 확인해 주세요.');
    }
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void install(int index) {
    final next = selectedKind == null
        ? board!.remove(index)
        : board!.place(index, selectedKind!, selectedRotation);
    if (identical(next, board)) {
      if (selectedKind != null &&
          board!.rails[index]?.kind != selectedKind &&
          board!.remaining(selectedKind!) == 0) {
        showMessage('선택한 선로가 부족합니다. 다른 칸에서 회수해 주세요.');
      }
      return;
    }
    if (progress.soundEnabled) SystemSound.play(SystemSoundType.click);
    if (progress.vibrationEnabled) HapticFeedback.selectionClick();
    setState(() {
      board = next;
      broken = {};
      hintCell = null;
      notice = null;
    });
  }

  String railName(TrackKind kind) => switch (kind) {
    TrackKind.straight => '직선',
    TrackKind.curve => '곡선',
    TrackKind.tee => '분기',
    TrackKind.cross => '교차',
    _ => '선로',
  };

  String directionName(int mask) => [
    if (mask & north != 0) '북',
    if (mask & east != 0) '동',
    if (mask & south != 0) '남',
    if (mask & west != 0) '서',
  ].join('·');

  Future<void> hint() async {
    final index = board!.hintIndex;
    if (index == null) {
      showMessage('설치 상태가 모두 맞습니다. 운행을 시작해 보세요.');
    } else if (progress.hints == 0) {
      showMessage('힌트 티켓이 없습니다. 3별 달성 시 1장을 받습니다.');
    } else {
      setState(() {
        hintCell = index;
        final tile = puzzle!.tiles[index];
        notice =
            '노란 칸: ${railName(tile.kind)} · ${directionName(tile.maskAt(tile.solvedRotation))} 방향으로 설치하세요.';
      });
      await save(progress.copyWith(hints: progress.hints - 1));
    }
  }

  void restart() {
    setState(() {
      board = BoardState.initial(puzzle!);
      broken = {};
      notice = null;
      hintCell = null;
      started = DateTime.now();
    });
  }

  Future<void> runTrain() async {
    final checked = board!.evaluate();
    if (checked.stars == 0) {
      setState(() {
        broken = {...checked.brokenTiles, ...board!.unfilledSites};
        notice = board!.unfilledSites.isNotEmpty
            ? '빈 설치 칸을 모두 채운 뒤 운행해 주세요.'
            : broken.isNotEmpty
            ? '붉은 칸에 끊어진 선로가 있습니다.'
            : '출발역과 목적역이 이어지지 않았습니다.';
      });
      return;
    }
    setState(() {
      result = checked;
      trainCell = checked.trainPath.first;
      notice = '열차 운행 중…';
    });
    final key = dailyDate == null
        ? puzzle!.id
        : '${widget.catalog.dailyKey(dailyDate!)}/${puzzle!.id}';
    await save(
      progress.recordClear(
        key,
        checked.stars,
        board!.moves,
        bestKey: 'install-v2/$key',
      ),
    );
    if (!mounted || screen != _Screen.game) return;
    var step = 0;
    trainTimer?.cancel();
    trainTimer = Timer.periodic(const Duration(milliseconds: 130), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      step++;
      if (step >= checked.trainPath.length) {
        timer.cancel();
        setState(() {
          trainCell = null;
          screen = _Screen.result;
        });
      } else {
        setState(() => trainCell = checked.trainPath[step]);
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          topBar(),
          Expanded(
            child: switch (screen) {
              _Screen.home => home(),
              _Screen.stages => stages(),
              _Screen.game => game(),
              _Screen.result => results(),
              _Screen.daily => daily(),
              _Screen.collection => collection(),
              _Screen.settings => settings(),
            },
          ),
        ],
      ),
    ),
  );

  Widget topBar() => Container(
    height: 58,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFFDBE2E0))),
    ),
    child: Row(
      children: [
        if (screen != _Screen.home)
          IconButton(
            tooltip: '뒤로',
            onPressed: () => go(
              screen == _Screen.game || screen == _Screen.result
                  ? _Screen.stages
                  : _Screen.home,
            ),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        const Icon(Icons.subway_rounded, color: ink),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            MediaQuery.sizeOf(context).width < 430 && screen != _Screen.home
                ? '해솔시'
                : '지하철 노선 복구',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
        ),
        badge(Icons.toll_rounded, '${progress.coins}'),
        const SizedBox(width: 6),
        badge(Icons.tips_and_updates_rounded, '${progress.hints}'),
        if (screen == _Screen.home)
          IconButton(
            tooltip: '설정',
            onPressed: () => go(_Screen.settings),
            icon: const Icon(Icons.settings_rounded),
          ),
      ],
    ),
  );

  Widget badge(IconData icon, String count) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        Icon(icon, size: 14),
        const SizedBox(width: 3),
        Text(
          count,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );

  Widget page(Widget child, {double maxWidth = 1080}) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(18, 22, 18, 32),
    child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    ),
  );

  Widget home() => page(
    LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 740;
        final introduction = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            eyebrow('HAESOL CITY · 구도심 01'),
            const SizedBox(height: 14),
            Text(
              '끊어진 길을 잇고,\n도시를 깨우세요.',
              style: TextStyle(
                color: ink,
                fontSize: wide ? 44 : 32,
                height: 1.15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '선로 조각과 방향을 고른 뒤 빈 칸에 설치하세요. 모든 끝을 연결하면 복구 완료!',
              style: TextStyle(color: Color(0xFF53687B), height: 1.5),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                action(
                  '이어하기',
                  Icons.play_arrow_rounded,
                  () =>
                      openPuzzle(widget.catalog.stages[progress.unlockedStage]),
                ),
                outline(
                  '스테이지 선택',
                  Icons.grid_view_rounded,
                  () => go(_Screen.stages),
                ),
              ],
            ),
            const SizedBox(height: 21),
            Text(
              '${progress.stars.keys.where((id) => id.startsWith('s')).length}/30 노선 복구  ·  ${progress.totalStars}/90 별',
              style: const TextStyle(color: ink, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            LinearProgressIndicator(
              value:
                  progress.stars.keys.where((id) => id.startsWith('s')).length /
                  30,
              minHeight: 7,
              color: mint,
              backgroundColor: const Color(0xFFDFE9E5),
              borderRadius: BorderRadius.circular(10),
            ),
          ],
        );
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(25),
              ),
              child: wide
                  ? Row(
                      children: [
                        Expanded(child: introduction),
                        const SizedBox(width: 25),
                        const SizedBox(
                          width: 300,
                          height: 290,
                          child: _RouteArt(),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        introduction,
                        const SizedBox(height: 20),
                        const SizedBox(height: 170, child: _RouteArt()),
                      ],
                    ),
            ),
            const SizedBox(height: 14),
            if (wide)
              Row(
                children: [
                  Expanded(
                    child: homeCard(
                      '오늘의 퍼즐',
                      '매일 자정 새 임무',
                      Icons.today_rounded,
                      () => openPuzzle(
                        widget.catalog.dailyFor(DateTime.now()),
                        forDate: DateTime.now(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: homeCard(
                      '기록 보관함',
                      '지난 퍼즐 다시 풀기',
                      Icons.history_rounded,
                      () => go(_Screen.daily),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: homeCard(
                      '도시 컬렉션',
                      '별과 배지 확인',
                      Icons.emoji_events_rounded,
                      () => go(_Screen.collection),
                    ),
                  ),
                ],
              )
            else
              Column(
                children: [
                  homeCard(
                    '오늘의 퍼즐',
                    '매일 자정 새 임무',
                    Icons.today_rounded,
                    () => openPuzzle(
                      widget.catalog.dailyFor(DateTime.now()),
                      forDate: DateTime.now(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  homeCard(
                    '기록 보관함',
                    '지난 퍼즐 다시 풀기',
                    Icons.history_rounded,
                    () => go(_Screen.daily),
                  ),
                  const SizedBox(height: 10),
                  homeCard(
                    '도시 컬렉션',
                    '별과 배지 확인',
                    Icons.emoji_events_rounded,
                    () => go(_Screen.collection),
                  ),
                ],
              ),
          ],
        );
      },
    ),
  );

  Widget homeCard(
    String title,
    String detail,
    IconData icon,
    VoidCallback onTap,
  ) => Material(
    color: ink,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Row(
          children: [
            Icon(icon, color: mint, size: 28),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: Color(0xFFAAC3CF),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, color: mint, size: 18),
          ],
        ),
      ),
    ),
  );

  Widget stages() => page(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        eyebrow('CHAPTER 01 · HAESOL OLD TOWN'),
        const SizedBox(height: 8),
        const Text(
          '구도심 노선도',
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
        ),
        const Text(
          '하나씩 이어 도시의 30개 구간을 복구하세요.',
          style: TextStyle(color: Color(0xFF66798A)),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 6
                : constraints.maxWidth >= 580
                ? 4
                : 3;
            final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: List.generate(widget.catalog.stages.length, (index) {
                final stage = widget.catalog.stages[index];
                final stars = progress.stars[stage.id] ?? 0;
                final locked = index > progress.unlockedStage;
                return SizedBox(
                  width: width,
                  child: Material(
                    color: locked ? const Color(0xFFE4E9E6) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: locked ? null : () => openPuzzle(stage),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${index + 1}'.padLeft(2, '0'),
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: locked ? Colors.blueGrey : ink,
                                  ),
                                ),
                                Icon(
                                  locked
                                      ? Icons.lock_rounded
                                      : stars > 0
                                      ? Icons.check_circle_rounded
                                      : Icons.route_rounded,
                                  color: locked
                                      ? Colors.blueGrey
                                      : const Color(0xFF25A68B),
                                  size: 17,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              stage.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              stars == 0 ? '미복구' : '★' * stars,
                              style: TextStyle(
                                fontSize: 12,
                                color: stars == 0
                                    ? Colors.blueGrey
                                    : const Color(0xFFD59837),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ],
    ),
  );

  Widget game() => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 760;
      final size = wide
          ? math.min(420.0, (constraints.maxHeight - 60) * .75)
          : math.min(
              constraints.maxWidth - 36,
              math.max(224.0, (constraints.maxHeight - 225) * .75),
            );
      final gameBoard = SizedBox(
        width: size,
        child: GameBoard(
          state: board!,
          onCellTap: install,
          broken: broken,
          hintIndex: hintCell,
          trainCell: trainCell,
        ),
      );
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 17, 18, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: gameControls()),
                      const SizedBox(width: 35),
                      gameBoard,
                    ],
                  )
                : Column(
                    children: [
                      gameControls(),
                      const SizedBox(height: 14),
                      gameBoard,
                    ],
                  ),
          ),
        ),
      );
    },
  );

  Widget gameControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      eyebrow(
        dailyDate == null
            ? '구도심 · STAGE ${puzzle!.id.substring(1)}'
            : 'DAILY · ${widget.catalog.dailyKey(dailyDate!)}',
      ),
      const SizedBox(height: 5),
      Text(
        puzzle!.title,
        style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 6),
      const Text(
        '조각과 방향을 고른 뒤 빈 설치 칸을 누르세요. 공사 칸은 통과할 수 없습니다.',
        style: TextStyle(fontSize: 13, color: Color(0xFF5B7080)),
      ),
      const SizedBox(height: 13),
      Row(
        children: [
          stat('설치', '${board!.placedCount} / ${puzzle!.buildSiteCount}'),
          const SizedBox(width: 8),
          stat('작업 횟수', '${board!.moves}회 · 3★ ${puzzle!.buildSiteCount}회'),
        ],
      ),
      const SizedBox(height: 12),
      railPalette(),
      if (tutorialStep >= 0) tutorial(),
      if (notice != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: broken.isEmpty
                  ? const Color(0xFFDEF5EB)
                  : const Color(0xFFFFE6E1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              notice!,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          action(
            '운행 시작',
            Icons.train_rounded,
            trainCell == null ? runTrain : null,
          ),
          outline(
            '힌트',
            Icons.tips_and_updates_rounded,
            trainCell == null ? hint : null,
          ),
          outline(
            '다시 시작',
            Icons.refresh_rounded,
            trainCell == null ? restart : null,
          ),
        ],
      ),
      const SizedBox(height: 11),
      const Text(
        '설치 칸은 + 표시 · 공사 칸은 통과 불가 · 붉은 칸은 미설치 또는 끊어진 선로입니다.',
        style: TextStyle(fontSize: 12, color: Color(0xFF718491)),
      ),
    ],
  );

  Widget railPalette() {
    const kinds = [
      TrackKind.straight,
      TrackKind.curve,
      TrackKind.tee,
      TrackKind.cross,
    ];
    final choices = kinds.where(
      (kind) => puzzle!.tiles.any((tile) => tile.kind == kind),
    );
    final rotations = selectedKind == TrackKind.straight
        ? 2
        : selectedKind == TrackKind.cross
        ? 1
        : 4;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '설치할 선로 선택',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final kind in choices)
                ChoiceChip(
                  key: ValueKey('rail-kind-${kind.name}'),
                  label: Text('${railName(kind)} ${board!.remaining(kind)}개'),
                  selected: selectedKind == kind,
                  onSelected: (_) => setState(() {
                    selectedKind = kind;
                    selectedRotation = kind == TrackKind.straight ? 1 : 0;
                  }),
                ),
              ChoiceChip(
                key: const ValueKey('rail-remove'),
                label: const Text('회수'),
                selected: selectedKind == null,
                onSelected: (_) => setState(() => selectedKind = null),
              ),
            ],
          ),
          if (selectedKind != null) ...[
            const SizedBox(height: 8),
            const Text(
              '방향 선택',
              style: TextStyle(fontSize: 12, color: Color(0xFF5B7080)),
            ),
            const SizedBox(height: 5),
            Wrap(
              spacing: 7,
              children: [
                for (var rotation = 0; rotation < rotations; rotation++)
                  Tooltip(
                    message: directionName(
                      TrackTile(selectedKind!, 0, 0).maskAt(rotation),
                    ),
                    child: InkWell(
                      key: ValueKey('rail-direction-$rotation'),
                      onTap: () => setState(() => selectedRotation = rotation),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: selectedRotation == rotation
                                ? ink
                                : const Color(0xFFD1DDE3),
                            width: selectedRotation == rotation ? 3 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: RailPreview(
                          kind: selectedKind!,
                          rotation: rotation,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget stat(String title, String value) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 11, color: Color(0xFF718491)),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 17,
              color: ink,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    ),
  );

  Widget tutorial() {
    const titles = ['1 · 선로 고르기', '2 · 선로 설치하기', '3 · 오류와 힌트'];
    const descriptions = [
      '선로 종류와 방향을 먼저 고르세요. 각 종류의 재고는 한정되어 있습니다.',
      '+ 표시된 칸을 눌러 설치하세요. 회수를 선택하면 놓은 선로를 되돌릴 수 있습니다.',
      '모든 칸을 채워 출발역과 목적역을 연결한 뒤 운행해 보세요.',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFDDF6EB),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titles[tutorialStep],
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    descriptions[tutorialStep],
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () {
                if (tutorialStep < 2) {
                  setState(() => tutorialStep++);
                } else {
                  setState(() => tutorialStep = -1);
                  save(progress.copyWith(tutorialSeen: true));
                }
              },
              child: Text(tutorialStep == 2 ? '완료' : '다음'),
            ),
          ],
        ),
      ),
    );
  }

  Widget results() {
    final nextIndex =
        widget.catalog.stages.indexWhere((entry) => entry.id == puzzle!.id) + 1;
    final key = dailyDate == null
        ? puzzle!.id
        : '${widget.catalog.dailyKey(dailyDate!)}/${puzzle!.id}';
    return page(
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(23),
        ),
        child: Column(
          children: [
            const Icon(Icons.train_rounded, size: 55, color: Color(0xFF27AD92)),
            eyebrow('MISSION COMPLETE'),
            const SizedBox(height: 8),
            const Text(
              '노선 복구 완료!',
              style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
            ),
            Text(
              '★' * result!.stars + '☆' * (3 - result!.stars),
              style: const TextStyle(fontSize: 42, color: Color(0xFFDAA143)),
            ),
            Text(
              '${board!.moves}회 작업 · 최고 ${progress.bestMoves['install-v2/$key']}회 · 약 ${DateTime.now().difference(started!).inSeconds}초',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF637A87)),
            ),
            const SizedBox(height: 21),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 9,
              runSpacing: 9,
              children: [
                if (dailyDate == null && nextIndex < 30)
                  action(
                    '다음 스테이지',
                    Icons.arrow_forward_rounded,
                    () => openPuzzle(widget.catalog.stages[nextIndex]),
                  ),
                outline(
                  '다시 풀기',
                  Icons.refresh_rounded,
                  () => openPuzzle(puzzle!, forDate: dailyDate),
                ),
                outline('노선도로', Icons.map_rounded, () => go(_Screen.stages)),
              ],
            ),
          ],
        ),
      ),
      maxWidth: 610,
    );
  }

  Widget daily() => page(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        eyebrow('DAILY SERVICE'),
        const SizedBox(height: 7),
        const Text(
          '일일 퍼즐 기록',
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
        ),
        const Text(
          '오늘과 지난 6일의 퍼즐을 다시 플레이하세요.',
          style: TextStyle(color: Color(0xFF617888)),
        ),
        const SizedBox(height: 18),
        for (var i = 0; i < 7; i++) ...[
          Builder(
            builder: (context) {
              final date = DateTime.now().subtract(Duration(days: i));
              final challenge = widget.catalog.dailyFor(date);
              final key = '${widget.catalog.dailyKey(date)}/${challenge.id}';
              return recordCard(
                i == 0
                    ? '오늘 · ${widget.catalog.dailyKey(date)}'
                    : widget.catalog.dailyKey(date),
                '${challenge.title} · ${progress.stars[key] == null ? '미복구' : '★' * progress.stars[key]!}',
                Icons.today_rounded,
                () => openPuzzle(challenge, forDate: date),
              );
            },
          ),
          const SizedBox(height: 9),
        ],
      ],
    ),
    maxWidth: 700,
  );

  Widget collection() => page(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        eyebrow('CITY RECORD'),
        const SizedBox(height: 7),
        const Text(
          '도시 컬렉션',
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 18),
        recordCard(
          '구도심 복구 배지',
          '${progress.stars.keys.where((id) => id.startsWith('s')).length}/30 구간',
          Icons.workspace_premium_rounded,
          () => go(_Screen.stages),
        ),
        const SizedBox(height: 9),
        recordCard(
          '별의 기록',
          '${progress.totalStars}/90 별',
          Icons.star_rounded,
          () => go(_Screen.stages),
        ),
        const SizedBox(height: 9),
        recordCard('도시 코인', '${progress.coins} 코인', Icons.toll_rounded, () {}),
        const SizedBox(height: 18),
        const Text(
          '열차 스킨과 역 테마는 정식 업데이트에 추가됩니다.',
          style: TextStyle(color: Color(0xFF617888), fontSize: 13),
        ),
      ],
    ),
    maxWidth: 700,
  );

  Widget settings() => page(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        eyebrow('PREFERENCES'),
        const SizedBox(height: 7),
        const Text(
          '설정',
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 17),
        settingSwitch(
          '효과음',
          progress.soundEnabled,
          (value) => save(progress.copyWith(soundEnabled: value)),
        ),
        const SizedBox(height: 9),
        settingSwitch(
          '진동',
          progress.vibrationEnabled,
          (value) => save(progress.copyWith(vibrationEnabled: value)),
        ),
        const SizedBox(height: 17),
        outline('튜토리얼 다시 보기', Icons.help_outline_rounded, () {
          openPuzzle(widget.catalog.stages.first);
          setState(() => tutorialStep = 0);
        }),
        const SizedBox(height: 20),
        const Text(
          '진행도는 이 기기 또는 브라우저 프로필에 저장됩니다.',
          style: TextStyle(color: Color(0xFF617888), fontSize: 13),
        ),
        TextButton.icon(
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('진행도를 초기화할까요?'),
                content: const Text('별점, 코인, 최고 기록이 삭제됩니다.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('취소'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('초기화'),
                  ),
                ],
              ),
            );
            if (confirmed == true) await save(ProgressData.empty());
          },
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('진행도 초기화'),
        ),
      ],
    ),
    maxWidth: 700,
  );

  Widget settingSwitch(String title, bool value, ValueChanged<bool> change) =>
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: SwitchListTile(
          title: Text(title),
          value: value,
          onChanged: change,
        ),
      );

  Widget recordCard(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF23AA91), size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6F8290),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    ),
  );

  Widget eyebrow(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 11,
      letterSpacing: 1.3,
      color: Color(0xFF168D75),
      fontWeight: FontWeight.w900,
    ),
  );

  Widget action(String label, IconData icon, VoidCallback? onPressed) =>
      FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      );

  Widget outline(String label, IconData icon, VoidCallback? onPressed) =>
      OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: Color(0xFFB7C9CC)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      );
}

class _RouteArt extends StatelessWidget {
  const _RouteArt();

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: CustomPaint(
      painter: _RoutePainter(),
      child: const SizedBox.expand(),
    ),
  );
}

class _RoutePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = ink);
    final grid = Paint()
      ..color = const Color(0xFF284258)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 26) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += 26) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final route = Path()
      ..moveTo(size.width * .12, size.height * .2)
      ..lineTo(size.width * .75, size.height * .2)
      ..quadraticBezierTo(
        size.width * .88,
        size.height * .2,
        size.width * .88,
        size.height * .34,
      )
      ..lineTo(size.width * .88, size.height * .6)
      ..quadraticBezierTo(
        size.width * .88,
        size.height * .75,
        size.width * .72,
        size.height * .75,
      )
      ..lineTo(size.width * .27, size.height * .75)
      ..quadraticBezierTo(
        size.width * .12,
        size.height * .75,
        size.width * .12,
        size.height * .88,
      );
    canvas.drawPath(
      route,
      Paint()
        ..color = mint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11
        ..strokeCap = StrokeCap.round,
    );
    for (final point in [
      Offset(size.width * .12, size.height * .2),
      Offset(size.width * .48, size.height * .2),
      Offset(size.width * .88, size.height * .48),
      Offset(size.width * .58, size.height * .75),
      Offset(size.width * .12, size.height * .88),
    ]) {
      canvas.drawCircle(point, 10, Paint()..color = ink);
      canvas.drawCircle(point, 6, Paint()..color = paper);
    }
    canvas.drawCircle(
      Offset(size.width * .48, size.height * .2),
      8,
      Paint()..color = coral,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
