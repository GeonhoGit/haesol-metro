import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/puzzle.dart';

const ink = Color(0xFF11243A);
const mint = Color(0xFF69DFC3);
const coral = Color(0xFFFC786D);
const paper = Color(0xFFF3F0E7);

class GameBoard extends StatelessWidget {
  const GameBoard({
    super.key,
    required this.state,
    required this.onCellTap,
    this.broken = const {},
    this.hintIndex,
    this.trainCell,
  });

  final BoardState state;
  final ValueChanged<int> onCellTap;
  final Set<int> broken;
  final int? hintIndex;
  final int? trainCell;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: boardWidth / boardHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ink,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF27435B), width: 3),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33031525),
              blurRadius: 28,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            itemCount: boardLength,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: boardWidth,
            ),
            itemBuilder: (context, index) {
              final tile = state.puzzle.tiles[index];
              final buildSite = state.isBuildSite(index);
              final installed = state.rails[index];
              final label = tile.kind == TrackKind.start
                  ? '출발역'
                  : tile.kind == TrackKind.destination
                  ? '목적역'
                  : tile.kind == TrackKind.blocked
                  ? '공사 구역, 통행 불가'
                  : buildSite
                  ? '${index ~/ boardWidth + 1}행 ${index % boardWidth + 1}열 ${installed == null ? '빈 설치 칸' : '설치된 선로'}'
                  : '빈 칸';
              return Focus(
                canRequestFocus: buildSite,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      (event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.space)) {
                    onCellTap(index);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (focusContext) {
                    final focused = Focus.of(focusContext).hasFocus;
                    return Padding(
                      padding: const EdgeInsets.all(2),
                      child: Semantics(
                        button: buildSite,
                        label: label,
                        hint: buildSite ? '선택한 선로 설치 또는 회수' : null,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            key: ValueKey('tile-$index'),
                            canRequestFocus: false,
                            onTap: !buildSite
                                ? null
                                : () {
                                    Focus.of(focusContext).requestFocus();
                                    onCellTap(index);
                                  },
                            borderRadius: BorderRadius.circular(10),
                            focusColor: const Color(0x5569DFC3),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                CustomPaint(
                                  painter: _TilePainter(
                                    mask: state.maskAt(index),
                                    kind: state.kindAt(index),
                                    buildSite: buildSite,
                                    error: broken.contains(index),
                                    hinted: hintIndex == index || focused,
                                  ),
                                ),
                                if (buildSite && installed == null)
                                  const Center(
                                    child: Icon(
                                      Icons.add_rounded,
                                      color: Color(0xFF5C7A8E),
                                      size: 20,
                                    ),
                                  ),
                                if (tile.kind == TrackKind.blocked)
                                  const Center(
                                    child: Icon(
                                      Icons.construction_rounded,
                                      color: Color(0xFFFFC978),
                                      size: 28,
                                    ),
                                  ),
                                if (tile.kind == TrackKind.start ||
                                    tile.kind == TrackKind.destination)
                                  Center(
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        color: tile.kind == TrackKind.start
                                            ? mint
                                            : coral,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        tile.kind == TrackKind.start
                                            ? Icons.play_arrow_rounded
                                            : Icons.flag_rounded,
                                        color: ink,
                                        size: 17,
                                      ),
                                    ),
                                  ),
                                if (trainCell == index)
                                  const Center(
                                    child: Icon(
                                      Icons.train_rounded,
                                      color: Colors.white,
                                      size: 30,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TilePainter extends CustomPainter {
  _TilePainter({
    required this.mask,
    required this.kind,
    required this.buildSite,
    required this.error,
    required this.hinted,
  });

  final int mask;
  final TrackKind kind;
  final bool buildSite;
  final bool error;
  final bool hinted;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = Radius.circular(size.width * .14);
    final background = kind == TrackKind.blocked
        ? const Color(0xFF654A36)
        : buildSite && mask == 0
        ? const Color(0xFF28445A)
        : kind == TrackKind.empty
        ? const Color(0xFF172B40)
        : const Color(0xFF203B50);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()..color = background,
    );
    if (mask != 0) {
      final center = Offset(size.width / 2, size.height / 2);
      final endpoints = <int, Offset>{
        north: Offset(center.dx, 0),
        east: Offset(size.width, center.dy),
        south: Offset(center.dx, size.height),
        west: Offset(0, center.dy),
      };
      final rail = Paint()
        ..color = error ? coral : const Color(0xFF0A1827)
        ..strokeWidth = size.width * .22
        ..strokeCap = StrokeCap.round;
      final line = Paint()
        ..color = error ? const Color(0xFFFFB6AA) : mint
        ..strokeWidth = size.width * .095
        ..strokeCap = StrokeCap.round;
      for (final entry in endpoints.entries) {
        if (mask & entry.key == 0) continue;
        canvas.drawLine(center, entry.value, rail);
        canvas.drawLine(center, entry.value, line);
      }
      canvas.drawCircle(center, size.width * .085, Paint()..color = line.color);
    }
    if (error || hinted) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(1), radius),
        Paint()
          ..color = error ? coral : const Color(0xFFFFD16A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TilePainter oldDelegate) =>
      mask != oldDelegate.mask ||
      kind != oldDelegate.kind ||
      buildSite != oldDelegate.buildSite ||
      error != oldDelegate.error ||
      hinted != oldDelegate.hinted;
}

class RailPreview extends StatelessWidget {
  const RailPreview({super.key, required this.kind, required this.rotation});

  final TrackKind kind;
  final int rotation;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 42,
    child: CustomPaint(
      painter: _TilePainter(
        mask: TrackTile(kind, 0, 0).maskAt(rotation),
        kind: kind,
        buildSite: false,
        error: false,
        hinted: false,
      ),
    ),
  );
}
