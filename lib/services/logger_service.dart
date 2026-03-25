import 'dart:developer' as developer;
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

bool isSilent = false;

class Logger {
  Logger._();

  static const String _reset = '\x1B[0m';
  static const String _red = '\x1B[31m';
  static const String _green = '\x1B[32m';
  static const String _yellow = '\x1B[33m';
  // ignore: unused_field
  static const String _blue = '\x1B[34m';
  static const String _magenta = '\x1B[35m';
  static const String _cyan = '\x1B[36m';

  static File? _logFile;
  static String? _logDirectoryPath;
  static final _fileWriteQueue = <String>[];
  static bool _isWritingToFile = false;
  static Timer? _flushTimer;

  static const int _maxLogLines = 1000;
  static int _currentFileIndex = 1;
  static String? _currentDateStr;

  static const int _maxStackFrames = 15;

  static void d(String message, [Object? error, StackTrace? stackTrace]) {
    if (isSilent) return;
    _log('DEBUG', message, _cyan, error, stackTrace);
  }

  static void i(String message, [Object? error, StackTrace? stackTrace]) {
    if (isSilent) return;
    _log('INFO', message, _green, error, stackTrace);
  }

  static void w(String message, [Object? error, StackTrace? stackTrace]) {
    if (isSilent) return;
    _log('WARN', message, _yellow, error, stackTrace);
  }

  static void e(String message, [Object? error, StackTrace? stackTrace]) {
    if (isSilent) return;
    _log('ERROR', message, _red, error, stackTrace);
  }

  static void t(String message, [Object? error, StackTrace? stackTrace]) {
    if (isSilent) return;
    _log('TRACE', message, _magenta, error, stackTrace);
  }

  static Future<T> time<T>(String label, Future<T> Function() callback) async {
    if (isSilent) return callback();
    final stopwatch = Stopwatch()..start();
    try {
      final result = await callback();
      stopwatch.stop();
      d('⏱️ $label: ${stopwatch.elapsedMilliseconds}ms');
      return result;
    } catch (error, stackTrace) {
      stopwatch.stop();
      e('⏱️ $label failed after ${stopwatch.elapsedMilliseconds}ms', error, stackTrace);
      rethrow;
    }
  }

  static void shutdown() {
    if (isSilent) return;
    i('🔄 Logger shutting down, flushing pending logs...');
    _cleanupFileLogging();
  }

  static String? get logDirectoryPath => _logDirectoryPath;
  static String? get currentLogFilePath => _logFile?.path;

