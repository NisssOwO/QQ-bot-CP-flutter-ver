import 'dart:convert';
import 'dart:isolate';

/// Runs JSON decoding away from Flutter's UI isolate.
Future<Object?> decodeJsonInBackground(String source) {
  return Isolate.run<Object?>(() => jsonDecode(source));
}

/// Filters primitive log records away from Flutter's UI isolate.
Future<List<int>> filterLogIndexesInBackground(
  List<Map<String, Object?>> entries,
  String? level,
  String module,
) {
  return Isolate.run<List<int>>(() {
    final needle = module.trim().toLowerCase();
    return [
      for (var index = 0; index < entries.length; index++)
        if ((level == null || entries[index]['level'] == level) &&
            (needle.isEmpty ||
                '${entries[index]['module'] ?? ''}'.toLowerCase() == needle))
          index,
    ];
  });
}
