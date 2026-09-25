import 'dart:collection';

const int boardWidth = 6;
const int boardHeight = 8;
const int boardLength = boardWidth * boardHeight;
const int north = 1;
const int east = 2;
const int south = 4;
const int west = 8;

enum TrackKind {
  empty,
  blocked,
  straight,
  curve,
  tee,
  cross,
  start,
  destination,
}

class TrackTile {
  const TrackTile(
    this.kind,
    this.initialRotation,
    this.solvedRotation, {
    this.locked = false,
  });

  final TrackKind kind;
  final int initialRotation;
  final int solvedRotation;
  final bool locked;

  bool get fixed =>
      kind == TrackKind.empty ||
      kind == TrackKind.blocked ||
      kind == TrackKind.start ||
      kind == TrackKind.destination ||
      locked;

  int maskAt(int rotation) {
    final base = switch (kind) {
      TrackKind.empty => 0,
      TrackKind.blocked => 0,
      TrackKind.straight => north | south,
      TrackKind.curve => north | east,
      TrackKind.tee => north | east | west,
      TrackKind.cross => north | east | south | west,
      TrackKind.start || TrackKind.destination => north,
    };
    var result = base;
    for (var step = 0; step < rotation % 4; step++) {
      result = ((result << 1) & 15) | ((result & west) >> 3);
    }
    return result;
  }
}

class Puzzle {
  const Puzzle._({
    required this.id,
    required this.title,
    required this.tiles,
    required this.startIndex,
    required this.destinationIndex,
    required this.auxiliaryIndices,
    required this.targetMoves,
    required this.rotationLimit,
  });

  final String id;
  final String title;
  final List<TrackTile> tiles;
  final int startIndex;
  final int destinationIndex;
  final List<int> auxiliaryIndices;
  final int targetMoves;
  final int rotationLimit;

  int get buildSiteCount => tiles.where((tile) => _isRail(tile.kind)).length;

  factory Puzzle.fromNetwork({
    required String id,
    required String title,
    required List<int> route,
    required List<List<int>> detours,
    required List<int> walls,
    required List<int> lockedRails,
    required int scrambleSeed,
  }) {
    if (route.length < 3 ||
        route.any((cell) => cell < 0 || cell >= boardLength) ||
        route.toSet().length != route.length) {
      throw ArgumentError('Invalid network route for $id');
    }
    final masks = List<int>.filled(boardLength, 0);
    void addPath(List<int> path) {
      for (var step = 1; step < path.length; step++) {
        final from = path[step - 1];
        final to = path[step];
        if (from < 0 || from >= boardLength || to < 0 || to >= boardLength) {
          throw ArgumentError('Network path outside board for $id');
        }
        final direction = directionBetween(from, to);
        final opposite = directionBetween(to, from);
        masks[from] |= direction;
        masks[to] |= opposite;
      }
    }

    addPath(route);
    final auxiliary = <int>{};
    for (final detour in detours) {
      if (detour.length < 3 ||
          !route.contains(detour.first) ||
          !route.contains(detour.last) ||
          detour.toSet().length != detour.length) {
        throw ArgumentError('Invalid detour for $id');
      }
      addPath(detour);
      auxiliary.addAll(detour);
    }
    final blocked = walls.toSet();
    if (blocked.length != walls.length ||
        blocked.any(
          (cell) => cell < 0 || cell >= boardLength || masks[cell] != 0,
        )) {
      throw ArgumentError('Invalid construction wall for $id');
    }
    final anchors = lockedRails.toSet();
    if (anchors.length != lockedRails.length ||
        anchors.any(
          (cell) =>
              cell < 0 ||
              cell >= boardLength ||
              masks[cell] == 0 ||
              cell == route.first ||
              cell == route.last,
        )) {
      throw ArgumentError('Invalid locked rail for $id');
    }
    final tiles = <TrackTile>[];
    var target = 0;
    for (var index = 0; index < boardLength; index++) {
      final mask = masks[index];
      final kind = blocked.contains(index)
          ? TrackKind.blocked
          : index == route.first
          ? TrackKind.start
          : index == route.last
          ? TrackKind.destination
          : mask == 0
          ? TrackKind.empty
          : mask == 15
          ? TrackKind.cross
          : _bitCount(mask) == 3
          ? TrackKind.tee
          : mask == north | south || mask == east | west
          ? TrackKind.straight
          : TrackKind.curve;
      final solved = _rotationFor(kind, mask);
      final locked = anchors.contains(index);
      final scramble =
          !locked &&
          kind != TrackKind.empty &&
          kind != TrackKind.blocked &&
          kind != TrackKind.start &&
          kind != TrackKind.destination &&
          kind != TrackKind.cross &&
          (index * 7 + scrambleSeed) % 5 < 3;
      final offset = !scramble
          ? 0
          : kind == TrackKind.straight
          ? 1
          : 1 + ((index + scrambleSeed) % 3);
      tiles.add(TrackTile(kind, (solved + offset) % 4, solved, locked: locked));
      if (offset > 0) target += kind == TrackKind.straight ? 1 : 4 - offset;
    }
    if (target == 0) throw ArgumentError('Network has no moves for $id');
    return Puzzle._(
      id: id,
      title: title,
      tiles: List.unmodifiable(tiles),
      startIndex: route.first,
      destinationIndex: route.last,
      auxiliaryIndices: List.unmodifiable(auxiliary),
      targetMoves: target,
      rotationLimit: target + 4,
    );
  }

