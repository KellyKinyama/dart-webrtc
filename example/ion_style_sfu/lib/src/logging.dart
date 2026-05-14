// Phase 27 — minimal structured logger.
//
// We deliberately keep this tiny so production deployments can plug
// it into their existing observability stack (pipe JSON to a log
// shipper) without forcing a heavy logging dependency on the rest of
// the codebase.
//
// Two output modes:
//   * `text` (default) — human-friendly single-line records, matching
//     the pre-Phase-27 stdout/stderr style.
//   * `json` — one JSON object per record with stable keys: `ts`,
//     `level`, `msg`, plus any structured `fields` flattened in.
//
// Levels are numerically ordered so callers can drop low-importance
// records via [Logger.level].

import 'dart:convert';
import 'dart:io';

enum LogLevel {
  debug,
  info,
  warn,
  error,
}

/// Output format for [Logger.write].
enum LogFormat { text, json }

/// Tiny structured logger. Safe to share across isolates *only* by
/// re-creating one per isolate (the `IOSink`s are not sendable).
class Logger {
  /// Records below this level are dropped. Defaults to [LogLevel.info].
  LogLevel level;

  final LogFormat format;
  final IOSink _outSink;
  final IOSink _errSink;

  /// Static fields appended to every record (e.g. `node: <id>`).
  final Map<String, Object?> staticFields;

  Logger({
    this.level = LogLevel.info,
    this.format = LogFormat.text,
    IOSink? out,
    IOSink? err,
    Map<String, Object?>? staticFields,
  })  : _outSink = out ?? stdout,
        _errSink = err ?? stderr,
        staticFields = staticFields ?? const {};

  /// A logger that drops every record. Useful in tests and when the
  /// caller passes `quiet: true`.
  factory Logger.silent() => Logger(level: LogLevel.error, out: _Null(), err: _Null());

  void debug(String msg, [Map<String, Object?>? fields]) =>
      _emit(LogLevel.debug, msg, fields);
  void info(String msg, [Map<String, Object?>? fields]) =>
      _emit(LogLevel.info, msg, fields);
  void warn(String msg, [Map<String, Object?>? fields]) =>
      _emit(LogLevel.warn, msg, fields);
  void error(String msg, [Map<String, Object?>? fields]) =>
      _emit(LogLevel.error, msg, fields);

  void _emit(LogLevel lvl, String msg, Map<String, Object?>? fields) {
    if (lvl.index < level.index) return;
    final sink = lvl.index >= LogLevel.warn.index ? _errSink : _outSink;
    final ts = DateTime.now().toUtc().toIso8601String();
    if (format == LogFormat.json) {
      final rec = <String, Object?>{
        'ts': ts,
        'level': lvl.name,
        'msg': msg,
        ...staticFields,
        if (fields != null) ...fields,
      };
      sink.writeln(jsonEncode(rec));
    } else {
      final buf = StringBuffer()
        ..write(ts)
        ..write(' ')
        ..write(lvl.name.toUpperCase().padRight(5))
        ..write(' ')
        ..write(msg);
      if (staticFields.isNotEmpty || (fields != null && fields.isNotEmpty)) {
        buf.write(' {');
        var first = true;
        void writeField(String k, Object? v) {
          if (!first) buf.write(', ');
          buf
            ..write(k)
            ..write('=')
            ..write(v);
          first = false;
        }

        staticFields.forEach(writeField);
        fields?.forEach(writeField);
        buf.write('}');
      }
      sink.writeln(buf.toString());
    }
  }
}

/// IOSink that swallows everything. We need our own because
/// `IOSink` constructors require an underlying StreamConsumer; this
/// shortcut lets [Logger.silent] avoid touching stdio at all.
class _Null implements IOSink {
  @override
  Encoding encoding = utf8;
  @override
  void add(List<int> data) {}
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
  void write(Object? object) {}
  @override
  void writeAll(Iterable objects, [String separator = '']) {}
  @override
  void writeCharCode(int charCode) {}
  @override
  void writeln([Object? object = '']) {}
}
