import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Generates a single-page PDF used for printer calibration testing.
///
/// Ported from `gabooth_event` (`lib/features/printer/printer_service.dart`'s
/// `_renderTestPdf`). The page is drawn directly at the requested physical
/// dimensions (no margin) with:
///   - Outer edge frame (verify content isn't clipped)
///   - 5mm safe-zone inner frame
///   - Trim marks (L-shape at TL & BR)
///   - 0–10mm rulers at TL & BR corners
///   - Brand pill title + paper info pill
///   - 7 RGB+CMYK color swatches
///   - Grayscale gradient bar (0–100%)
///   - Center crosshair (alignment check)
///   - Timestamp footer
class CalibrationTestPdfBuilder {
  static const _brand = PdfColor.fromInt(0xFF6366F1);
  static const _ink = PdfColor.fromInt(0xFF0F172A);
  static const _muted = PdfColor.fromInt(0xFF94A3B8);
  static const _subtle = PdfColor.fromInt(0xFFE2E8F0);

  static const _swatches = <(String, PdfColor)>[
    ('R', PdfColor.fromInt(0xFFE53935)),
    ('G', PdfColor.fromInt(0xFF43A047)),
    ('B', PdfColor.fromInt(0xFF1E88E5)),
    ('C', PdfColor.fromInt(0xFF00BCD4)),
    ('M', PdfColor.fromInt(0xFFD81B60)),
    ('Y', PdfColor.fromInt(0xFFFDD835)),
    ('K', PdfColor.fromInt(0xFF000000)),
  ];

