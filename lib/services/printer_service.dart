import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:print_windows/print_windows.dart' as print_win;
import '../models/printer_device.dart';
import 'logger_service.dart';

/// Tipis: pembungkus `print_windows` yang meneruskan paper size dari client
/// langsung ke driver via DEVMODE. Tidak ada lagi kalibrasi/manipulasi —
/// gabooth_assistant murni sebagai jembatan antara client dan printer.
class PrinterService {
  static PrinterService? _instance;

  PrinterService._();

  static PrinterService get instance {
    _instance ??= PrinterService._();
    return _instance!;
  }

  static final print_win.PrintWindows _printWindows = print_win.PrintWindows();

  Future<List<PrinterDevice>> getAvailablePrinters() async {
    try {
      final printers = await _printWindows.listPrinters();
      final defaultName = await _printWindows.getDefaultPrinter();
      return printers
          .map(
            (p) => PrinterDevice(
              printerName: p.name,
              description: 'System Printer',
              isDefault: p.isDefault || p.name == defaultName,
              isOnline: true,
              printerType: _determinePrinterType(p.name),
            ),
          )
          .toList(growable: false);
    } catch (e, st) {
      Logger.w('[PRINTER] listPrinters failed', e, st);
      return const [];
    }
  }

  String _determinePrinterType(String printerName) {
    final name = printerName.toLowerCase();
    if (name.contains('pdf')) return 'PDF';
    if (name.contains('laser')) return 'LaserJet';
    if (name.contains('inkjet') || name.contains('ink')) return 'Inkjet';
    if (name.contains('dot') && name.contains('matrix')) return 'Dot Matrix';
    if (name.contains('thermal')) return 'Thermal';
    if (name.contains('photo')) return 'Photo';
    return 'Unknown';
  }

  Future<bool> isPrinterAvailable(
    String printerName, {
    int timeoutMs = 5000,
  }) async {
    if (printerName.isEmpty) return false;
    try {
      return await _printWindows.isPrinterAvailable(
        printerName,
        timeoutMs: timeoutMs,
      );
    } catch (e) {
      Logger.w('[PRINTER] Error checking printer: $e');
      return false;
    }
  }

  /// Cetak PDF [documentData] ke [printerName]. [paperWidthMm]/[paperHeightMm]
  /// (>0) override DEVMODE printer untuk job ini sehingga driver memakai
  /// kertas tepat sesuai permintaan client. 0 = pakai default printer.
  ///
  /// Parameter kalibrasi ([targetWidthMm], [targetHeightMm], [offsetXMm],
  /// [offsetYMm], [scalePercent]) diteruskan ke `print_windows` agar driver
  /// melakukan fit/offset/scale terhadap area cetak. Nilai 0/100 (default)
  /// = no-op, sehingga klien yang tidak mengirimnya tetap kompatibel.
  Future<bool> printDocument({
    required String printerName,
    required Uint8List documentData,
    required double paperWidthMm,
    required double paperHeightMm,
    String? jobName,
    int copies = 1,
    double targetWidthMm = 0.0,
    double targetHeightMm = 0.0,
    double offsetXMm = 0.0,
    double offsetYMm = 0.0,
    double scalePercent = 100.0,
    int timeoutMs = 30000,
  }) async {
    try {
      if (printerName.isEmpty) return false;
      if (documentData.isEmpty) return false;
      if (copies < 1) return false;

      if (!await isPrinterAvailable(printerName)) return false;

      final settings = print_win.PrintSettings.fromBytes(
        pdfData: documentData,
        printerName: printerName,
        copies: copies,
        jobName: jobName ?? 'Gabooth Print Job',
        fitToPage: true,
        paperWidthMm: paperWidthMm,
        paperHeightMm: paperHeightMm,
        targetWidthMm: targetWidthMm,
        targetHeightMm: targetHeightMm,
        offsetXMm: offsetXMm,
        offsetYMm: offsetYMm,
        scalePercent: scalePercent <= 0 ? 100.0 : scalePercent,
      );

      final result = await _printWindows.printPDFAsync(
        settings,
        timeoutMs: timeoutMs,
      );

      final success = result['success'] == true;
      if (!success) {
        Logger.w('[PRINTER] Failed to queue print job: ${result['message']}');
      }
      return success;
    } catch (e, stackTrace) {
      Logger.e('[PRINTER] Print error', e, stackTrace);
      return false;
    }
  }

  Future<bool> cancelPendingPrints() async {
    try {
      return await _printWindows.cancelPrint();
    } catch (e) {
      Logger.w('[PRINTER] Error cancelling prints: $e');
      return false;
    }
  }
}
