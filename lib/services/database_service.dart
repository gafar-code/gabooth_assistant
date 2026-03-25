import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/printer_settings.dart';
import '../objectbox.g.dart';
import 'logger_service.dart';
import 'printer_settings_repository.dart';

class DatabaseService {
  static Store? _store;
  static Box<PrinterSettings>? _printerSettingsBox;

  static Future<Store> get store async {
    if (_store == null) {
      await _initDatabase();
    }
    return _store!;
  }

  static Box<PrinterSettings> get printerSettingsBox {
    _printerSettingsBox ??= _store!.box<PrinterSettings>();
    return _printerSettingsBox!;
  }

  static Future<void> _initDatabase() async {
    String dbPath;

    if (Platform.isWindows) {
      final userHome =
          Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      if (userHome != null) {
        dbPath = path.join(
          userHome,
          'AppData',
          'Local',
          'gabooth_assistant',
          'objectbox',
        );
      } else {
        final tempDir = await getTemporaryDirectory();
        final localAppData = path.dirname(tempDir.path);
        dbPath = path.join(localAppData, 'gabooth_assistant', 'objectbox');
      }
    } else {
      final appDir = await getApplicationSupportDirectory();
      dbPath = path.join(appDir.path, 'objectbox');
    }

    final dbDir = Directory(dbPath);
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    try {
      _store = Store(getObjectBoxModel(), directory: dbPath);
    } catch (e) {
      if (e.toString().contains('DB\'s last entity ID') ||
          e.toString().contains('failed to create store')) {
        Logger.w(
          '[DB] Schema mismatch detected, recreating database. '
          'Printer settings will be restored from backup.',
        );

        _store?.close();
        _store = null;

        final dir = Directory(dbPath);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }

        _store = Store(getObjectBoxModel(), directory: dbPath);
        await PrinterSettingsRepository.restoreFromBackup();
      } else {
        rethrow;
      }
    }
  }

  static Future<void> close() async {
    _store?.close();
    _store = null;
    _printerSettingsBox = null;
  }
}