  factory Puzzle.fromRoute({
    required String id,
    required String title,
    required List<int> route,
    required int scrambleSeed,
  }) {
    if (route.length < 3 ||
        route.any((cell) => cell < 0 || cell >= boardLength) ||
        route.toSet().length != route.length) {
      throw ArgumentError('Invalid route cells for $id');
    }
    final tiles = List<TrackTile>.filled(
      boardLength,
      const TrackTile(TrackKind.empty, 0, 0),
    );
    var target = 0;
    for (var step = 0; step < route.length; step++) {
      final index = route[step];
      var mask = 0;
      if (step > 0) mask |= directionBetween(index, route[step - 1]);
      if (step < route.length - 1) {
        mask |= directionBetween(index, route[step + 1]);
      }
      final kind = step == 0
          ? TrackKind.start
          : step == route.length - 1
          ? TrackKind.destination
          : mask == north | south || mask == east | west
          ? TrackKind.straight
          : TrackKind.curve;
      final solved = _rotationFor(kind, mask);
      final offset = kind == TrackKind.straight
          ? 1
          : kind == TrackKind.curve
          ? 1 + ((step + scrambleSeed) % 3)
          : 0;
      final initial = (solved + offset) % 4;
      tiles[index] = TrackTile(kind, initial, solved);
      if (offset > 0) target += kind == TrackKind.straight ? 1 : 4 - offset;
    }
    return Puzzle._(
      id: id,
      title: title,
      tiles: List.unmodifiable(tiles),
      startIndex: route.first,
      destinationIndex: route.last,
      auxiliaryIndices: const [],
      targetMoves: target,
      rotationLimit: target + 8,
    );
  }

  factory Puzzle.fromBranch({
    required String id,
    required String title,
    required int row,
    required int scrambleSeed,
  }) {
    if (row < 0 || row > boardHeight - 3) {
      throw ArgumentError('Branch row outside board: $row');
    }
    final start = row * boardWidth + 1;
    final firstTee = start + 1;
    final secondTee = start + 2;
    final destination = start + 3;
    final leftTop = firstTee + boardWidth;
    final leftBottom = leftTop + boardWidth;
    final rightBottom = leftBottom + 1;
    final rightTop = rightBottom - boardWidth;
    final layout = <(int, TrackKind, int)>[
      (start, TrackKind.start, east),
      (firstTee, TrackKind.tee, west | east | south),
      (secondTee, TrackKind.tee, west | east | south),
      (destination, TrackKind.destination, west),
      (leftTop, TrackKind.straight, north | south),
      (leftBottom, TrackKind.curve, north | east),
      (rightBottom, TrackKind.curve, north | west),
      (rightTop, TrackKind.straight, north | south),
    ];
    final tiles = List<TrackTile>.filled(
      boardLength,
      const TrackTile(TrackKind.empty, 0, 0),
    );
    var target = 0;
    for (var step = 0; step < layout.length; step++) {
      final (index, kind, mask) = layout[step];
      final solved = _rotationFor(kind, mask);
      final offset = kind == TrackKind.straight
          ? 1
          : kind == TrackKind.curve || kind == TrackKind.tee
          ? 1 + ((step + scrambleSeed) % 3)
          : 0;
      tiles[index] = TrackTile(kind, (solved + offset) % 4, solved);
      if (offset > 0) target += kind == TrackKind.straight ? 1 : 4 - offset;
    }
    return Puzzle._(
      id: id,
      title: title,
      tiles: List.unmodifiable(tiles),
      startIndex: start,
      destinationIndex: destination,
      auxiliaryIndices: List.unmodifiable([
        leftTop,
        leftBottom,
        rightBottom,
        rightTop,
      ]),
      targetMoves: target,
      rotationLimit: target + 8,
    );
  }

