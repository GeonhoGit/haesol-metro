import 'package:flutter_test/flutter_test.dart';
import 'package:haesol_metro/game/catalog.dart';
import 'package:haesol_metro/game/puzzle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all 30 stages and 7 daily puzzles have playable solutions', () async {
    final catalog = await PuzzleCatalog.load();
    expect(catalog.stages, hasLength(30));
    expect(catalog.daily, hasLength(7));
    for (final puzzle in [...catalog.stages.skip(1), ...catalog.daily]) {
      expect(
        puzzle.tiles.where((tile) => tile.kind == TrackKind.blocked).length,
        greaterThanOrEqualTo(2),
        reason: puzzle.id,
      );
      expect(
        puzzle.buildSiteCount,
        greaterThanOrEqualTo(10),
        reason: puzzle.id,
      );
      expect(
        puzzle.tiles.where((tile) => tile.kind == TrackKind.tee).length,
        greaterThanOrEqualTo(2),
        reason: puzzle.id,
      );
      expect(BoardState.initial(puzzle).placedCount, 0, reason: puzzle.id);
    }
    final ids = <String>{};
    final boards = <String>{};
    for (final puzzle in [...catalog.stages, ...catalog.daily]) {
      expect(ids.add(puzzle.id), isTrue, reason: puzzle.id);
      final signature = puzzle.tiles
          .map(
            (tile) => '${tile.kind.index}:${tile.maskAt(tile.solvedRotation)}',
          )
          .join(',');
      expect(boards.add(signature), isTrue, reason: puzzle.id);
      expect(
        puzzle.tiles.where((tile) => tile.kind == TrackKind.start),
        hasLength(1),
        reason: puzzle.id,
      );
      expect(
        puzzle.tiles.where((tile) => tile.kind == TrackKind.destination),
        hasLength(1),
        reason: puzzle.id,
      );
      expect(BoardState.solved(puzzle).evaluate().stars, 3, reason: puzzle.id);
      expect(BoardState.initial(puzzle).evaluate().stars, 0, reason: puzzle.id);
      expect(puzzle.buildSiteCount, greaterThan(0));
      expect(_countValidSolutions(puzzle), 1, reason: puzzle.id);
    }
  });

  test(
    'same Korean date selects the same daily puzzle across time zones',
    () async {
      final catalog = await PuzzleCatalog.load();
      final utc = DateTime.utc(2026, 9, 25, 14, 59);
      final afterMidnight = DateTime.utc(2026, 9, 25, 15, 01);
      expect(catalog.dailyKey(utc), '20260925');
      expect(catalog.dailyKey(afterMidnight), '20260926');
      expect(
        catalog.dailyFor(afterMidnight).id,
        catalog.dailyFor(afterMidnight.toLocal()).id,
      );
    },
  );
}

int _countValidSolutions(Puzzle puzzle) {
  final candidates = List.generate(boardLength, (index) {
    final tile = puzzle.tiles[index];
    if (tile.fixed) return <int>{tile.maskAt(tile.solvedRotation)};
    return {
      for (var rotation = 0; rotation < 4; rotation++) tile.maskAt(rotation),
    };
  });

  int search(List<Set<int>> options) {
    var changed = true;
    while (changed) {
      changed = false;
      for (var cell = 0; cell < boardLength; cell++) {
        final x = cell % boardWidth;
        final y = cell ~/ boardWidth;
        final neighbors = [
          y == 0 ? -1 : cell - boardWidth,
          x == boardWidth - 1 ? -1 : cell + 1,
          y == boardHeight - 1 ? -1 : cell + boardWidth,
          x == 0 ? -1 : cell - 1,
        ];
        final bits = [north, east, south, west];
        final opposite = [south, west, north, east];
        final allowed = options[cell].where((mask) {
          for (var direction = 0; direction < 4; direction++) {
            final open = mask & bits[direction] != 0;
            final neighbor = neighbors[direction];
            if (neighbor == -1) {
              if (open) return false;
            } else if (!options[neighbor].any(
              (other) => (other & opposite[direction] != 0) == open,
            )) {
              return false;
            }
          }
          return true;
        }).toSet();
        if (allowed.isEmpty) return 0;
        if (allowed.length < options[cell].length) {
          options[cell] = allowed;
          changed = true;
        }
      }
    }
    var choice = -1;
    for (var cell = 0; cell < boardLength; cell++) {
      if (options[cell].length > 1 &&
          (choice == -1 || options[cell].length < options[choice].length)) {
        choice = cell;
      }
    }
    if (choice == -1) {
      final seen = <int>{puzzle.startIndex};
      final queue = <int>[puzzle.startIndex];
      for (var index = 0; index < queue.length; index++) {
        final cell = queue[index];
        final mask = options[cell].single;
        for (final (bit, offset, opposite) in [
          (north, -boardWidth, south),
          (east, 1, west),
          (south, boardWidth, north),
          (west, -1, east),
        ]) {
          final next = cell + offset;
          if (mask & bit != 0 &&
              next >= 0 &&
              next < boardLength &&
              options[next].single & opposite != 0 &&
              seen.add(next)) {
            queue.add(next);
          }
        }
      }
      return seen.contains(puzzle.destinationIndex) ? 1 : 0;
    }
    var solutions = 0;
    for (final mask in options[choice]) {
      final branch = [for (final set in options) Set<int>.of(set)];
      branch[choice] = {mask};
      solutions += search(branch);
      if (solutions > 1) break;
    }
    return solutions;
  }

  return search(candidates);
}
