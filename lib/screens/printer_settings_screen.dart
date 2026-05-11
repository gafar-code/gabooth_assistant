import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart';
import 'package:print_windows/print_windows.dart';

import '../models/printer_calibration.dart';
import '../models/printer_device.dart';
import '../providers/printer_calibration_provider.dart';
import '../services/calibration_test_pdf_builder.dart';
import '../services/logger_service.dart';
import '../services/printer_service.dart';

class PrinterSettingsScreen extends ConsumerStatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  ConsumerState<PrinterSettingsScreen> createState() =>
      _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends ConsumerState<PrinterSettingsScreen> {
  bool _isLoadingPrinters = true;
  bool _isPrinting = false;

  List<PrinterDevice> _printers = const [];
  String? _selectedPrinterName;

  // Driver-derived paper sizes for the currently selected printer.
  List<DriverPaperSize> _paperSizes = const [];
  DriverPaperSize? _selectedPaperSize;
  bool _isLoadingPaperSizes = false;
  String? _paperSizesError;

  // Calibration values for the currently selected printer.
  double _targetWidth = 0.0;
  double _targetHeight = 0.0;
  double _offsetX = 0.0;
  double _offsetY = 0.0;
  double _scalePercent = 100.0;

  // On-the-fly preview state.
  PdfController? _pdfController;
  Uint8List? _lastGeneratedPdfBytes;
  int _previewGeneration = 0;

  late TextEditingController _widthController;
  late TextEditingController _heightController;
  late TextEditingController _offsetXController;
  late TextEditingController _offsetYController;
  late TextEditingController _scaleController;

  @override
  void initState() {
    super.initState();
    _widthController = TextEditingController(text: '0.0');
    _heightController = TextEditingController(text: '0.0');
    _offsetXController = TextEditingController(text: '0.0');
    _offsetYController = TextEditingController(text: '0.0');
    _scaleController = TextEditingController(text: '100.0');

    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    _offsetXController.dispose();
    _offsetYController.dispose();
    _scaleController.dispose();
    _pdfController?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _loadPrinters();
    if (mounted) setState(() => _isLoadingPrinters = false);
  }

  Future<void> _loadPrinters() async {
    try {
      final printers = await PrinterService.instance.getAvailablePrinters();
      if (!mounted) return;
      setState(() => _printers = printers);
      if (_selectedPrinterName == null && printers.isNotEmpty) {
        final defaultPrinter = printers.firstWhere(
          (p) => p.isDefault,
          orElse: () => printers.first,
        );
        await _selectPrinter(defaultPrinter.printerName);
      }
    } catch (e, st) {
      Logger.w('[SETTINGS] Failed to load printers', e, st);
    }
  }

  Future<void> _selectPrinter(String name) async {
    setState(() => _selectedPrinterName = name);
    _loadCalibrationForSelected();
    await _loadPaperSizesFor(name);
  }

  void _loadCalibrationForSelected() {
    final name = _selectedPrinterName;
    if (name == null) return;
    final cals = ref.read(printerCalibrationsProvider).valueOrNull ?? {};
    final cal = cals[name] ?? const PrinterCalibration.zero();
    _applyCalibration(cal);
  }

  void _applyCalibration(PrinterCalibration cal) {
    setState(() {
      _targetWidth = cal.targetWidthMm;
      _targetHeight = cal.targetHeightMm;
      _offsetX = cal.offsetXMm;
      _offsetY = cal.offsetYMm;
      _scalePercent = cal.scalePercent;
    });
    _widthController.text = _targetWidth.toStringAsFixed(1);
    _heightController.text = _targetHeight.toStringAsFixed(1);
    _offsetXController.text = _offsetX.toStringAsFixed(1);
    _offsetYController.text = _offsetY.toStringAsFixed(1);
    _scaleController.text = _scalePercent.toStringAsFixed(1);
  }

  PrinterCalibration get _currentCalibration => PrinterCalibration(
        targetWidthMm: _targetWidth,
        targetHeightMm: _targetHeight,
        offsetXMm: _offsetX,
        offsetYMm: _offsetY,
        scalePercent: _scalePercent,
      );

  /// Fire-and-forget auto-save on every change.
  void _autoSave() {
    final name = _selectedPrinterName;
    if (name == null) return;
    final cal = PrinterCalibration(
      targetWidthMm: _targetWidth.clamp(0.0, 500.0),
      targetHeightMm: _targetHeight.clamp(0.0, 500.0),
      offsetXMm: _offsetX.clamp(-100.0, 100.0),
      offsetYMm: _offsetY.clamp(-100.0, 100.0),
      scalePercent: _scalePercent.clamp(50.0, 200.0),
    );
    ref.read(printerCalibrationsProvider.notifier).save(name, cal);
  }

  // ── Paper sizes + preview generation ─────────────────────────────────────

  Future<void> _loadPaperSizesFor(String printerName) async {
    setState(() {
      _isLoadingPaperSizes = true;
      _paperSizesError = null;
      _paperSizes = const [];
      _selectedPaperSize = null;
      _lastGeneratedPdfBytes = null;
      _pdfController?.dispose();
      _pdfController = null;
    });
    try {
      final sizes = await PrinterService.instance.listPaperSizes(printerName);
      if (!mounted) return;
      if (sizes.isEmpty) {
        setState(() {
          _isLoadingPaperSizes = false;
          _paperSizesError =
              'Driver printer "$printerName" tidak meng-expose daftar paper '
              'size. Test print tidak tersedia untuk printer ini.';
        });
        return;
      }
      setState(() {
        _paperSizes = sizes;
        _selectedPaperSize = sizes.first;
        _isLoadingPaperSizes = false;
      });
      await _regeneratePreview();
    } catch (e, st) {
      Logger.e('[SETTINGS] Failed to read paper sizes', e, st);
      if (!mounted) return;
      setState(() {
        _isLoadingPaperSizes = false;
        _paperSizesError = 'Failed to read paper sizes: $e';
      });
    }
  }

  Future<void> _regeneratePreview() async {
    final size = _selectedPaperSize;
    if (size == null) return;
    final generation = ++_previewGeneration;

    // Tear down the previous controller and show a spinner before we start
    // building. Without this, pdfx keeps the stale controller mounted while
    // the new PDF is generating; swapping controllers later with the same
    // ValueKey can leave the view stuck on a loading state.
    final oldController = _pdfController;
    if (oldController != null || _lastGeneratedPdfBytes != null) {
      setState(() {
        _pdfController = null;
        _lastGeneratedPdfBytes = null;
      });
      oldController?.dispose();
    }

    try {
      final bytes = await CalibrationTestPdfBuilder.build(
        widthMm: size.widthMm,
        heightMm: size.heightMm,
        paperLabel: size.name,
      );
      // Skip if user switched printer/paper while we were generating.
      if (!mounted || generation != _previewGeneration) return;
      setState(() {
        _pdfController =
            PdfController(document: PdfDocument.openData(bytes));
        _lastGeneratedPdfBytes = bytes;
      });
    } catch (e, st) {
      Logger.e('[SETTINGS] Failed to generate preview', e, st);
    }
  }

  void _onPaperSizeChanged(DriverPaperSize size) {
    if (_selectedPaperSize == size) return;
    // Auto-fill target width/height from the chosen paper and zero out the
    // offsets — starting point for a fresh calibration on that paper.
    // Scale is left as-is so the user's existing scale factor survives.
    setState(() {
      _selectedPaperSize = size;
      _targetWidth = size.widthMm;
      _targetHeight = size.heightMm;
      _offsetX = 0.0;
      _offsetY = 0.0;
    });
    _widthController.text = _targetWidth.toStringAsFixed(1);
    _heightController.text = _targetHeight.toStringAsFixed(1);
    _offsetXController.text = '0.0';
    _offsetYController.text = '0.0';
    _autoSave();
    _regeneratePreview();
  }

  // ── Calibration value plumbing ───────────────────────────────────────────

  void _clearValues() {
    _applyCalibration(const PrinterCalibration.zero());
    _autoSave();
    _snack('Values cleared to defaults');
  }

  Future<void> _copyValues() async {
    final data = 'width:${_targetWidth.toStringAsFixed(1)},'
        'height:${_targetHeight.toStringAsFixed(1)},'
        'offsetX:${_offsetX.toStringAsFixed(1)},'
        'offsetY:${_offsetY.toStringAsFixed(1)},'
        'scale:${_scalePercent.toStringAsFixed(1)}';
    await Clipboard.setData(ClipboardData(text: data));
    _snack('Values copied to clipboard');
  }

  Future<void> _pasteValues() async {
    try {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clip?.text;
      if (text == null || text.trim().isEmpty) {
        _snack('Clipboard is empty');
        return;
      }
      double? newWidth, newHeight, newOffsetX, newOffsetY, newScale;
      for (final part in text.split(',')) {
        final kv = part.split(':');
        if (kv.length != 2) continue;
        final key = kv[0].trim();
        final value = double.tryParse(kv[1].trim());
        if (value == null) continue;
        switch (key) {
          case 'width':
            newWidth = value.clamp(0.0, 500.0);
            break;
          case 'height':
            newHeight = value.clamp(0.0, 500.0);
            break;
          case 'offsetX':
            newOffsetX = value.clamp(-100.0, 100.0);
            break;
          case 'offsetY':
            newOffsetY = value.clamp(-100.0, 100.0);
            break;
          case 'scale':
            newScale = value.clamp(50.0, 200.0);
            break;
        }
      }
      if (newWidth == null &&
          newHeight == null &&
          newOffsetX == null &&
          newOffsetY == null &&
          newScale == null) {
        _snack('Invalid clipboard format');
        return;
      }
      setState(() {
        if (newWidth != null) {
          _targetWidth = newWidth;
          _widthController.text = newWidth.toStringAsFixed(1);
        }
        if (newHeight != null) {
          _targetHeight = newHeight;
          _heightController.text = newHeight.toStringAsFixed(1);
        }
        if (newOffsetX != null) {
          _offsetX = newOffsetX;
          _offsetXController.text = newOffsetX.toStringAsFixed(1);
        }
        if (newOffsetY != null) {
          _offsetY = newOffsetY;
          _offsetYController.text = newOffsetY.toStringAsFixed(1);
        }
        if (newScale != null) {
          _scalePercent = newScale;
          _scaleController.text = newScale.toStringAsFixed(1);
        }
      });
      _autoSave();
      _snack('Values pasted from clipboard');
    } catch (e) {
      _snack('Paste failed: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
    );
  }

  Future<void> _printTestPage() async {
    final name = _selectedPrinterName;
    final size = _selectedPaperSize;
    final bytes = _lastGeneratedPdfBytes;
    if (name == null || size == null || bytes == null) {
      _snack('Preview not ready');
      return;
    }
    setState(() => _isPrinting = true);
    try {
      final cal = _currentCalibration;
      final ok = await PrinterService.instance.printDocument(
        printerName: name,
        documentData: bytes,
        paperWidthMm: size.widthMm,
        paperHeightMm: size.heightMm,
        copies: 1,
        jobName: 'Calibration Test — ${size.name}',
        targetWidthMm: cal.targetWidthMm,
        targetHeightMm: cal.targetHeightMm,
        offsetXMm: cal.offsetXMm,
        offsetYMm: cal.offsetYMm,
        scalePercent: cal.scalePercent,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Print job sent!' : 'Print failed'),
          backgroundColor: ok ? Colors.green[700] : Colors.red,
        ),
      );
    } catch (e) {
      if (mounted) _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  // ── Expression evaluator: "10+5-2" → 13 ──────────────────────────────────
  double? _evaluateExpression(String text) {
    if (text.trim().isEmpty) return null;
    final match = RegExp(r'^(-?\d*\.?\d+)(.*)$').firstMatch(text.trim());
    if (match == null) return null;
    final first = double.tryParse(match.group(1)!);
    if (first == null) return null;
    double result = first;
    final rest = match.group(2)!;
    final ops = RegExp(r'([+\-])(\d*\.?\d+)').allMatches(rest);
    for (final op in ops) {
      final value = double.tryParse(op.group(2)!);
      if (value == null) continue;
      if (op.group(1) == '+') {
        result += value;
      } else {
        result -= value;
      }
    }
    return result;
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    ref.watch(printerCalibrationsProvider);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        title: Text(
          'Printer Calibration',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w500,
            fontSize: 18,
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: _loadPrinters,
            icon: Icon(Icons.refresh, size: 18, color: colorScheme.primary),
            label: Text('Refresh',
                style: TextStyle(color: colorScheme.primary)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoadingPrinters
          ? Center(
              child: CircularProgressIndicator(
                color: colorScheme.primary,
                strokeWidth: 2,
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 900;
                return isWide ? _buildLandscape() : _buildPortrait();
              },
            ),
    );
  }

  Widget _buildLandscape() {
    return Row(
      children: [
        _buildSidebar(),
        Expanded(child: _buildPreviewPanel(compact: false)),
        SizedBox(width: 340, child: _buildSettingsPanel()),
      ],
    );
  }

  Widget _buildPortrait() {
    // Responsive preview height: ~38% of the viewport, clamped so neither
    // the preview nor the settings panel below it become unreadable on
    // small phones or tall foldables.
    final screenH = MediaQuery.of(context).size.height;
    final previewH = (screenH * 0.38).clamp(260.0, 400.0);

    return Column(
      children: [
        _buildPrinterChips(),
        SizedBox(height: previewH, child: _buildPreviewPanel(compact: true)),
        Expanded(child: _buildSettingsPanel()),
      ],
    );
  }

  // ── Sidebar / printer chips ──────────────────────────────────────────────

  Map<String, PrinterCalibration> _calibrationsSnapshot() {
    return ref.read(printerCalibrationsProvider).valueOrNull ?? const {};
  }

  bool _isConfigured(String printerName) {
    final cal = _calibrationsSnapshot()[printerName];
    return cal != null && !cal.isNoOp;
  }

  Widget _buildSidebar() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(right: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Text(
              'Printers',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: _printers.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No printers detected. Plug in a printer and tap Refresh.',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _printers.length,
                    itemBuilder: (context, index) {
                      return _buildSidebarItem(_printers[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(PrinterDevice p) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = _selectedPrinterName == p.printerName;
    final configured = _isConfigured(p.printerName);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: isSelected ? colorScheme.primaryContainer : colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _selectPrinter(p.printerName),
          borderRadius: BorderRadius.circular(10),
          hoverColor: colorScheme.surfaceContainerLow,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? colorScheme.primary.withAlpha(80)
                    : colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.print_outlined,
                    size: 18,
                    color: isSelected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.printerName,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        configured
                            ? 'Configured'
                            : (p.isDefault
                                ? 'Default · ${p.printerType ?? "Unknown"}'
                                : (p.printerType ?? 'Unknown')),
                        style: TextStyle(
                          color: configured
                              ? Colors.green[700]
                              : colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (configured)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPrinterChips() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: _printers.isEmpty
          ? Center(
              child: Text(
                'No printers — tap Refresh',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            )
          : ListView.builder(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              itemCount: _printers.length,
              itemBuilder: (context, index) {
                final p = _printers[index];
                final isSelected = _selectedPrinterName == p.printerName;
                final configured = _isConfigured(p.printerName);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Material(
                    color: isSelected
                        ? colorScheme.primaryContainer
                        : colorScheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () => _selectPrinter(p.printerName),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? colorScheme.primary.withAlpha(80)
                                : colorScheme.outlineVariant,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.print_outlined,
                              size: 16,
                              color: isSelected
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              p.printerName,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: isSelected
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                                fontSize: 13,
                              ),
                            ),
                            if (configured) ...[
                              const SizedBox(width: 6),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  // ── Preview panel ────────────────────────────────────────────────────────

  Widget _buildPreviewPanel({required bool compact}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: Colors.grey[900],
      padding: EdgeInsets.all(compact ? 12 : 24),
      child: compact
          ? Column(
              children: [
                _buildPaperSizeDropdown(),
                const SizedBox(height: 10),
                Expanded(child: _buildPreviewArea(compact: true)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[850],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.visibility,
                        color: Colors.white.withValues(alpha: 0.9),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Preview',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                      const Spacer(),
                      if (_selectedPaperSize != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_selectedPaperSize!.name} • '
                            '${_selectedPaperSize!.dimensions}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildPaperSizeDropdown(),
                const SizedBox(height: 16),
                Expanded(child: _buildPreviewArea(compact: false)),
              ],
            ),
    );
  }

  Widget _buildPaperSizeDropdown() {
    // Light surface that pops on the dark preview pane background.
    final fill = Colors.white.withValues(alpha: 0.10);
    final border = Colors.white.withValues(alpha: 0.32);

    if (_isLoadingPaperSizes) {
      return Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Reading driver…',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
    if (_paperSizes.isEmpty) {
      return Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(
              Icons.description_outlined,
              size: 18,
              color: Colors.white.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _selectedPrinterName == null
                    ? 'Select a printer'
                    : 'No paper sizes available',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }
    final selected = _selectedPaperSize;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _openPaperSizePicker,
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Icon(
                Icons.description_outlined,
                size: 16,
                color: Colors.white.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: selected == null
                    ? Text(
                        'Pick a paper size',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 13,
                        ),
                      )
                    : Row(
                        children: [
                          Flexible(
                            child: Text(
                              selected.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            selected.dimensions,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.70),
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.expand_more_rounded,
                size: 20,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPaperSizePicker() async {
    if (_paperSizes.isEmpty) return;
    final picked = await showDialog<DriverPaperSize>(
      context: context,
      builder: (ctx) => _PaperSizePickerDialog(
        sizes: _paperSizes,
        selected: _selectedPaperSize,
      ),
    );
    if (picked != null) {
      _onPaperSizeChanged(picked);
    }
  }

  Widget _buildPreviewArea({required bool compact}) {
    if (_paperSizesError != null) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.red[300], size: 32),
              const SizedBox(height: 8),
              Text(
                _paperSizesError!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: compact ? double.infinity : 480),
        decoration: BoxDecoration(
          color: Colors.grey[850],
          borderRadius: BorderRadius.circular(compact ? 10 : 12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: compact ? 10 : 20,
              offset: Offset(0, compact ? 4 : 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(compact ? 10 : 12),
          child: _buildPdfView(compact: compact),
        ),
      ),
    );
  }

  Widget _buildPdfView({required bool compact}) {
    if (_pdfController == null) {
      return Center(
        child: CircularProgressIndicator(
          color: Colors.white.withValues(alpha: 0.7),
          strokeWidth: compact ? 2 : 4,
        ),
      );
    }
    return PdfView(
      key: ValueKey(
        '${compact ? "compact_" : ""}${_selectedPrinterName}_'
        '${_selectedPaperSize?.paperId}_$_previewGeneration',
      ),
      controller: _pdfController!,
      scrollDirection: Axis.vertical,
      physics: compact
          ? const NeverScrollableScrollPhysics()
          : const BouncingScrollPhysics(),
      builders: PdfViewBuilders<DefaultBuilderOptions>(
        options: const DefaultBuilderOptions(),
        documentLoaderBuilder: (_) => Center(
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: compact ? 2 : 4,
          ),
        ),
        pageLoaderBuilder: (_) => Center(
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: compact ? 2 : 4,
          ),
        ),
        errorBuilder: (_, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Preview error: $error',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  // ── Settings panel ───────────────────────────────────────────────────────

  Widget _buildSettingsPanel() {
    final colorScheme = Theme.of(context).colorScheme;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    PrinterDevice? selectedPrinter;
    if (_selectedPrinterName != null) {
      for (final p in _printers) {
        if (p.printerName == _selectedPrinterName) {
          selectedPrinter = p;
          break;
        }
      }
    }
    final hasPrinter = _selectedPrinterName != null;
    final canPrint = hasPrinter &&
        !_isPrinting &&
        _selectedPaperSize != null &&
        _lastGeneratedPdfBytes != null;

    return Container(
      alignment: Alignment.topCenter,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: isPortrait
            ? Border(top: BorderSide(color: colorScheme.outlineVariant))
            : Border(left: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(isPortrait ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: isPortrait ? 36 : 44,
                  height: isPortrait ? 36 : 44,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.print_rounded,
                    size: isPortrait ? 18 : 22,
                    color: colorScheme.onPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedPrinterName ?? 'No printer selected',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                          fontSize: isPortrait ? 15 : 17,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        selectedPrinter == null
                            ? 'Select a printer from the list'
                            : '${selectedPrinter.printerType ?? "Unknown"}'
                                '${selectedPrinter.isDefault ? " · Default" : ""}',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: isPortrait ? 20 : 28),

            Row(
              children: [
                _buildFieldLabel('Calibration'),
                const Spacer(),
                Tooltip(
                  message: 'Clear',
                  child: IconButton(
                    onPressed: hasPrinter ? _clearValues : null,
                    icon: Icon(
                      Icons.clear_all,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Copy',
                  child: IconButton(
                    onPressed: hasPrinter ? _copyValues : null,
                    icon: Icon(
                      Icons.copy,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Paste',
                  child: IconButton(
                    onPressed: hasPrinter ? _pasteValues : null,
                    icon: Icon(
                      Icons.paste,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildCalibrationControls(enabled: hasPrinter),

            SizedBox(height: isPortrait ? 20 : 28),

            SizedBox(
              width: double.infinity,
              height: isPortrait ? 42 : 46,
              child: FilledButton.icon(
                onPressed: canPrint ? _printTestPage : null,
                icon: _isPrinting
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            colorScheme.onPrimary,
                          ),
                        ),
                      )
                    : const Icon(Icons.print_rounded, size: 18),
                label: Text(
                  _isPrinting
                      ? 'Printing...'
                      : isPortrait
                          ? 'Print Test'
                          : 'Print Test Page',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: isPortrait ? 13 : 14,
                  ),
                ),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurfaceVariant,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildCalibrationControls({required bool enabled}) {
    final colorScheme = Theme.of(context).colorScheme;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    return Container(
      padding: EdgeInsets.all(isPortrait ? 12 : 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          _buildNumberField('Scale', '%', _scaleController, enabled, (v) {
            setState(() => _scalePercent = v.clamp(50.0, 200.0));
            _autoSave();
          }),
          SizedBox(height: isPortrait ? 8 : 12),
          _buildNumberField('Offset X', 'mm', _offsetXController, enabled, (v) {
            setState(() => _offsetX = v.clamp(-100.0, 100.0));
            _autoSave();
          }),
          SizedBox(height: isPortrait ? 8 : 12),
          _buildNumberField('Offset Y', 'mm', _offsetYController, enabled, (v) {
            setState(() => _offsetY = v.clamp(-100.0, 100.0));
            _autoSave();
          }),
          SizedBox(height: isPortrait ? 8 : 12),
          _buildNumberField('Width', 'mm', _widthController, enabled, (v) {
            setState(() => _targetWidth = v.clamp(0.0, 500.0));
            _autoSave();
          }),
          SizedBox(height: isPortrait ? 8 : 12),
          _buildNumberField('Height', 'mm', _heightController, enabled, (v) {
            setState(() => _targetHeight = v.clamp(0.0, 500.0));
            _autoSave();
          }),
        ],
      ),
    );
  }

  Widget _buildNumberField(
    String label,
    String suffix,
    TextEditingController controller,
    bool enabled,
    void Function(double) onChanged,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    return Row(
      children: [
        SizedBox(
          width: isPortrait ? 50 : 65,
          child: Text(
            label,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: isPortrait ? 11 : 13,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: Opacity(
            opacity: enabled ? 1.0 : 0.5,
            child: Container(
              height: isPortrait ? 34 : 38,
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  _buildStepButton(Icons.remove_rounded, enabled, () {
                    final v = (double.tryParse(controller.text) ?? 0) -
                        (suffix == '%' ? 1 : 0.1);
                    controller.text = v.toStringAsFixed(1);
                    onChanged(v);
                  }),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      enabled: enabled,
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^-?\d*\.?\d*([+\-]\d*\.?\d*)*'),
                        ),
                      ],
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                        fontSize: isPortrait ? 12 : 13,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                      onChanged: (text) {
                        final v = double.tryParse(text);
                        if (v != null) onChanged(v);
                      },
                      onSubmitted: (text) {
                        final result = _evaluateExpression(text);
                        if (result != null) {
                          controller.text = result.toStringAsFixed(1);
                          onChanged(result);
                        }
                      },
                    ),
                  ),
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: isPortrait ? 4 : 8),
                    child: Text(
                      suffix,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: isPortrait ? 10 : 12,
                      ),
                    ),
                  ),
                  _buildStepButton(Icons.add_rounded, enabled, () {
                    final v = (double.tryParse(controller.text) ?? 0) +
                        (suffix == '%' ? 1 : 0.1);
                    controller.text = v.toStringAsFixed(1);
                    onChanged(v);
                  }),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepButton(IconData icon, bool enabled, VoidCallback onTap) {
    final colorScheme = Theme.of(context).colorScheme;
    return _HoldableButton(
      enabled: enabled,
      onTap: onTap,
      child: Container(
        width: 32,
        height: 38,
        alignment: Alignment.center,
        child: Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// A button that triggers repeatedly when held down.
class _HoldableButton extends StatefulWidget {
  const _HoldableButton({
    required this.onTap,
    required this.child,
    this.enabled = true,
  });

  final VoidCallback onTap;
  final Widget child;
  final bool enabled;

  @override
  State<_HoldableButton> createState() => _HoldableButtonState();
}

class _HoldableButtonState extends State<_HoldableButton> {
  Timer? _timer;
  bool _isHolding = false;
  int _holdCount = 0;

  void _startHolding() {
    if (!widget.enabled) return;
    _isHolding = true;
    _holdCount = 0;
    widget.onTap();

    _timer = Timer(const Duration(milliseconds: 400), () {
      if (_isHolding) _startRepeating();
    });
  }

  void _startRepeating() {
    _timer?.cancel();
    int interval = 100 - (_holdCount * 5);
    if (interval < 30) interval = 30;

    _timer = Timer.periodic(Duration(milliseconds: interval), (timer) {
      if (_isHolding) {
        widget.onTap();
        _holdCount++;
        if (_holdCount % 5 == 0 && interval > 30) _startRepeating();
      } else {
        timer.cancel();
      }
    });
  }

  void _stopHolding() {
    _isHolding = false;
    _holdCount = 0;
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _startHolding(),
      onPointerUp: (_) => _stopHolding(),
      onPointerCancel: (_) => _stopHolding(),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: widget.enabled ? () {} : null,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Modal picker for paper sizes with a live search field. Useful because
/// printer drivers commonly advertise 20+ sizes (Letter, A4, A5, 4R, 5R,
/// envelopes, custom forms, …) and a flat dropdown is hard to scan.
class _PaperSizePickerDialog extends StatefulWidget {
  const _PaperSizePickerDialog({
    required this.sizes,
    required this.selected,
  });

  final List<DriverPaperSize> sizes;
  final DriverPaperSize? selected;

  @override
  State<_PaperSizePickerDialog> createState() => _PaperSizePickerDialogState();
}

class _PaperSizePickerDialogState extends State<_PaperSizePickerDialog> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final next = _searchController.text;
      if (next == _query) return;
      setState(() => _query = next);
    });
    // Autofocus the search after the dialog finishes its open animation —
    // grabbing focus immediately can fight the dialog's transition.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<DriverPaperSize> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.sizes;
    return widget.sizes.where((p) {
      final name = p.name.toLowerCase();
      final dims = p.dimensions.toLowerCase();
      // Match against the name, the dimensions string ("102×152 mm"),
      // and a "WxH" form so users can search by either axis.
      final wxh = '${p.widthMm.toStringAsFixed(0)}x'
          '${p.heightMm.toStringAsFixed(0)}';
      return name.contains(q) || dims.contains(q) || wxh.contains(q);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final filtered = _filtered;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Select Paper Size',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Cancel',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            // ── Search field ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search by name or size (e.g. "4R", "A4", "102")',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          tooltip: 'Clear',
                          onPressed: () {
                            _searchController.clear();
                            _searchFocus.requestFocus();
                          },
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        BorderSide(color: colorScheme.primary, width: 1.4),
                  ),
                ),
                onSubmitted: (_) {
                  // Enter = pick the first filtered result, if any.
                  if (filtered.isNotEmpty) {
                    Navigator.of(context).pop(filtered.first);
                  }
                },
              ),
            ),
            const SizedBox(height: 4),
            Divider(
              height: 1,
              thickness: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
            // ── Result list ───────────────────────────────────────────
            Flexible(
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(28),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              size: 28,
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.6),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No paper sizes match "$_query"',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final p = filtered[index];
                        final isSelected = p == widget.selected;
                        return InkWell(
                          onTap: () => Navigator.of(context).pop(p),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            color: isSelected
                                ? colorScheme.primaryContainer
                                    .withValues(alpha: 0.4)
                                : null,
                            child: Row(
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.check_circle_rounded
                                      : Icons.description_outlined,
                                  size: 18,
                                  color: isSelected
                                      ? colorScheme.primary
                                      : colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    p.name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: colorScheme.onSurface,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  p.dimensions,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
            // ── Footer ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  Text(
                    '${filtered.length} of ${widget.sizes.length}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
