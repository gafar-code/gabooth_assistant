import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:print_windows/print_windows.dart' as print_win;
import '../models/printer_device.dart';
import '../models/paper_size.dart';
import '../models/printer_settings.dart';
import 'printer_settings_repository.dart';
import 'logger_service.dart';

class PrinterService {
  static PrinterService? _instance;

  PrinterService._();

  static PrinterService get instance {
    _instance ??= PrinterService._();
    return _instance!;
  }

  /// Get list of available printers on the system
  Future<List<PrinterDevice>> getAvailablePrinters() async {
    try {
      final printers = <PrinterDevice>[];

      await Printing.listPrinters().then((systemPrinters) {
        for (final printer in systemPrinters) {
          final printerDevice = PrinterDevice(
            printerName: printer.name,
            description: printer.location ?? 'System Printer',
            isDefault: printer.isDefault,
            isOnline: !printer.isAvailable ? false : true,
            printerType: _determinePrinterType(printer.name),
          );
          printers.add(printerDevice);
        }
      });

      return printers;
    } catch (e) {
      return [];
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

  /// Check if a specific printer is available
  Future<bool> isPrinterAvailable(
    String printerName, {
    int timeoutMs = 5000,
  }) async {
    try {
      final isAvailable = await isPrinterAvailableWithTimeout(
        printerName,
        timeoutMs: timeoutMs,
      );
      if (isAvailable) return true;

      final printers = await Printing.listPrinters();
      return printers.any(
        (printer) => printer.name == printerName && printer.isAvailable,
      );
    } catch (e) {
      Logger.w('[PRINTER] Error checking printer: $e');
      return false;
    }
  }

  /// Get default printer from system
  Future<PrinterDevice?> getDefaultPrinter() async {
    try {
      final printers = await getAvailablePrinters();
      return printers.where((p) => p.isDefault).firstOrNull;
    } catch (e) {
      return null;
    }
  }

  /// Print a document using the specified printer
  Future<bool> printDocument({
    required String printerName,
    required Uint8List documentData,
    String? jobName,
    int copies = 1,
    PrinterSettings? printerSettings,
    String? printerType,
  }) async {
    try {
      if (printerName.isEmpty) return false;
      if (documentData.isEmpty) return false;
      if (copies < 1) return false;

      if (!await isPrinterAvailable(printerName)) return false;

      PrinterSettings settings;
      if (printerSettings != null) {
        settings = printerSettings;
      } else {
        PrinterSettings? loadedSettings;
        final settingsRepo = PrinterSettingsRepository();

        if (printerType != null) {
          loadedSettings = await settingsRepo.getSettingsByType(printerType);
        }

        if (loadedSettings != null) {
          settings = loadedSettings;
        } else {
          settings = await settingsRepo.getDefaultSettings();
          Logger.w('[PRINTER] Using DEFAULT settings (all zeros - original size)');
        }
      }

      return await _printWithPrintWindows(
        printerName: printerName,
        documentData: documentData,
        jobName: jobName,
        copies: copies,
        printerSettings: settings,
      );
    } catch (e) {
      return false;
    }
  }

  Future<bool> _printWithPrintWindows({
    required String printerName,
    required Uint8List documentData,
    String? jobName,
    int copies = 1,
    required PrinterSettings printerSettings,
    int timeoutMs = 30000,
  }) async {
    try {
      final printWindows = print_win.PrintWindows();

      final scalePercent = printerSettings.scalePercent > 0.0
          ? printerSettings.scalePercent
          : 100.0;

      final settings = print_win.PrintSettings.fromBytes(
        pdfData: documentData,
        printerName: printerName,
        copies: copies,
        jobName: jobName ?? 'Gabooth Print Job',
        fitToPage: true,
        targetWidthMm: printerSettings.targetWidthMm,
        targetHeightMm: printerSettings.targetHeightMm,
        offsetXMm: printerSettings.offsetXMm,
        offsetYMm: printerSettings.offsetYMm,
        scalePercent: scalePercent,
      );

      final result = await printWindows.printPDFAsync(
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

  Future<bool> isPrinterAvailableWithTimeout(
    String printerName, {
    int timeoutMs = 5000,
  }) async {
    try {
      final printWindows = print_win.PrintWindows();
      return await printWindows.isPrinterAvailable(
        printerName,
        timeoutMs: timeoutMs,
      );
    } catch (e) {
      Logger.w('[PRINTER] Error checking printer availability: $e');
      return false;
    }
  }

  Future<bool> cancelPendingPrints() async {
    try {
      final printWindows = print_win.PrintWindows();
      return await printWindows.cancelPrint();
    } catch (e) {
      Logger.w('[PRINTER] Error cancelling prints: $e');
      return false;
    }
  }

  static Future<void> showPrintPreview({
    required Uint8List documentData,
    String? jobName,
  }) async {
    await Printing.layoutPdf(
      onLayout: (_) => documentData,
      name: jobName ?? 'Gabooth Preview',
    );
  }

  Future<bool> printTestPage({
    required String printerName,
    String? printerType,
  }) async {
    try {
      final paperSize = PaperSize.size4R;
      final pdf = await _generateTestPage(printerName, paperSize);

      return await printDocument(
        printerName: printerName,
        documentData: pdf,
        jobName: 'Gabooth Test Print',
        printerType: printerType,
      );
    } catch (e) {
      return false;
    }
  }

  Future<Uint8List> _generateTestPage(
    String printerName,
    PaperSize paperSize,
  ) async {
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: paperSize.pdfPageFormat,
        build: (pw.Context context) {
          return pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 2),
            ),
            padding: const pw.EdgeInsets.all(16),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  'GABOOTH TEST PRINT',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  'Printer: $printerName',
                  style: const pw.TextStyle(fontSize: 14),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  'Type: ${paperSize.displayName} Print',
                  style: const pw.TextStyle(fontSize: 14),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  'Format: ${paperSize.dimensionsString}',
                  style: const pw.TextStyle(fontSize: 14),
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  'Date: ${DateTime.now().toString().split('.')[0]}',
                  style: const pw.TextStyle(fontSize: 12),
                ),
                pw.SizedBox(height: 30),
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(border: pw.Border.all(width: 2)),
                  child: pw.Text(
                    '${paperSize.displayName} Photo Test\n${paperSize.dimensionsString}',
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 12),
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  'If you can read this clearly,\nyour printer is working correctly!',
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
          );
        },
      ),
    );

