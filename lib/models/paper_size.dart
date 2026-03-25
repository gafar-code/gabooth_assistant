import 'package:pdf/pdf.dart';

enum PaperSizeType {
  r2x6, // 2R (2x6 inch)
  r4x6, // 4R (4x6 inch)
  r6x4, // 6R landscape (6x4 inch)
  r6x6, // Square (6x6 inch)
  r5x7, // 5x7 inch
  r8x10, // 8x10 inch
}

class PaperSize {
  final PaperSizeType type;
  final String displayName;
  final double widthInches;
  final double heightInches;
  final String description;

  const PaperSize({
    required this.type,
    required this.displayName,
    required this.widthInches,
    required this.heightInches,
    required this.description,
  });

  /// Convert to PDF page format
  PdfPageFormat get pdfPageFormat {
    return PdfPageFormat(
      widthInches * PdfPageFormat.inch,
      heightInches * PdfPageFormat.inch,
      marginAll: 0,
    );
  }

  /// Get aspect ratio
  double get aspectRatio => widthInches / heightInches;

  /// Check if size is landscape
  bool get isLandscape => widthInches > heightInches;

  /// Check if size is square
  bool get isSquare => widthInches == heightInches;

  /// Format dimensions as string
  String get dimensionsString => '$widthInches"×$heightInches"';

  static const List<PaperSize> availableSizes = [
    PaperSize(
      type: PaperSizeType.r2x6,
      displayName: '2R (Portrait)',
      widthInches: 2.0,
      heightInches: 6.0,
      description: '2R Standard - 2×6 inch',
    ),
    PaperSize(
      type: PaperSizeType.r4x6,
      displayName: '4R (Portrait)',
      widthInches: 4.0,
      heightInches: 6.0,
      description: '4R Standard - 4×6 inch',
    ),
    PaperSize(
      type: PaperSizeType.r6x4,
      displayName: '6R (Landscape)',
      widthInches: 6.0,
      heightInches: 4.0,
      description: '6R Landscape - 6×4 inch',
    ),
    PaperSize(
      type: PaperSizeType.r6x6,
      displayName: 'Square',
      widthInches: 6.0,
      heightInches: 6.0,
      description: 'Square Format - 6×6 inch',
    ),
    PaperSize(
      type: PaperSizeType.r5x7,
      displayName: '5×7',
      widthInches: 5.0,
      heightInches: 7.0,
      description: 'Standard 5×7 inch',
    ),
    PaperSize(
      type: PaperSizeType.r8x10,
      displayName: '8×10',
      widthInches: 8.0,
      heightInches: 10.0,
      description: 'Large Format - 8×10 inch',
    ),
  ];

  /// Get paper size by type
  static PaperSize getByType(PaperSizeType type) {
    return availableSizes.firstWhere((size) => size.type == type);
  }

  /// Get paper size by display name
  static PaperSize? getByDisplayName(String displayName) {
    try {
      return availableSizes.firstWhere(
        (size) => size.displayName == displayName,
      );
    } catch (e) {
      return null;
    }
  }

  /// Get default paper size (4R)
  static PaperSize get defaultSize => getByType(PaperSizeType.r4x6);

  /// Get 2R size specifically
  static PaperSize get size2R => getByType(PaperSizeType.r2x6);

  /// Get 4R size specifically
  static PaperSize get size4R => getByType(PaperSizeType.r4x6);

  @override
  String toString() => displayName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaperSize &&
          runtimeType == other.runtimeType &&
          type == other.type;

  @override
  int get hashCode => type.hashCode;
}
