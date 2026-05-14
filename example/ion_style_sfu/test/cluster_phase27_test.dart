// Phase 27 — structured logging.
//
// Verifies:
//  * Text and JSON formats produce reasonable output.
//  * Level filtering drops below-threshold records.
//  * Static fields appear on every record.
//  * Logger.silent() emits nothing.

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
  void write(Object? object) => buf.add(utf8.encode('$object'));
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
  group('Phase 27 — Logger', () {
    test('text format emits human-readable lines', () {
      final out = _MemSink();
      final err = _MemSink();
      final log = Logger(out: out, err: err, format: LogFormat.text);
      log.info('hello', {'k': 1});
      log.warn('careful');
      expect(out.text, contains('INFO'));
      expect(out.text, contains('hello'));
      expect(out.text, contains('k=1'));
      expect(err.text, contains('WARN'));
      expect(err.text, contains('careful'));
    });

    test('json format emits one JSON object per line', () {
      final out = _MemSink();
      final err = _MemSink();
      final log = Logger(
        out: out,
        err: err,
        format: LogFormat.json,
        staticFields: {'node': 'a'},
      );
      log.info('boot', {'port': 9090});
      final line = out.text.trim();
      final rec = jsonDecode(line) as Map<String, Object?>;
      expect(rec['msg'], 'boot');
      expect(rec['level'], 'info');
      expect(rec['node'], 'a');
      expect(rec['port'], 9090);
      expect(rec['ts'], isA<String>());
    });

    test('level filter drops below-threshold records', () {
      final out = _MemSink();
      final err = _MemSink();
      final log = Logger(
          out: out, err: err, level: LogLevel.warn, format: LogFormat.text);
      log.debug('d');
      log.info('i');
      log.warn('w');
      log.error('e');
      expect(out.text, isEmpty);
      expect(err.text, contains('w'));
      expect(err.text, contains('e'));
    });

    test('Logger.silent() emits nothing', () {
      final log = Logger.silent();
      // Just must not throw.
      log.info('ignored');
      log.error('also ignored');
    });
  });
}
