import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/printer_calibration.dart';
import 'logger_service.dart';

/// Singleton repository for per-printer calibration values.
///
/// Stores all entries as one JSON blob under [_prefsKey] so multi-byte /
/// spaced printer names don't need key-escaping. Holds an in-memory cache
/// so the HTTP `/print` handler can read calibration synchronously without
/// awaiting disk I/O on every job.
class PrinterCalibrationRepository {
  PrinterCalibrationRepository._();
  static final PrinterCalibrationRepository instance =
      PrinterCalibrationRepository._();

  static const String _prefsKey = 'printer_calibrations_v1';

  final Map<String, PrinterCalibration> _cache = {};
  bool _loaded = false;
  Future<void>? _loadingFuture;

  /// Idempotently load the persisted calibrations into the in-memory cache.
  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loadingFuture ??= _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _cache.clear();
          decoded.forEach((name, value) {
            if (value is Map<String, dynamic>) {
              _cache[name] = PrinterCalibration.fromJson(value);
            }
          });
        }
      }
    } catch (e, st) {
      Logger.w('[CAL] Failed to load calibrations, starting empty', e, st);
      _cache.clear();
    } finally {
      _loaded = true;
      _loadingFuture = null;
    }
  }

  /// Synchronous cache-only lookup. Returns [PrinterCalibration.zero] when
  /// no entry exists for [printerName] or when the cache hasn't been loaded
  /// yet — both equivalent to "no calibration applied".
  PrinterCalibration getSync(String printerName) {
    return _cache[printerName] ?? const PrinterCalibration.zero();
  }

  Future<PrinterCalibration?> get(String printerName) async {
    await ensureLoaded();
    return _cache[printerName];
  }

  Future<void> save(String printerName, PrinterCalibration cal) async {
    await ensureLoaded();
    _cache[printerName] = cal;
    await _persist();
  }

  Future<void> delete(String printerName) async {
    await ensureLoaded();
    if (_cache.remove(printerName) != null) {
      await _persist();
    }
  }

  /// Unmodifiable copy of the current cache.
  Map<String, PrinterCalibration> snapshot() =>
      Map.unmodifiable(Map.of(_cache));

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = <String, dynamic>{
        for (final e in _cache.entries) e.key: e.value.toJson(),
      };
      await prefs.setString(_prefsKey, jsonEncode(json));
    } catch (e, st) {
      Logger.e('[CAL] Failed to persist calibrations', e, st);
    }
  }
}