    return await doc.save();
  }

  Future<bool> printDocumentWithPrinterType({
    required String printerName,
    required Uint8List documentData,
    required String printerType,
    String? jobName,
    int copies = 1,
    PrinterSettings? printerSettings,
  }) async {
    try {
      if (!await isPrinterAvailable(printerName)) return false;

      return await printDocument(
        printerName: printerName,
        documentData: documentData,
        jobName: jobName ?? 'Gabooth Print Job',
        copies: copies,
        printerSettings: printerSettings,
        printerType: printerType,
      );
    } catch (e) {
      return false;
    }
  }

  static PaperSize getRecommendedPaperSize(
    double widthInches,
    double heightInches,
  ) {
    final aspectRatio = widthInches / heightInches;

    PaperSize? bestMatch;
    double closestRatioDiff = double.infinity;

    for (final paperSize in PaperSize.availableSizes) {
      final ratioDiff = (paperSize.aspectRatio - aspectRatio).abs();
      if (ratioDiff < closestRatioDiff) {
        closestRatioDiff = ratioDiff;
        bestMatch = paperSize;
      }
    }

    return bestMatch ?? PaperSize.defaultSize;
  }

  static List<PaperSize> getAvailablePaperSizes() {
    return PaperSize.availableSizes;
  }
}
