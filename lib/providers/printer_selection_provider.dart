import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../services/logger_service.dart';

/// Holds the selected printer name for each layout type and flipbook frame mode.
/// Replaces DraggableQrSoftFileData's printer-selection fields from gabooth_selfphoto.
class PrinterSelectionState {
  final String? stripPrinter;
  final String? kolasePrinter;
  final String? majalahPrinter;
  final String? flipbookPrinter;
  final String? thermalPrinter;
  final String flipbookFrameMode; // 'f1', 'f2', 'f3'

  const PrinterSelectionState({
    this.stripPrinter,
    this.kolasePrinter,
    this.majalahPrinter,
    this.flipbookPrinter,
    this.thermalPrinter,
    this.flipbookFrameMode = 'f1',
  });

  PrinterSelectionState copyWith({
    String? stripPrinter,
    String? kolasePrinter,
    String? majalahPrinter,
    String? flipbookPrinter,
    String? thermalPrinter,
    String? flipbookFrameMode,
    bool clearStripPrinter = false,
    bool clearKolasePrinter = false,
    bool clearMajalahPrinter = false,
    bool clearFlipbookPrinter = false,
    bool clearThermalPrinter = false,
  }) {
    return PrinterSelectionState(
      stripPrinter: clearStripPrinter ? null : (stripPrinter ?? this.stripPrinter),
      kolasePrinter: clearKolasePrinter ? null : (kolasePrinter ?? this.kolasePrinter),
      majalahPrinter: clearMajalahPrinter ? null : (majalahPrinter ?? this.majalahPrinter),
      flipbookPrinter: clearFlipbookPrinter ? null : (flipbookPrinter ?? this.flipbookPrinter),
      thermalPrinter: clearThermalPrinter ? null : (thermalPrinter ?? this.thermalPrinter),
      flipbookFrameMode: flipbookFrameMode ?? this.flipbookFrameMode,
    );
  }

  Map<String, dynamic> toJson() => {
    'stripPrinter': stripPrinter,
    'kolasePrinter': kolasePrinter,
    'majalahPrinter': majalahPrinter,
    'flipbookPrinter': flipbookPrinter,
    'thermalPrinter': thermalPrinter,
    'flipbookFrameMode': flipbookFrameMode,
  };

  factory PrinterSelectionState.fromJson(Map<String, dynamic> json) {
    return PrinterSelectionState(
      stripPrinter: json['stripPrinter'] as String?,
      kolasePrinter: json['kolasePrinter'] as String?,
      majalahPrinter: json['majalahPrinter'] as String?,
      flipbookPrinter: json['flipbookPrinter'] as String?,
      thermalPrinter: json['thermalPrinter'] as String?,
      flipbookFrameMode: (json['flipbookFrameMode'] as String?) ?? 'f1',
    );
  }
}

class PrinterSelectionNotifier extends AsyncNotifier<PrinterSelectionState> {
  static const String _fileName = 'printer_selection.json';

  static Future<String> _getFilePath() async {
    if (Platform.isWindows) {
      final userHome =
          Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      if (userHome != null) {
        return path.join(
          userHome,
          'AppData',
          'Local',
          'gabooth_assistant',
          _fileName,
        );
      }
    }
    final appDir = await getApplicationSupportDirectory();
    return path.join(appDir.path, _fileName);
  }

  @override
  Future<PrinterSelectionState> build() async {
    try {
      final filePath = await _getFilePath();
      final file = File(filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        return PrinterSelectionState.fromJson(json);
      }
    } catch (e) {
      Logger.w('[PRINTER_SELECTION] Failed to load: $e');
    }
    return const PrinterSelectionState();
  }

  Future<void> _persist(PrinterSelectionState state) async {
    try {
      final filePath = await _getFilePath();
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(state.toJson()));
    } catch (e) {
      Logger.w('[PRINTER_SELECTION] Failed to persist: $e');
    }
  }

  Future<void> updatePrinter(String layoutType, String? printerName) async {
    final current = state.valueOrNull ?? const PrinterSelectionState();
    PrinterSelectionState updated;

    switch (layoutType) {
      case 'strip':
        updated = printerName == null
            ? current.copyWith(clearStripPrinter: true)
            : current.copyWith(stripPrinter: printerName);
        break;
      case 'kolase':
        updated = printerName == null
            ? current.copyWith(clearKolasePrinter: true)
            : current.copyWith(kolasePrinter: printerName);
        break;
      case 'majalah':
        updated = printerName == null
            ? current.copyWith(clearMajalahPrinter: true)
            : current.copyWith(majalahPrinter: printerName);
        break;
      case 'flipbook':
        updated = printerName == null
            ? current.copyWith(clearFlipbookPrinter: true)
            : current.copyWith(flipbookPrinter: printerName);
        break;
      case 'thermal':
        updated = printerName == null
            ? current.copyWith(clearThermalPrinter: true)
            : current.copyWith(thermalPrinter: printerName);
        break;
      default:
        return;
    }

    state = AsyncData(updated);
    await _persist(updated);
  }

  Future<void> updateFlipbookFrameMode(String frameMode) async {
    final current = state.valueOrNull ?? const PrinterSelectionState();
    final updated = current.copyWith(flipbookFrameMode: frameMode);
    state = AsyncData(updated);
    await _persist(updated);
  }

  String? getPrinterForLayout(String layoutType) {
    final s = state.valueOrNull;
    if (s == null) return null;
    switch (layoutType) {
      case 'strip': return s.stripPrinter;
      case 'kolase': return s.kolasePrinter;
      case 'majalah': return s.majalahPrinter;
      case 'flipbook': return s.flipbookPrinter;
      case 'thermal': return s.thermalPrinter;
      default: return null;
    }
  }
}

final printerSelectionProvider =
    AsyncNotifierProvider<PrinterSelectionNotifier, PrinterSelectionState>(
  PrinterSelectionNotifier.new,
);
