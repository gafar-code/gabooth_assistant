import 'package:objectbox/objectbox.dart';

/// Printer settings for position and size adjustments
/// These settings are applied when printing to compensate for printer hardware variations
@Entity()
class PrinterSettings {
  @Id()
  int id = 0;

  /// Unique key to identify this settings instance (usually 'default')
  @Unique()
  String key;

  /// Target width in millimeters (0 = use original size)
  double targetWidthMm;

  /// Target height in millimeters (0 = use original size)
  double targetHeightMm;

  /// Horizontal offset in millimeters (positive = move right, negative = move left)
  double offsetXMm;

  /// Vertical offset in millimeters (positive = move down, negative = move up)
  double offsetYMm;

  /// Scale factor in percentage (100 = original size, 95 = 95%, 105 = 105%)
  /// Applied after fitToPage scaling
  double scalePercent;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  @Property(type: PropertyType.date)
  DateTime updatedAt;

  PrinterSettings({
    required this.key,
    this.targetWidthMm = 0.0,
    this.targetHeightMm = 0.0,
    this.offsetXMm = 0.0,
    this.offsetYMm = 0.0,
    this.scalePercent = 100.0,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  /// Create a copy with updated values
  PrinterSettings copyWith({
    String? key,
    double? targetWidthMm,
    double? targetHeightMm,
    double? offsetXMm,
    double? offsetYMm,
    double? scalePercent,
    DateTime? updatedAt,
  }) {
    return PrinterSettings(
      key: key ?? this.key,
      targetWidthMm: targetWidthMm ?? this.targetWidthMm,
      targetHeightMm: targetHeightMm ?? this.targetHeightMm,
      offsetXMm: offsetXMm ?? this.offsetXMm,
      offsetYMm: offsetYMm ?? this.offsetYMm,
      scalePercent: scalePercent ?? this.scalePercent,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'PrinterSettings(key: $key, width: ${targetWidthMm}mm, height: ${targetHeightMm}mm, offsetX: ${offsetXMm}mm, offsetY: ${offsetYMm}mm, scale: $scalePercent%)';
  }
}
