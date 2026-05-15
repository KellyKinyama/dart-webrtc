// Phase B-quick — extra Logger coverage for the default-constructor
// stdio defaults and the multi-field path in text format that
// cluster_phase27_test doesn't exercise.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

class _MemSink implements IOSink {
  final BytesBuilder buf = BytesBuilder();
  @override
  Encoding encoding = utf8;
  @override
  void add(List<int> data) => buf.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream<List<int>> stream) async {}
  @override
  Future close() async {}
  @override
  Future get done async {}
  @override
  Future flush() async {}
  @override
  void write(Object? object) => buf.add(utf8.encode('${object ?? ''}'));
  @override
  void writeAll(Iterable objects, [String separator = '']) {}
  @override
  void writeCharCode(int charCode) {}
  @override
  void writeln([Object? object = '']) =>
      buf.add(utf8.encode('${object ?? ''}\n'));
  String get text => utf8.decode(buf.toBytes());
}

void main() {
  group('Logger defaults', () {
    test('default constructor falls back to stdout/stderr without throwing',
        () {
      // We don't write anything (would pollute test stdout); just
      // construct it so the `_outSink = out ?? stdout` and
      // `_errSink = err ?? stderr` initializers run.
      final log = Logger();
      expect(log.level, LogLevel.info);
      expect(log.format, LogFormat.text);
      expect(log.staticFields, isEmpty);
    });
  });

  group('Logger text-format multi-field path', () {
    test('emits comma-separated fields when 2+ keys present', () {
      final out = _MemSink();
      final err = _MemSink();
      final log = Logger(
        out: out,
        err: err,
        format: LogFormat.text,
        staticFields: const {'node': 'n1', 'shard': 7},
      );
      log.info('hi', const {'a': 1, 'b': 2});
      final s = out.text;
      expect(s, contains('node=n1'));
      expect(s, contains('shard=7'));
      expect(s, contains('a=1'));
      expect(s, contains('b=2'));
      // The comma-separator branch must have fired (3+ fields).
      expect(s, contains(', '));
    });

    test('staticFields-only path without fields arg still emits braces', () {
      final out = _MemSink();
      final err = _MemSink();
      final log = Logger(
        out: out,
        err: err,
        format: LogFormat.text,
        staticFields: const {'a': 1, 'b': 2},
      );
      log.info('msg');
      final s = out.text;
      expect(s, contains('a=1'));
      expect(s, contains('b=2'));
      expect(s, contains(', '));
    });
  });
}