  static Future<void> _initializeFileLogging() async {
    if (isSilent || _logDirectoryPath != null) return;

    try {
      String basePath;
      if (Platform.isWindows) {
        final appData = Platform.environment['APPDATA'];
        if (appData != null) {
          basePath = '$appData${Platform.pathSeparator}GaboothAssistant';
        } else {
          final supportDir = await getApplicationSupportDirectory();
          basePath = supportDir.path;
        }
      } else {
        final supportDir = await getApplicationSupportDirectory();
        basePath = supportDir.path;
      }

      _logDirectoryPath = '$basePath${Platform.pathSeparator}logs';
      final logDir = Directory(_logDirectoryPath!);
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      final now = DateTime.now();
      _currentDateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      _currentFileIndex = await _findLatestRotationIndex(_currentDateStr!);
      await _createLogFile();

      _flushTimer?.cancel();
      _flushTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _flushLogQueue(),
      );
    } catch (e) {
      developer.log('Failed to initialize file logging: $e', name: 'Logger');
    }
  }

  static Future<int> _findLatestRotationIndex(String dateStr) async {
    if (_logDirectoryPath == null) return 1;
    try {
      final logDir = Directory(_logDirectoryPath!);
      if (!await logDir.exists()) return 1;

      final pattern = RegExp(r'gabooth_' + dateStr + r'_(\d{3})\.log$');
      int maxIndex = 0;

      await for (final entity in logDir.list()) {
        if (entity is File) {
          final fileName = entity.path.split(Platform.pathSeparator).last;
          final match = pattern.firstMatch(fileName);
          if (match != null) {
            final index = int.parse(match.group(1)!);
            if (index > maxIndex) maxIndex = index;
          }
        }
      }

      if (maxIndex == 0) return 1;

      final latestFile = File(
        '${_logDirectoryPath!}${Platform.pathSeparator}gabooth_${dateStr}_${maxIndex.toString().padLeft(3, '0')}.log',
      );

      if (await latestFile.exists()) {
        final lineCount = await _countLinesInFile(latestFile);
        if (lineCount < _maxLogLines) return maxIndex;
        return maxIndex + 1;
      }

      return maxIndex;
    } catch (e) {
      return 1;
    }
  }

  static Future<void> _createLogFile() async {
    if (_logDirectoryPath == null || _currentDateStr == null) return;
    final indexStr = _currentFileIndex.toString().padLeft(3, '0');
    final logFileName = 'gabooth_${_currentDateStr}_$indexStr.log';
    _logFile = File('${_logDirectoryPath!}${Platform.pathSeparator}$logFileName');
  }

  static Future<void> _rotateLogFile() async {
    _currentFileIndex++;
    await _createLogFile();
  }

  static Future<int> _countLinesInFile(File file) async {
    try {
      if (!await file.exists()) return 0;
      final lines = await file.readAsLines();
      return lines.length;
    } catch (e) {
      return 0;
    }
  }

  static Future<int> _countLogLines() async {
    if (_logFile == null || !await _logFile!.exists()) return 0;
    try {
      final lines = await _logFile!.readAsLines();
      return lines.length;
    } catch (e) {
      return 0;
    }
  }

  static void _writeToFile(String logEntry) {
    if (isSilent || _logFile == null) return;
    _fileWriteQueue.add(logEntry);
    if (_fileWriteQueue.length > 100) _flushLogQueue();
  }

  static void _flushLogQueue() async {
    if (isSilent || _isWritingToFile || _fileWriteQueue.isEmpty || _logFile == null) return;

    _isWritingToFile = true;
    final entriesToWrite = List<String>.from(_fileWriteQueue);
    _fileWriteQueue.clear();

    try {
      final now = DateTime.now();
      final todayStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      if (_currentDateStr != todayStr) {
        _currentDateStr = todayStr;
        _currentFileIndex = 1;
        await _createLogFile();
      }

      final currentLines = await _countLogLines();
      if (currentLines >= _maxLogLines) await _rotateLogFile();

      final logContent = '${entriesToWrite.join('\n')}\n';
      await _logFile!.writeAsString(logContent, mode: FileMode.append, flush: true);
    } catch (e) {
      developer.log('Failed to write to log file: $e', name: 'Logger');
    } finally {
      _isWritingToFile = false;
    }
  }

  static void _cleanupFileLogging() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_fileWriteQueue.isNotEmpty) _flushLogQueue();
  }

  static void _log(
    String level,
    String message,
    String color,
    Object? error,
    StackTrace? stackTrace,
  ) {
    if (isSilent) return;

    final now = DateTime.now();
    final timestamp = now.toIso8601String().substring(11, 23);
    final prefix = '$color[$level]$_reset';
    final formattedMessage = '$prefix $timestamp | $message';

    developer.log(
      message,
      time: now,
      level: _getLevelValue(level),
      name: 'Logger',
      error: error,
      stackTrace: stackTrace,
    );

    // ignore: avoid_print
    print(formattedMessage);

    if (error != null) {
      // ignore: avoid_print
      print('$_red   Error: $error$_reset');
    }

    if (stackTrace != null && level == 'ERROR') {
      final limitedStack = _limitStackTrace(stackTrace);
      // ignore: avoid_print
      print('$_red   Stack trace:\n$limitedStack$_reset');
    }

    _logToFile(level, message, now, error, stackTrace);
  }

  static void _logToFile(
    String level,
    String message,
    DateTime timestamp,
    Object? error,
    StackTrace? stackTrace,
  ) {
    if (isSilent) return;

    if (_logDirectoryPath == null) _initializeFileLogging();

    final dateStr = timestamp.toIso8601String();
    final timeStr = dateStr.substring(11, 23);
    final fullDateStr = dateStr.substring(0, 10);

    final buffer = StringBuffer();
    buffer.write('[$level] $fullDateStr $timeStr | $message');

    if (error != null) buffer.write('\n   Error: $error');

    if (stackTrace != null && level == 'ERROR') {
      final limitedStack = _limitStackTrace(stackTrace);
      buffer.write('\n   Stack trace:\n$limitedStack');
    }

    _writeToFile(buffer.toString());
  }

  static String _limitStackTrace(StackTrace stackTrace) {
    final lines = stackTrace.toString().split('\n');
    if (lines.length <= _maxStackFrames) return stackTrace.toString();
    final limitedLines = lines.take(_maxStackFrames).toList();
    final omitted = lines.length - _maxStackFrames;
    limitedLines.add('... ($omitted more frames omitted)');
    return limitedLines.join('\n');
  }

  static int _getLevelValue(String level) {
    switch (level) {
      case 'TRACE': return 300;
      case 'DEBUG': return 500;
      case 'INFO': return 800;
      case 'WARN': return 900;
      case 'ERROR': return 1000;
      default: return 0;
    }
  }
}

extension LoggerExtension on Object? {
  void log([String? label]) {
    if (isSilent) return;
  }

  T logAndReturn<T>(String label) {
    if (kDebugMode) {}
    return this as T;
  }
}
