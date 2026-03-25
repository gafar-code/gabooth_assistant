import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/printer_settings.dart';
import '../objectbox.g.dart';
import 'database_service.dart';
import 'logger_service.dart';

/// Repository for managing printer settings in ObjectBox
class PrinterSettingsRepository {
  static final PrinterSettingsRepository _instance =
      PrinterSettingsRepository._internal();
  factory PrinterSettingsRepository() => _instance;
  PrinterSettingsRepository._internal();

  static const String defaultSettingsKey = 'default';
  static const String _backupFileName = 'printer_settings_backup.json';

  Box<PrinterSettings> get _box => DatabaseService.printerSettingsBox;

  /// Get the default printer settings (or create if not exists)
  Future<PrinterSettings> getDefaultSettings() async {
    final query = _box
        .query(PrinterSettings_.key.equals(defaultSettingsKey))
        .build();

    try {
      var settings = query.findFirst();

      if (settings == null) {
        settings = PrinterSettings(
          key: defaultSettingsKey,
          targetWidthMm: 0.0,
          targetHeightMm: 0.0,
          offsetXMm: 0.0,
          offsetYMm: 0.0,
        );
        _box.put(settings);
      }

      return settings;
    } finally {
      query.close();
    }
  }

  /// Save or update printer settings
  Future<PrinterSettings> saveSettings(PrinterSettings settings) async {
    settings.updatedAt = DateTime.now();
    _box.put(settings);
    await _backupAllToFile();
    return settings;
  }

  /// Update specific fields of the default settings
  Future<PrinterSettings> updateDefaultSettings({
    double? targetWidthMm,
    double? targetHeightMm,
    double? offsetXMm,
    double? offsetYMm,
  }) async {
    final currentSettings = await getDefaultSettings();

    final updatedSettings = currentSettings.copyWith(
      targetWidthMm: targetWidthMm,
      targetHeightMm: targetHeightMm,
      offsetXMm: offsetXMm,
      offsetYMm: offsetYMm,
      updatedAt: DateTime.now(),
    );

    return await saveSettings(updatedSettings);
  }

  /// Reset settings to defaults (all zeros)
  Future<PrinterSettings> resetToDefaults() async {
    final settings = PrinterSettings(
      key: defaultSettingsKey,
      targetWidthMm: 0.0,
      targetHeightMm: 0.0,
      offsetXMm: 0.0,
      offsetYMm: 0.0,
    );

    return await saveSettings(settings);
  }