  Puzzle copyWith({int? rotationLimit}) => Puzzle._(
    id: id,
    title: title,
    tiles: tiles,
    startIndex: startIndex,
    destinationIndex: destinationIndex,
    auxiliaryIndices: auxiliaryIndices,
    targetMoves: targetMoves,
    rotationLimit: rotationLimit ?? this.rotationLimit,
  );

  Puzzle withAuxiliaryLoop(List<int> loop) {
    if (loop.length != 4 || loop.toSet().length != 4) {
      throw ArgumentError('An auxiliary loop needs four distinct cells');
    }
    final updated = List<TrackTile>.of(tiles);
    for (var i = 0; i < loop.length; i++) {
      final index = loop[i];
      if (index < 0 ||
          index >= boardLength ||
          updated[index].kind != TrackKind.empty) {
        throw ArgumentError('Auxiliary cell unavailable: $index');
      }
      final mask =
          directionBetween(index, loop[(i + 3) % 4]) |
          directionBetween(index, loop[(i + 1) % 4]);
      updated[index] = TrackTile(
        TrackKind.curve,
        _rotationFor(TrackKind.curve, mask),
        _rotationFor(TrackKind.curve, mask),
      );
    }
    return Puzzle._(
      id: id,
      title: title,
      tiles: List.unmodifiable(updated),
      startIndex: startIndex,
      destinationIndex: destinationIndex,
      auxiliaryIndices: List.unmodifiable(loop),
      targetMoves: targetMoves,
      rotationLimit: rotationLimit,
    );
  }
}

int directionBetween(int from, int to) {
  if (from ~/ boardWidth == to ~/ boardWidth) {
    if (to == from + 1) return east;
    if (to == from - 1) return west;
  }
  if (to == from - boardWidth) return north;
  if (to == from + boardWidth) return south;
  throw ArgumentError('Non-adjacent route cells: $from, $to');
}

int _rotationFor(TrackKind kind, int mask) {
  final tile = TrackTile(kind, 0, 0);
  for (var rotation = 0; rotation < 4; rotation++) {
    if (tile.maskAt(rotation) == mask) return rotation;
  }
  throw ArgumentError('Track shape does not fit: $kind, $mask');
}

int _bitCount(int mask) {
  var count = 0;
  while (mask != 0) {
    count += mask & 1;
    mask >>= 1;
  }
  return count;
}

bool _isRail(TrackKind kind) =>
    kind == TrackKind.straight ||
    kind == TrackKind.curve ||
    kind == TrackKind.tee ||
    kind == TrackKind.cross;

class PlacedRail {
  const PlacedRail(this.kind, this.rotation);

  final TrackKind kind;
  final int rotation;

  int get mask => TrackTile(kind, 0, 0).maskAt(rotation);
}

class BoardState {
  const BoardState._(this.puzzle, this.rails, this.moves);

  factory BoardState.initial(Puzzle puzzle) => BoardState._(
    puzzle,
    List<PlacedRail?>.unmodifiable(List.filled(boardLength, null)),
    0,
  );

  factory BoardState.solved(Puzzle puzzle) => BoardState._(
    puzzle,
    List<PlacedRail?>.unmodifiable([
      for (final tile in puzzle.tiles)
        _isRail(tile.kind) ? PlacedRail(tile.kind, tile.solvedRotation) : null,
    ]),
    0,
  );

  final Puzzle puzzle;
  final List<PlacedRail?> rails;
  final int moves;

  bool isBuildSite(int index) =>
      index >= 0 && index < boardLength && _isRail(puzzle.tiles[index].kind);

  TrackKind kindAt(int index) => isBuildSite(index)
      ? rails[index]?.kind ?? TrackKind.empty
      : puzzle.tiles[index].kind;

  int maskAt(int index) => isBuildSite(index)
      ? rails[index]?.mask ?? 0
      : puzzle.tiles[index].maskAt(puzzle.tiles[index].solvedRotation);

