import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/printer_calibration.dart';
import '../services/printer_calibration_repository.dart';

class PrinterCalibrationsNotifier
    extends AsyncNotifier<Map<String, PrinterCalibration>> {
  PrinterCalibrationRepository get _repo =>
      PrinterCalibrationRepository.instance;

  @override
  Future<Map<String, PrinterCalibration>> build() async {
    await _repo.ensureLoaded();
    return _repo.snapshot();
  }

  Future<void> save(String printerName, PrinterCalibration cal) async {
    await _repo.save(printerName, cal);
    state = AsyncData(_repo.snapshot());
  }

  Future<void> reset(String printerName) async {
    await _repo.delete(printerName);
    state = AsyncData(_repo.snapshot());
  }
}

final printerCalibrationsProvider = AsyncNotifierProvider<
    PrinterCalibrationsNotifier,
    Map<String, PrinterCalibration>>(PrinterCalibrationsNotifier.new);