  /// Get settings by custom key
  Future<PrinterSettings?> getSettingsByKey(String key) async {
    final query = _box.query(PrinterSettings_.key.equals(key)).build();

    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  /// Get all printer settings
  Future<List<PrinterSettings>> getAllSettings() async {
    return _box.getAll();
  }

  /// Delete settings by key
  Future<bool> deleteSettings(String key) async {
    final query = _box.query(PrinterSettings_.key.equals(key)).build();

    try {
      final settings = query.findFirst();
      if (settings != null) {
        _box.remove(settings.id);
        await _backupAllToFile();
        return true;
      }
      return false;
    } finally {
      query.close();
    }
  }

  /// Generate simplified settings key based on printer type only.
  /// Example: 'printer_kolase', 'printer_majalah'
  static String generateKey({required String printerType}) {
    return 'printer_$printerType';
  }

  /// Get settings for a printer type.
  ///
  /// Tries new key `printer_{type}` first.
  /// If not found, searches for any old key starting with `printer_{type}_`
  /// and copies the first match to the new key (one-time migration).
  Future<PrinterSettings?> getSettingsByType(String printerType) async {
    final newKey = generateKey(printerType: printerType);

    var settings = await getSettingsByKey(newKey);
    if (settings != null) return settings;

    final allSettings = await getAllSettings();
    final prefix = 'printer_${printerType}_';
    final oldSettings = allSettings
        .where((s) => s.key.startsWith(prefix))
        .toList();

    if (oldSettings.isNotEmpty) {
      final source = oldSettings.first;
      final migrated = PrinterSettings(
        key: newKey,
        targetWidthMm: source.targetWidthMm,
        targetHeightMm: source.targetHeightMm,
        offsetXMm: source.offsetXMm,
        offsetYMm: source.offsetYMm,
        scalePercent: source.scalePercent,
      );
      return await saveSettings(migrated);
    }

    return null;
  }

  /// Save settings for a printer type using simplified key.
  Future<PrinterSettings> saveSettingsByType({
    required String printerType,
    required double targetWidthMm,
    required double targetHeightMm,
    required double offsetXMm,
    required double offsetYMm,
    double scalePercent = 100.0,
  }) async {
    final key = generateKey(printerType: printerType);

    var settings = await getSettingsByKey(key);

    if (settings != null) {
      settings.targetWidthMm = targetWidthMm;
      settings.targetHeightMm = targetHeightMm;
      settings.offsetXMm = offsetXMm;
      settings.offsetYMm = offsetYMm;
      settings.scalePercent = scalePercent;
      settings.updatedAt = DateTime.now();
    } else {
      settings = PrinterSettings(
        key: key,
        targetWidthMm: targetWidthMm,
        targetHeightMm: targetHeightMm,
        offsetXMm: offsetXMm,
        offsetYMm: offsetYMm,
        scalePercent: scalePercent,
      );
    }

    return await saveSettings(settings);
  }

  // ─── Backup / Restore ───

  static Future<String> _getBackupFilePath() async {
    if (Platform.isWindows) {
      final userHome =
          Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      if (userHome != null) {
        return path.join(
          userHome,
          'AppData',
          'Local',
          'gabooth_assistant',
          _backupFileName,
        );
      }
    }
    final appDir = await getApplicationSupportDirectory();
    return path.join(appDir.path, _backupFileName);
  }

  Future<void> _backupAllToFile() async {
    try {
      final allSettings = _box.getAll();
      if (allSettings.isEmpty) return;

      final backupPath = await _getBackupFilePath();
      final backupData = allSettings
          .map(
            (s) => {
              'key': s.key,
              'targetWidthMm': s.targetWidthMm,
              'targetHeightMm': s.targetHeightMm,
              'offsetXMm': s.offsetXMm,
              'offsetYMm': s.offsetYMm,
              'scalePercent': s.scalePercent,
              'createdAt': s.createdAt.toIso8601String(),
              'updatedAt': s.updatedAt.toIso8601String(),
            },
          )
          .toList();

      final file = File(backupPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(backupData));
    } catch (e) {
      Logger.w('[PRINTER] Failed to backup printer settings: $e');
    }
  }

  static Future<void> restoreFromBackup() async {
    try {
      final backupPath = await _getBackupFilePath();
      final file = File(backupPath);
      if (!await file.exists()) return;

      final content = await file.readAsString();
      final List<dynamic> backupData = jsonDecode(content);
      if (backupData.isEmpty) return;

      final box = DatabaseService.printerSettingsBox;
      for (final item in backupData) {
        final settings = PrinterSettings(
          key: item['key'] as String,
          targetWidthMm: (item['targetWidthMm'] as num).toDouble(),
          targetHeightMm: (item['targetHeightMm'] as num).toDouble(),
          offsetXMm: (item['offsetXMm'] as num).toDouble(),
          offsetYMm: (item['offsetYMm'] as num).toDouble(),
          scalePercent: (item['scalePercent'] as num?)?.toDouble() ?? 100.0,
          createdAt:
              DateTime.tryParse(item['createdAt'] ?? '') ?? DateTime.now(),
          updatedAt:
              DateTime.tryParse(item['updatedAt'] ?? '') ?? DateTime.now(),
        );
        box.put(settings);
      }
    } catch (e) {
      Logger.e('[PRINTER] Failed to restore printer settings from backup', e);
    }
  }
}