  int remaining(TrackKind kind) {
    if (!_isRail(kind)) return 0;
    final supply = puzzle.tiles.where((tile) => tile.kind == kind).length;
    final used = rails.where((rail) => rail?.kind == kind).length;
    return supply - used;
  }

  int get placedCount => rails.where((rail) => rail != null).length;

  Set<int> get unfilledSites => {
    for (var index = 0; index < boardLength; index++)
      if (isBuildSite(index) && rails[index] == null) index,
  };

  BoardState place(int index, TrackKind kind, int rotation) {
    if (!isBuildSite(index) ||
        !_isRail(kind) ||
        rotation < 0 ||
        rotation > 3 ||
        (kind == TrackKind.cross && rotation != 0) ||
        (kind == TrackKind.straight && rotation > 1)) {
      return this;
    }
    final old = rails[index];
    if (old?.kind == kind && old?.rotation == rotation) return this;
    if (old?.kind != kind && remaining(kind) == 0) return this;
    final changed = List<PlacedRail?>.of(rails);
    changed[index] = PlacedRail(kind, rotation);
    return BoardState._(puzzle, List.unmodifiable(changed), moves + 1);
  }

  BoardState remove(int index) {
    if (!isBuildSite(index) || rails[index] == null) return this;
    final changed = List<PlacedRail?>.of(rails);
    changed[index] = null;
    return BoardState._(puzzle, List.unmodifiable(changed), moves + 1);
  }

  int? get hintIndex {
    for (var i = 0; i < boardLength; i++) {
      if (!isBuildSite(i)) continue;
      final expected = puzzle.tiles[i];
      if (rails[i]?.kind != expected.kind ||
          maskAt(i) != expected.maskAt(expected.solvedRotation)) {
        return i;
      }
    }
    return null;
  }

  PuzzleResult evaluate() {
    final broken = <int>{};
    final neighbours = <int, List<int>>{};
    for (var i = 0; i < boardLength; i++) {
      final mask = maskAt(i);
      for (final direction in [north, east, south, west]) {
        if (mask & direction == 0) continue;
        final next = switch (direction) {
          north => i - boardWidth,
          east => i + 1,
          south => i + boardWidth,
          _ => i - 1,
        };
        final edge =
            next < 0 ||
            next >= boardLength ||
            (direction == east && i % boardWidth == boardWidth - 1) ||
            (direction == west && i % boardWidth == 0);
        if (edge) {
          broken.add(i);
          continue;
        }
        final opposite = switch (direction) {
          north => south,
          east => west,
          south => north,
          _ => east,
        };
        if (maskAt(next) & opposite == 0) {
          broken.add(i);
          continue;
        }
        neighbours.putIfAbsent(i, () => []).add(next);
      }
    }

    final visited = <int>{puzzle.startIndex};
    final parents = <int, int>{};
    final queue = Queue<int>()..add(puzzle.startIndex);
    while (queue.isNotEmpty) {
      final cell = queue.removeFirst();
      for (final next in neighbours[cell] ?? const <int>[]) {
        if (visited.add(next)) {
          parents[next] = cell;
          queue.add(next);
        }
      }
    }
    final connected = visited.contains(puzzle.destinationIndex);
    final auxiliaryConnected = puzzle.auxiliaryIndices.every(visited.contains);
    final path = <int>[];
    if (connected) {
      var cell = puzzle.destinationIndex;
      path.add(cell);
      while (cell != puzzle.startIndex) {
        cell = parents[cell]!;
        path.add(cell);
      }
    }
    final clean = broken.isEmpty && connected && unfilledSites.isEmpty;
    final stars = !clean
        ? 0
        : moves > puzzle.buildSiteCount
        ? 1
        : auxiliaryConnected
        ? 3
        : 2;
    return PuzzleResult(
      brokenTiles: Set.unmodifiable(broken),
      requiredRouteSolved: connected,
      auxiliaryRouteSolved: auxiliaryConnected,
      stars: stars,
      trainPath: List.unmodifiable(path.reversed),
    );
  }
}

class PuzzleResult {
  const PuzzleResult({
    required this.brokenTiles,
    required this.requiredRouteSolved,
    required this.auxiliaryRouteSolved,
    required this.stars,
    required this.trainPath,
  });

  final Set<int> brokenTiles;
  final bool requiredRouteSolved;
  final bool auxiliaryRouteSolved;
  final int stars;
  final List<int> trainPath;
}
