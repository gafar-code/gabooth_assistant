/// Per-printer calibration values applied at print time.
///
/// All values default to a no-op: 0mm targets/offsets and 100% scale,
/// equivalent to "print the document as-is, full paper". Non-zero values
/// are forwarded to the `print_windows` plugin which applies them in the
/// Windows print driver.
class PrinterCalibration {
  /// Target content width in mm (0 = full paper).
  final double targetWidthMm;

  /// Target content height in mm (0 = full paper).
  final double targetHeightMm;

  /// Horizontal offset in mm (positive = right, negative = left).
  final double offsetXMm;

  /// Vertical offset in mm (positive = down, negative = up).
  final double offsetYMm;

  /// Scale percent applied after fit-to-page (100 = no-op).
  final double scalePercent;

  const PrinterCalibration({
    this.targetWidthMm = 0.0,
    this.targetHeightMm = 0.0,
    this.offsetXMm = 0.0,
    this.offsetYMm = 0.0,
    this.scalePercent = 100.0,
  });

  const PrinterCalibration.zero()
      : targetWidthMm = 0.0,
        targetHeightMm = 0.0,
        offsetXMm = 0.0,
        offsetYMm = 0.0,
        scalePercent = 100.0;

  bool get isNoOp =>
      targetWidthMm == 0.0 &&
      targetHeightMm == 0.0 &&
      offsetXMm == 0.0 &&
      offsetYMm == 0.0 &&
      scalePercent == 100.0;

  PrinterCalibration copyWith({
    double? targetWidthMm,
    double? targetHeightMm,
    double? offsetXMm,
    double? offsetYMm,
    double? scalePercent,
  }) {
    return PrinterCalibration(
      targetWidthMm: targetWidthMm ?? this.targetWidthMm,
      targetHeightMm: targetHeightMm ?? this.targetHeightMm,
      offsetXMm: offsetXMm ?? this.offsetXMm,
      offsetYMm: offsetYMm ?? this.offsetYMm,
      scalePercent: scalePercent ?? this.scalePercent,
    );
  }

  Map<String, dynamic> toJson() => {
        'targetWidthMm': targetWidthMm,
        'targetHeightMm': targetHeightMm,
        'offsetXMm': offsetXMm,
        'offsetYMm': offsetYMm,
        'scalePercent': scalePercent,
      };

  factory PrinterCalibration.fromJson(Map<String, dynamic> j) {
    double d(String key, double fallback) =>
        (j[key] as num?)?.toDouble() ?? fallback;
    return PrinterCalibration(
      targetWidthMm: d('targetWidthMm', 0.0),
      targetHeightMm: d('targetHeightMm', 0.0),
      offsetXMm: d('offsetXMm', 0.0),
      offsetYMm: d('offsetYMm', 0.0),
      scalePercent: d('scalePercent', 100.0),
    );
  }

  @override
  String toString() =>
      'PrinterCalibration(target=${targetWidthMm}x${targetHeightMm}mm, '
      'offset=($offsetXMm,$offsetYMm)mm, scale=$scalePercent%)';
}