  static Future<Uint8List> build({
    required double widthMm,
    required double heightMm,
    required String paperLabel,
  }) async {
    final doc = pw.Document();
    final timestamp = DateTime.now().toString().split('.').first;
    const mm = PdfPageFormat.mm;

    const armLen = 7.0; // mm — trim-mark arm length
    const armW = 0.7;   // pt — trim-mark thickness

    pw.Widget bar({
      double? left,
      double? top,
      double? right,
      double? bottom,
      required double w,
      required double h,
    }) {
      return pw.Positioned(
        left: left,
        top: top,
        right: right,
        bottom: bottom,
        child: pw.Container(width: w, height: h, color: _brand),
      );
    }

    List<pw.Widget> cornerRuler({required bool fromTopLeft}) {
      final fromLeft = fromTopLeft;
      final fromTop = fromTopLeft;
      const tickOffset = armLen * mm + 0.5 * mm;
      const labelOffset = armLen * mm + 3.2 * mm;
      final widgets = <pw.Widget>[];
      for (var i = 0; i <= 10; i++) {
        final tickLen = (i % 5 == 0 ? 2.5 : 1.4) * mm;
        final tickColor = i % 5 == 0 ? _ink : _muted;
        widgets.add(pw.Positioned(
          left: fromLeft ? i * mm : null,
          right: fromLeft ? null : i * mm,
          top: fromTop ? tickOffset : null,
          bottom: fromTop ? null : tickOffset,
          child: pw.Container(width: 0.4, height: tickLen, color: tickColor),
        ));
        widgets.add(pw.Positioned(
          left: fromLeft ? tickOffset : null,
          right: fromLeft ? null : tickOffset,
          top: fromTop ? i * mm : null,
          bottom: fromTop ? null : i * mm,
          child: pw.Container(width: tickLen, height: 0.4, color: tickColor),
        ));
      }
      for (final i in const [5, 10]) {
        widgets.add(pw.Positioned(
          left: fromLeft ? i * mm - 1.5 * mm : null,
          right: fromLeft ? null : i * mm - 1.5 * mm,
          top: fromTop ? labelOffset : null,
          bottom: fromTop ? null : labelOffset,
          child: pw.Text(
            '$i',
            style: pw.TextStyle(
              fontSize: 6,
              color: _ink,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ));
        widgets.add(pw.Positioned(
          left: fromLeft ? labelOffset : null,
          right: fromLeft ? null : labelOffset,
          top: fromTop ? i * mm - 1.5 * mm : null,
          bottom: fromTop ? null : i * mm - 1.5 * mm,
          child: pw.Text(
            '$i',
            style: pw.TextStyle(
              fontSize: 6,
              color: _ink,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ));
      }
      return widgets;
    }

    pw.Widget titleBlock() {
      return pw.Container(
        padding: pw.EdgeInsets.symmetric(
          horizontal: 5 * mm,
          vertical: 3.5 * mm,
        ),
        decoration: pw.BoxDecoration(
          color: _brand,
          borderRadius: pw.BorderRadius.all(pw.Radius.circular(2.5 * mm)),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text(
                    'GABOOTH ASSISTANT',
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                      letterSpacing: 1.4,
                    ),
                  ),
                  pw.SizedBox(height: 1),
                  pw.Text(
                    'Calibration Test',
                    style: pw.TextStyle(
                      fontSize: 7.5,
                      color: PdfColors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            pw.Container(
              padding: pw.EdgeInsets.symmetric(
                horizontal: 3 * mm,
                vertical: 1.6 * mm,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius:
                    pw.BorderRadius.all(pw.Radius.circular(1.5 * mm)),
              ),
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    paperLabel,
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: _brand,
                      letterSpacing: 0.5,
                    ),
                  ),
                  pw.SizedBox(height: 0.5),
                  pw.Text(
                    '${widthMm.toStringAsFixed(0)}×${heightMm.toStringAsFixed(0)} mm',
                    style: pw.TextStyle(
                      fontSize: 6.5,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget colorSwatches() {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            'COLOR CHECK',
            style: pw.TextStyle(
              fontSize: 6,
              color: _muted,
              letterSpacing: 1.0,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 1.5 * mm),
          pw.Row(
            children: [
              for (var i = 0; i < _swatches.length; i++) ...[
                if (i > 0) pw.SizedBox(width: 1.2 * mm),
                pw.Expanded(
                  child: pw.Column(
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      pw.Container(
                        height: 11 * mm,
                        decoration: pw.BoxDecoration(
                          color: _swatches[i].$2,
                          borderRadius: pw.BorderRadius.all(
                            pw.Radius.circular(1 * mm),
                          ),
                          border: pw.Border.all(width: 0.3, color: _ink),
                        ),
                      ),
                      pw.SizedBox(height: 0.8 * mm),
                      pw.Text(
                        _swatches[i].$1,
                        style: pw.TextStyle(
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                          color: _ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      );
    }

    pw.Widget grayscaleBar() {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            'GRAYSCALE',
            style: pw.TextStyle(
              fontSize: 6,
              color: _muted,
              letterSpacing: 1.0,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 1.5 * mm),
          pw.Container(
            height: 5 * mm,
            decoration: pw.BoxDecoration(
              gradient: const pw.LinearGradient(
                begin: pw.Alignment.centerLeft,
                end: pw.Alignment.centerRight,
                colors: [PdfColors.white, PdfColors.black],
              ),
              borderRadius:
                  pw.BorderRadius.all(pw.Radius.circular(0.8 * mm)),
              border: pw.Border.all(width: 0.3, color: _ink),
            ),
          ),
          pw.SizedBox(height: 0.6 * mm),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              for (final pct in const ['0%', '25%', '50%', '75%', '100%'])
                pw.Text(
                  pct,
                  style: pw.TextStyle(fontSize: 5.5, color: _muted),
                ),
            ],
          ),
        ],
      );
    }

    const crosshairMm = 14.0;
    pw.Widget centerCrosshair() {
      return pw.Container(
        width: crosshairMm * mm,
        height: crosshairMm * mm,
        decoration: pw.BoxDecoration(
          shape: pw.BoxShape.circle,
          border: pw.Border.all(width: 0.5, color: _muted),
        ),
        child: pw.Stack(
          alignment: pw.Alignment.center,
          children: [
            pw.Container(width: 0.5, color: _muted),
            pw.Container(height: 0.5, color: _muted),
          ],
        ),
      );
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(widthMm * mm, heightMm * mm, marginAll: 0),
        margin: pw.EdgeInsets.zero,
        build: (context) {
          return pw.Stack(
            children: [
              pw.Positioned.fill(
                child: pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(width: 0.5, color: _ink),
                  ),
                ),
              ),
              pw.Positioned(
                left: 5 * mm,
                top: 5 * mm,
                right: 5 * mm,
                bottom: 5 * mm,
                child: pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(width: 0.3, color: _subtle),
                  ),
                ),
              ),

              bar(left: 0, top: 0, w: armLen * mm, h: armW),
              bar(left: 0, top: 0, w: armW, h: armLen * mm),
              bar(right: 0, bottom: 0, w: armLen * mm, h: armW),
              bar(right: 0, bottom: 0, w: armW, h: armLen * mm),

              ...cornerRuler(fromTopLeft: true),
              ...cornerRuler(fromTopLeft: false),

              pw.Positioned.fill(
                child: pw.Padding(
                  padding: pw.EdgeInsets.fromLTRB(
                    14 * mm,
                    9 * mm,
                    9 * mm,
                    14 * mm,
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      titleBlock(),
                      pw.SizedBox(height: 4 * mm),
                      colorSwatches(),
                      pw.SizedBox(height: 3 * mm),
                      grayscaleBar(),
                      pw.SizedBox(height: 4 * mm),
                      pw.Center(child: centerCrosshair()),
                      pw.SizedBox(height: 2 * mm),
                      pw.Center(
                        child: pw.Text(
                          timestamp,
                          style: pw.TextStyle(fontSize: 7, color: _muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    return doc.save();
  }
}
