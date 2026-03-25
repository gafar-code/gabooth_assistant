import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/printer_device.dart';
import '../services/printer_service.dart';

// Printer Service Provider
final printerServiceProvider = Provider<PrinterService>((ref) {
  return PrinterService.instance;
});

// Available Printers Provider
final availablePrintersProvider = FutureProvider<List<PrinterDevice>>((
  ref,
) async {
  final printerService = ref.read(printerServiceProvider);
  return await printerService.getAvailablePrinters();
});

// Default Printer Provider
final defaultPrinterProvider = FutureProvider<PrinterDevice?>((ref) async {
  final printerService = ref.read(printerServiceProvider);
  return await printerService.getDefaultPrinter();
});

// Per-layout printer selection providers
final selectedQrSoftFileStripPrinterProvider = StateProvider<PrinterDevice?>(
  (ref) => null,
);
final selectedQrSoftFileKolasePrinterProvider = StateProvider<PrinterDevice?>(
  (ref) => null,
);
final selectedQrSoftFileMajalahPrinterProvider = StateProvider<PrinterDevice?>(
  (ref) => null,
);
final selectedQrSoftFileFlipbookPrinterProvider = StateProvider<PrinterDevice?>(
  (ref) => null,
);
final selectedQrSoftFileThermalPrinterProvider = StateProvider<PrinterDevice?>(
  (ref) => null,
);
