import 'dart:convert';

import 'package:flutter/services.dart';

import 'puzzle.dart';

class PuzzleCatalog {
  const PuzzleCatalog(this.stages, this.daily);

  final List<Puzzle> stages;
  final List<Puzzle> daily;

  static Future<PuzzleCatalog> load() async => PuzzleCatalog.fromJson(
    await rootBundle.loadString('assets/puzzles.json'),
  );

  factory PuzzleCatalog.fromJson(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    final blueprints = (json['blueprints'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, (value as List).cast<int>()),
    );
    final networks = (json['networks'] as Map<String, dynamic>?) ?? const {};

    List<Puzzle> read(String key) => (json[key] as List)
        .map((entry) {
          final data = entry as Map<String, dynamic>;
          final id = data['id'] as String;
          final title = data['title'] as String;
          final seed = id.codeUnits.fold(0, (a, b) => a + b);
          if (data['network'] case final String networkId) {
            final network = networks[networkId] as Map<String, dynamic>;
            final transform = data['transform'] as int;
            if (transform < 0 || transform > 3) {
              throw FormatException('Invalid network transform for $id');
            }
            int cell(int index) {
              final x = index % boardWidth;
              final y = index ~/ boardWidth;
              final reflectedX = transform & 1 == 0 ? x : boardWidth - 1 - x;
              final reflectedY = transform & 2 == 0 ? y : boardHeight - 1 - y;
              return reflectedY * boardWidth + reflectedX;
            }

            List<int> cells(String key) => [
              for (final index in (network[key] as List).cast<int>())
                cell(index),
            ];
            return Puzzle.fromNetwork(
              id: id,
              title: title,
              route: cells('route'),
              detours: [
                for (final path in network['detours'] as List)
                  [for (final index in (path as List).cast<int>()) cell(index)],
              ],
              walls: cells('walls'),
              lockedRails: cells('locked'),
              scrambleSeed: seed,
            );
          }
          if (data['branchRow'] case final int row) {
            return Puzzle.fromBranch(
              id: id,
              title: title,
              row: row,
              scrambleSeed: seed,
            );
          }
          final route = blueprints[data['path']]!;
          final from = data['from'] as int;
          final length = data['length'] as int;
          if (from < 0 || length < 3 || from + length > route.length) {
            throw FormatException('Invalid route slice for ${data['id']}');
          }
          return Puzzle.fromRoute(
            id: id,
            title: title,
            route: route.sublist(from, from + length),
            scrambleSeed: seed,
          );
        })
        .toList(growable: false);

    return PuzzleCatalog(read('stages'), read('daily'));
  }

  String dailyKey(DateTime moment) {
    final korean = moment.toUtc().add(const Duration(hours: 9));
    return '${korean.year.toString().padLeft(4, '0')}'
        '${korean.month.toString().padLeft(2, '0')}'
        '${korean.day.toString().padLeft(2, '0')}';
  }

  Puzzle dailyFor(DateTime moment) {
    final korean = moment.toUtc().add(const Duration(hours: 9));
    final date = DateTime.utc(korean.year, korean.month, korean.day);
    final anchor = DateTime.utc(2026, 9, 25);
    final index =
        ((date.difference(anchor).inDays % daily.length) + daily.length) %
        daily.length;
    return daily[index];
  }
}
