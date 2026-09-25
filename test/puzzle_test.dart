import 'package:flutter_test/flutter_test.dart';
import 'package:haesol_metro/game/puzzle.dart';

void main() {
  final puzzle = Puzzle.fromRoute(
    id: 'test',
    title: '테스트',
    route: [8, 9, 10, 16],
    scrambleSeed: 1,
  );

  test('a rail shape has the expected orientations', () {
    const corner = TrackTile(TrackKind.curve, 0, 0);
    expect(corner.maskAt(0), north | east);
    expect(corner.maskAt(2), south | west);
  });

  test(
    'build sites begin empty and rails are installed from limited stock',
    () {
      final start = BoardState.initial(puzzle);
      expect(start.maskAt(9), 0);
      expect(start.maskAt(10), 0);
      expect(start.remaining(TrackKind.straight), 1);
      expect(start.remaining(TrackKind.curve), 1);
      expect(start.evaluate().stars, 0);

      final first = start.place(9, TrackKind.straight, 1);
      expect(first.maskAt(9), east | west);
      expect(first.remaining(TrackKind.straight), 0);
      expect(first.place(10, TrackKind.straight, 1), same(first));
      final complete = first.place(10, TrackKind.curve, 2);
      expect(complete.moves, 2);
      expect(complete.evaluate().stars, 3);
      expect(complete.evaluate().trainPath, [8, 9, 10, 16]);
    },
  );

  test('rails can be replaced or recovered without rotating placed rails', () {
    final start = BoardState.initial(puzzle);
    final wrong = start.place(9, TrackKind.curve, 0);
    expect(wrong.remaining(TrackKind.curve), 0);
    final replaced = wrong.place(9, TrackKind.straight, 1);
    expect(replaced.remaining(TrackKind.curve), 1);
    expect(replaced.remaining(TrackKind.straight), 0);
    final removed = replaced.remove(9);
    expect(removed.maskAt(9), 0);
    expect(removed.remaining(TrackKind.straight), 1);
    expect(start.place(puzzle.startIndex, TrackKind.straight, 1), same(start));
    expect(start.place(0, TrackKind.straight, 1), same(start));
  });

  test('a corrected installation can finish but loses the perfect score', () {
    final state = BoardState.initial(puzzle)
        .place(9, TrackKind.straight, 0)
        .place(9, TrackKind.straight, 1)
        .place(10, TrackKind.curve, 2);
    expect(state.evaluate().stars, 1);
  });

  test('a broken or incomplete line cannot depart', () {
    final incomplete = BoardState.initial(
      puzzle,
    ).place(9, TrackKind.straight, 1);
    expect(incomplete.unfilledSites, contains(10));
    expect(incomplete.evaluate().stars, 0);
    final broken = incomplete.place(10, TrackKind.curve, 0).evaluate();
    expect(broken.brokenTiles, contains(10));
    expect(broken.stars, 0);
  });

  test('a detached auxiliary loop permits only basic clearance', () {
    final withLoop = puzzle.withAuxiliaryLoop([33, 34, 40, 39]);
    final solved = BoardState.solved(withLoop);
    expect(solved.evaluate().stars, 2);
    expect(solved.evaluate().auxiliaryRouteSolved, isFalse);
  });

  test('branch puzzle builds from empty sites and has two junctions', () {
    final branch = Puzzle.fromBranch(
      id: 'branch',
      title: '환승',
      row: 2,
      scrambleSeed: 3,
    );
    expect(
      branch.tiles.where((tile) => tile.kind == TrackKind.tee),
      hasLength(2),
    );
    expect(BoardState.initial(branch).maskAt(branch.startIndex), isNot(0));
    expect(BoardState.initial(branch).remaining(TrackKind.tee), 2);
    expect(BoardState.initial(branch).evaluate().stars, 0);
    expect(BoardState.solved(branch).evaluate().stars, 3);
  });

  test(
    'construction blocks placement and former fixed rails are empty sites',
    () {
      final network = Puzzle.fromNetwork(
        id: 'network',
        title: '공사 구역',
        route: [12, 13, 7, 8, 9, 10, 16, 22, 23],
        detours: [
          [7, 1, 2, 3, 4, 10],
        ],
        walls: [14, 15, 20, 21],
        lockedRails: [13, 16],
        scrambleSeed: 4,
      );
      final state = BoardState.initial(network);
      expect(state.maskAt(13), 0);
      expect(state.maskAt(14), 0);
      expect(state.place(14, TrackKind.straight, 0), same(state));
      expect(state.isBuildSite(13), isTrue);
      expect(BoardState.solved(network).evaluate().stars, 3);
    },
  );

  test('a wall cannot overlap an active rail', () {
    expect(
      () => Puzzle.fromNetwork(
        id: 'invalid',
        title: '겹침',
        route: [6, 7, 8],
        detours: const [],
        walls: [7],
        lockedRails: const [],
        scrambleSeed: 1,
      ),
      throwsArgumentError,
    );
  });
}
