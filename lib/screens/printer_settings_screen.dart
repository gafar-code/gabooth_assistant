import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:print_windows/print_windows.dart';
import '../models/printer_settings.dart';
import '../providers/printer_providers.dart';
import '../providers/printer_selection_provider.dart';
import '../services/logger_service.dart';
import '../services/printer_settings_repository.dart';

/// Layout type enum for printer configuration
enum PrinterLayoutType {
  strip('Strip', '2R / Strip format', Icons.view_column),
  kolase('Kolase', '4R / Photo collage', Icons.grid_view),
  majalah('Majalah', 'A3 / Magazine format', Icons.menu_book),
  flipbook('Flipbook', 'Flipbook prints', Icons.auto_stories),
  thermal('Thermal', 'Thermal receipts', Icons.receipt_long);

  const PrinterLayoutType(this.label, this.description, this.icon);
  final String label;
  final String description;
  final IconData icon;
}

enum PdfOrientation { portrait, landscape }

enum PaperSizeOption {
  r2('80mm (2x6")', '80mm'),
  r2x180('80x180mm (3.15x7.09")', '80x180'),
  r4('4R (4x6")', '4R'),
  r5('5R (5x7")', '5R'),
  a5('A5 (5.8x8.3")', 'A5'),
  a4('A4 (8.3x11.7")', 'A4'),
  f4('F4 (8.27x13")', 'F4'),
  a3('A3 (11.7x16.5")', 'A3');

  const PaperSizeOption(this.label, this.shortName);
  final String label;
  final String shortName;

  String getAssetPath(PdfOrientation orientation) {
    final orientationPrefix = orientation == PdfOrientation.portrait
        ? 'potrait'
        : 'landscape';
    return 'assets/pdf/${orientationPrefix}_$shortName.pdf';
  }
}

class PrinterSettingsScreen extends ConsumerStatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  ConsumerState<PrinterSettingsScreen> createState() =>
      _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends ConsumerState<PrinterSettingsScreen> {
  bool _isLoading = true;
  bool _isPrinting = false;

  PrinterLayoutType _selectedLayoutType = PrinterLayoutType.strip;

  // Print settings
  double _targetWidth = 0.0;
  double _targetHeight = 0.0;
  double _offsetX = 0.0;
  double _offsetY = 0.0;
  double _scalePercent = 100.0;

  // PDF settings
  PdfOrientation _selectedOrientation = PdfOrientation.portrait;
  PaperSizeOption _selectedPaperSize = PaperSizeOption.r4;

  // PDF controller
  PdfController? _pdfController;
  String? _selectedPdfPath;

  // Printer
  List<PrinterInfo> _printers = [];
  String? _selectedPrinter;

  // Controllers
  late TextEditingController _widthController;
  late TextEditingController _heightController;
  late TextEditingController _offsetXController;
  late TextEditingController _offsetYController;
  late TextEditingController _scaleController;

  final _printWindows = PrintWindows();
  final _settingsRepo = PrinterSettingsRepository();

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
    try {
      await _initializePrinterProviders();
      await _loadPrinters();
      await _initializePdf();
      await _loadSettings();
      _updateSelectedPrinter();
    } catch (e) {
      Logger.w('Error initializing', e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _initializePrinterProviders() async {
    if (!mounted) return;
    final selectionState = await ref.read(printerSelectionProvider.future);
    final printers = await ref.read(availablePrintersProvider.future);
    if (!mounted) return;

    final mappings = {
      selectionState.stripPrinter: selectedQrSoftFileStripPrinterProvider,
      selectionState.kolasePrinter: selectedQrSoftFileKolasePrinterProvider,
      selectionState.majalahPrinter: selectedQrSoftFileMajalahPrinterProvider,
      selectionState.flipbookPrinter: selectedQrSoftFileFlipbookPrinterProvider,
      selectionState.thermalPrinter: selectedQrSoftFileThermalPrinterProvider,
    };

    for (final entry in mappings.entries) {
      if (entry.key != null) {
        final printer = printers
            .where((p) => p.printerName == entry.key)
            .firstOrNull;
        if (printer != null) ref.read(entry.value.notifier).state = printer;
      }
    }
  }

  Future<void> _loadPrinters() async {
    try {
      final printers = await _printWindows.listPrinters();
      final defaultPrinter = await _printWindows.getDefaultPrinter();
      if (mounted) {
        setState(() {
          _printers = printers;
          _selectedPrinter ??= defaultPrinter;
        });
      }
    } catch (e) {
      Logger.w('Error loading printers', e);
    }
  }

  void _updateSelectedPrinter() {
    final selectionState = ref.read(printerSelectionProvider).valueOrNull;
    if (selectionState == null) return;

    final idMap = {
      PrinterLayoutType.strip: selectionState.stripPrinter,
      PrinterLayoutType.kolase: selectionState.kolasePrinter,
      PrinterLayoutType.majalah: selectionState.majalahPrinter,
      PrinterLayoutType.flipbook: selectionState.flipbookPrinter,
      PrinterLayoutType.thermal: selectionState.thermalPrinter,
    };
    final id = idMap[_selectedLayoutType];
    if (id != null && id.isNotEmpty) setState(() => _selectedPrinter = id);
  }

  Future<void> _initializePdf() async {
    try {
      final oldController = _pdfController;
      _pdfController = null;
      oldController?.dispose();

      if (!mounted) return;
      setState(() {});
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;

      final path = _selectedPaperSize.getAssetPath(_selectedOrientation);
      final controller = PdfController(document: PdfDocument.openAsset(path));
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _pdfController = controller);

      final byteData = await rootBundle.load(path);
      final tempDir = await getTemporaryDirectory();
      final fileName = path.split('/').last;
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(byteData.buffer.asUint8List());
      if (mounted) setState(() => _selectedPdfPath = tempFile.path);
    } catch (e) {
      Logger.e('Error loading PDF', e);
    }
  }

  String get _settingsKey {
    return 'printer_${_selectedLayoutType.name}';
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _settingsRepo.getSettingsByType(
        _selectedLayoutType.name,
      );
      if (settings != null && mounted) {
        setState(() {
          _targetWidth = settings.targetWidthMm;
          _targetHeight = settings.targetHeightMm;
          _offsetX = settings.offsetXMm;
          _offsetY = settings.offsetYMm;
          _scalePercent = settings.scalePercent > 0
              ? settings.scalePercent
              : 100.0;
          _updateControllers();
        });
      } else {
        _resetDefaults();
      }
    } catch (e) {
      _resetDefaults();
    }
  }

  void _resetDefaults() {
    if (!mounted) return;
    setState(() {
      _targetWidth = 0.0;
      _targetHeight = 0.0;
      _offsetX = 0.0;
      _offsetY = 0.0;
      _scalePercent = 100.0;
      _updateControllers();
    });
  }

  void _updateControllers() {
    _widthController.text = _targetWidth.toStringAsFixed(1);
    _heightController.text = _targetHeight.toStringAsFixed(1);
    _offsetXController.text = _offsetX.toStringAsFixed(1);
    _offsetYController.text = _offsetY.toStringAsFixed(1);
    _scaleController.text = _scalePercent.toStringAsFixed(1);
  }

  void _clearValues() {
    _resetDefaults();
    _saveSettings();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Values cleared to defaults'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _copyValues() async {
    final data =
        'width:${_targetWidth.toStringAsFixed(1)},'
        'height:${_targetHeight.toStringAsFixed(1)},'
        'offsetX:${_offsetX.toStringAsFixed(1)},'
        'offsetY:${_offsetY.toStringAsFixed(1)},'
        'scale:${_scalePercent.toStringAsFixed(1)}';
    await Clipboard.setData(ClipboardData(text: data));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Values copied to clipboard'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _pasteValues() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData?.text == null || clipboardData!.text!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Clipboard is empty'),
              duration: Duration(seconds: 1),
            ),
          );
        }
        return;
      }

      final text = clipboardData.text!;
      final parts = text.split(',');

      double? newWidth, newHeight, newOffsetX, newOffsetY, newScale;

      for (final part in parts) {
        final keyValue = part.split(':');
        if (keyValue.length == 2) {
          final key = keyValue[0].trim();
          final value = double.tryParse(keyValue[1].trim());
          if (value != null) {
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
        }
      }

      if (newWidth == null &&
          newHeight == null &&
          newOffsetX == null &&
          newOffsetY == null &&
          newScale == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid clipboard format'),
              duration: Duration(seconds: 1),
            ),
          );
        }
        return;
      }

      setState(() {
        if (newWidth != null) {
          _targetWidth = newWidth;
          _widthController.text = _targetWidth.toStringAsFixed(1);
        }
        if (newHeight != null) {
          _targetHeight = newHeight;
          _heightController.text = _targetHeight.toStringAsFixed(1);
        }
        if (newOffsetX != null) {
          _offsetX = newOffsetX;
          _offsetXController.text = _offsetX.toStringAsFixed(1);
        }
        if (newOffsetY != null) {
          _offsetY = newOffsetY;
          _offsetYController.text = _offsetY.toStringAsFixed(1);
        }
        if (newScale != null) {
          _scalePercent = newScale;
          _scaleController.text = _scalePercent.toStringAsFixed(1);
        }
      });

      _saveSettings();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Values pasted from clipboard'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      Logger.e('Error pasting values', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error pasting values: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    try {
      var settings = await _settingsRepo.getSettingsByKey(_settingsKey);
      if (settings != null) {
        settings.targetWidthMm = _targetWidth;
        settings.targetHeightMm = _targetHeight;
        settings.offsetXMm = _offsetX;
        settings.offsetYMm = _offsetY;
        settings.scalePercent = _scalePercent;
        settings.updatedAt = DateTime.now();
        await _settingsRepo.saveSettings(settings);
      } else {
        await _settingsRepo.saveSettings(
          PrinterSettings(
            key: _settingsKey,
            targetWidthMm: _targetWidth,
            targetHeightMm: _targetHeight,
            offsetXMm: _offsetX,
            offsetYMm: _offsetY,
            scalePercent: _scalePercent,
          ),
        );
      }
    } catch (e) {
      Logger.e('Error saving settings', e);
    }
  }

  Future<void> _savePrinterSelection(String? name) async {
    try {
      await ref
          .read(printerSelectionProvider.notifier)
          .updatePrinter(_selectedLayoutType.name, name);
    } catch (e) {
      Logger.w('Error saving printer', e);
    }
  }

  PaperSizeOption _defaultPaperSize(PrinterLayoutType type) {
    return switch (type) {
      PrinterLayoutType.strip => PaperSizeOption.r4,
      PrinterLayoutType.kolase => PaperSizeOption.r4,
      PrinterLayoutType.majalah => PaperSizeOption.a3,
      PrinterLayoutType.flipbook => PaperSizeOption.r4,
      PrinterLayoutType.thermal => PaperSizeOption.r2,
    };
  }

  Future<void> _onLayoutTypeChanged(PrinterLayoutType type) async {
    if (_selectedLayoutType == type) return;
    final newPaperSize = _defaultPaperSize(type);
    final paperSizeChanged = _selectedPaperSize != newPaperSize;
    setState(() {
      _selectedLayoutType = type;
      _selectedPaperSize = newPaperSize;
    });
    _updateSelectedPrinter();
    if (paperSizeChanged) await _initializePdf();
    await _loadSettings();
  }

  Future<void> _onOrientationChanged(PdfOrientation o) async {
    if (_selectedOrientation == o) return;
    setState(() => _selectedOrientation = o);
    await _initializePdf();
  }

  Future<void> _onPaperSizeChanged(PaperSizeOption p) async {
    if (_selectedPaperSize == p) return;
    setState(() => _selectedPaperSize = p);
    await _initializePdf();
  }

  Future<void> _printTestPage() async {
    if (_selectedPrinter == null || _selectedPdfPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a printer first'),
        ),
      );
      return;
    }

    setState(() => _isPrinting = true);
    try {
      final settings = PrintSettings.fromPath(
        pdfPath: _selectedPdfPath!,
        printerName: _selectedPrinter!,
        copies: 1,
        jobName: 'Printer Test - ${_selectedLayoutType.label}',
        fitToPage: true,
        targetWidthMm: _targetWidth,
        targetHeightMm: _targetHeight,
        offsetXMm: _offsetX,
        offsetYMm: _offsetY,
        scalePercent: _scalePercent,
      );

      final result = await _printWindows.printPDF(settings);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['success'] == true ? 'Print job sent!' : 'Print failed',
            ),
            backgroundColor: result['success'] == true
                ? Colors.green
                : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  String? _getConfiguredPrinter(PrinterLayoutType type) {
    final selectionState = ref.read(printerSelectionProvider).valueOrNull;
    if (selectionState == null) return null;
    return switch (type) {
      PrinterLayoutType.strip => selectionState.stripPrinter,
      PrinterLayoutType.kolase => selectionState.kolasePrinter,
      PrinterLayoutType.majalah => selectionState.majalahPrinter,
      PrinterLayoutType.flipbook => selectionState.flipbookPrinter,
      PrinterLayoutType.thermal => selectionState.thermalPrinter,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        title: Text(
          'Printer Settings',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w500,
            fontSize: 18,
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: _loadPrinters,
            icon: Icon(
              Icons.refresh,
              size: 18,
              color: colorScheme.primary,
            ),
            label: Text(
              'Refresh',
              style: TextStyle(color: colorScheme.primary),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: colorScheme.primary,
                strokeWidth: 2,
              ),
            )
          : isPortrait
          ? _buildPortraitLayout()
          : _buildLandscapeLayout(),
    );
  }

  Widget _buildLandscapeLayout() {
    return Row(
      children: [
        _buildSidebar(),
        Expanded(child: _buildPreviewPanel()),
        SizedBox(width: 340, child: _buildSettingsPanel()),
      ],
    );
  }

  Widget _buildPortraitLayout() {
    return Column(
      children: [
        _buildLayoutTypeSelector(),
        SizedBox(
          height: 220,
          child: _buildCompactPreviewPanel(),
        ),
        Expanded(child: _buildSettingsPanel()),
      ],
    );
  }

  Widget _buildLayoutTypeSelector() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        itemCount: PrinterLayoutType.values.length,
        itemBuilder: (context, index) {
          final type = PrinterLayoutType.values[index];
          final isSelected = _selectedLayoutType == type;
          final configuredPrinter = _getConfiguredPrinter(type);
          final hasConfigured =
              configuredPrinter != null && configuredPrinter.isNotEmpty;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: isSelected
                  ? colorScheme.primaryContainer
                  : colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => _onLayoutTypeChanged(type),
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
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          type.icon,
                          size: 16,
                          color: isSelected
                              ? colorScheme.onPrimary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            type.label,
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: isSelected
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                              fontSize: 13,
                            ),
                          ),
                          if (hasConfigured)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Configured',
                                  style: TextStyle(
                                    color: Colors.green[700],
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
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

  Widget _buildSidebar() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(
          right: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Text(
              'Layout Types',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: PrinterLayoutType.values.length,
              itemBuilder: (context, index) {
                final type = PrinterLayoutType.values[index];
                final isSelected = _selectedLayoutType == type;
                final configuredPrinter = _getConfiguredPrinter(type);

                return _buildSidebarItem(
                  type: type,
                  isSelected: isSelected,
                  configuredPrinter: configuredPrinter,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem({
    required PrinterLayoutType type,
    required bool isSelected,
    required String? configuredPrinter,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasConfigured =
        configuredPrinter != null && configuredPrinter.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: isSelected
            ? colorScheme.primaryContainer
            : colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _onLayoutTypeChanged(type),
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
                    type.icon,
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
                        type.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasConfigured ? configuredPrinter : type.description,
                        style: TextStyle(
                          color: hasConfigured
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
                if (hasConfigured)
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

  Widget _buildPreviewPanel() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.all(24),
      child: Column(
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
                    '${_selectedPaperSize.shortName} \u2022 ${_selectedOrientation == PdfOrientation.portrait ? "Portrait" : "Landscape"}',
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
          Row(
            children: [
              Expanded(child: _buildPreviewOrientationSelector()),
              const SizedBox(width: 12),
              Expanded(child: _buildPreviewPaperSizeDropdown()),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 480),
                decoration: BoxDecoration(
                  color: Colors.grey[850],
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _buildPdfView(compact: false),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactPreviewPanel() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPreviewOrientationSelector(),
                const SizedBox(height: 8),
                _buildPreviewPaperSizeDropdown(),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_selectedPaperSize.shortName} ${_selectedOrientation == PdfOrientation.portrait ? "P" : "L"}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onPrimaryContainer,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[850],
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _buildPdfView(compact: true),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPdfView({required bool compact}) {
    if (_pdfController != null) {
      return PdfView(
        key: ValueKey(
          '${compact ? "compact_" : ""}${_selectedLayoutType.name}_${_selectedPaperSize.shortName}_${_selectedOrientation.name}',
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
              strokeWidth: compact ? 2 : null,
            ),
          ),
          pageLoaderBuilder: (_) => Center(
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: compact ? 2 : null,
            ),
          ),
          errorBuilder: (_, error) => Center(
            child: compact
                ? Icon(Icons.error_outline, color: Colors.red[300], size: 32)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red[300], size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'Error loading PDF',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$error',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
          ),
        ),
      );
    }

    return Center(
      child: CircularProgressIndicator(
        color: compact
            ? Colors.white.withValues(alpha: 0.7)
            : Colors.white,
        strokeWidth: compact ? 2 : null,
      ),
    );
  }

  Widget _buildPreviewOrientationSelector() {
    final isPortrait = _selectedOrientation == PdfOrientation.portrait;
    return Row(
      children: [
        _buildPreviewToggle(
          icon: Icons.stay_current_portrait_rounded,
          label: 'P',
          selected: isPortrait,
          onTap: () => _onOrientationChanged(PdfOrientation.portrait),
        ),
        const SizedBox(width: 6),
        _buildPreviewToggle(
          icon: Icons.stay_current_landscape_rounded,
          label: 'L',
          selected: !isPortrait,
          onTap: () => _onOrientationChanged(PdfOrientation.landscape),
        ),
      ],
    );
  }

  Widget _buildPreviewToggle({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: selected
            ? Colors.white.withAlpha(25)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? Colors.white.withAlpha(60)
                    : Colors.white.withAlpha(20),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: Colors.white.withAlpha(selected ? 230 : 120)),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withAlpha(selected ? 230 : 120),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewPaperSizeDropdown() {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<PaperSizeOption>(
          value: _selectedPaperSize,
          isExpanded: true,
          borderRadius: BorderRadius.circular(8),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          dropdownColor: Colors.grey[850],
          style: TextStyle(
            color: Colors.white.withAlpha(230),
            fontSize: 12,
          ),
          icon: Icon(
            Icons.unfold_more,
            size: 14,
            color: Colors.white.withAlpha(120),
          ),
          items: PaperSizeOption.values.map((p) {
            return DropdownMenuItem(
              value: p,
              child: Text(p.shortName),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) _onPaperSizeChanged(value);
          },
        ),
      ),
    );
  }

  Widget _buildSettingsPanel() {
    final colorScheme = Theme.of(context).colorScheme;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    return Container(
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
                    _selectedLayoutType.icon,
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
                        _selectedLayoutType.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                          fontSize: isPortrait ? 15 : 17,
                        ),
                      ),
                      Text(
                        _selectedLayoutType.description,
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

            // Printer Selection
            _buildFieldLabel('Printer'),
            _buildPrinterDropdown(),
            SizedBox(height: isPortrait ? 16 : 20),

            // Frame Mode (Flipbook only)
            if (_selectedLayoutType == PrinterLayoutType.flipbook) ...[
              _buildFieldLabel('Frame Mode'),
              _buildFrameModeDropdown(),
              SizedBox(height: isPortrait ? 16 : 24),
            ],

            // Calibration
            Row(
              children: [
                _buildFieldLabel('Calibration'),
                const Spacer(),
                Tooltip(
                  message: 'Clear',
                  child: IconButton(
                    onPressed: _clearValues,
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
                    onPressed: _copyValues,
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
                    onPressed: _pasteValues,
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
            _buildCalibrationControls(),

            SizedBox(height: isPortrait ? 20 : 28),

            // Print button
            SizedBox(
              width: double.infinity,
              height: isPortrait ? 42 : 46,
              child: FilledButton.icon(
                onPressed: (_isPrinting || _selectedPrinter == null)
                    ? null
                    : _printTestPage,
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

  Widget _buildPrinterDropdown() {
    final colorScheme = Theme.of(context).colorScheme;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    return Container(
      height: isPortrait ? 40 : 46,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _printers.any((p) => p.name == _selectedPrinter)
              ? _selectedPrinter
              : null,
          hint: Padding(
            padding: EdgeInsets.symmetric(horizontal: isPortrait ? 10 : 14),
            child: Row(
              children: [
                Icon(
                  Icons.print_outlined,
                  size: isPortrait ? 16 : 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                SizedBox(width: isPortrait ? 6 : 10),
                Flexible(
                  child: Text(
                    isPortrait ? 'Select printer' : 'Select a printer',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: isPortrait ? 12 : 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          isExpanded: true,
          borderRadius: BorderRadius.circular(10),
          padding: EdgeInsets.symmetric(horizontal: isPortrait ? 10 : 14),
          dropdownColor: colorScheme.surface,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: isPortrait ? 12 : 14,
          ),
          icon: Icon(
            Icons.unfold_more,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          items: _printers.map((p) {
            return DropdownMenuItem(
              value: p.name,
              child: Row(
                children: [
                  if (!isPortrait) ...[
                    Icon(
                      Icons.print_outlined,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      p.name + (p.isDefault ? ' (Default)' : ''),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() => _selectedPrinter = value);
            _savePrinterSelection(value);
          },
        ),
      ),
    );
  }

  Widget _buildFrameModeDropdown() {
    final colorScheme = Theme.of(context).colorScheme;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final selectionState = ref.watch(printerSelectionProvider).valueOrNull;
    final frameMode = selectionState?.flipbookFrameMode ?? 'f1';

    return Container(
      height: isPortrait ? 40 : 46,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: frameMode,
          isExpanded: true,
          borderRadius: BorderRadius.circular(10),
          padding: EdgeInsets.symmetric(horizontal: isPortrait ? 10 : 14),
          dropdownColor: colorScheme.surface,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: isPortrait ? 12 : 14,
          ),
          icon: Icon(
            Icons.unfold_more,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          items: const [
            DropdownMenuItem(value: 'f1', child: Text('F1 (1 Frame)')),
            DropdownMenuItem(value: 'f2', child: Text('F2 (2 Frame)')),
            DropdownMenuItem(value: 'f3', child: Text('F3 (3 Frame)')),
          ],
          onChanged: (value) {
            if (value != null) {
              ref
                  .read(printerSelectionProvider.notifier)
                  .updateFlipbookFrameMode(value);
            }
          },
        ),
      ),
    );
  }

  Widget _buildCalibrationControls() {
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
          _buildNumberField('Scale', '%', _scaleController, (v) {
            _scalePercent = v.clamp(50.0, 200.0);
            _saveSettings();
          }),
          SizedBox(height: isPortrait ? 8 : 12),
          _buildNumberField('Offset X', 'mm', _offsetXController, (v) {
            _offsetX = v.clamp(-100.0, 100.0);
            _saveSettings();
          }),
          SizedBox(height: isPortrait ? 8 : 12),
          _buildNumberField('Offset Y', 'mm', _offsetYController, (v) {
            _offsetY = v.clamp(-100.0, 100.0);
            _saveSettings();
          }),
          SizedBox(height: isPortrait ? 8 : 12),
          _buildNumberField('Width', 'mm', _widthController, (v) {
            _targetWidth = v.clamp(0.0, 500.0);
            _saveSettings();
          }),
          SizedBox(height: isPortrait ? 8 : 12),
          _buildNumberField('Height', 'mm', _heightController, (v) {
            _targetHeight = v.clamp(0.0, 500.0);
            _saveSettings();
          }),
        ],
      ),
    );
  }

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

  Widget _buildNumberField(
    String label,
    String suffix,
    TextEditingController controller,
    Function(double) onChanged,
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
          child: Container(
            height: isPortrait ? 34 : 38,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                _buildStepButton(Icons.remove_rounded, () {
                  final v =
                      (double.tryParse(controller.text) ?? 0) -
                      (suffix == '%' ? 1 : 0.1);
                  controller.text = v.toStringAsFixed(1);
                  onChanged(v);
                }),
                Expanded(
                  child: TextField(
                    controller: controller,
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
                  padding: EdgeInsets.symmetric(horizontal: isPortrait ? 4 : 8),
                  child: Text(
                    suffix,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: isPortrait ? 10 : 12,
                    ),
                  ),
                ),
                _buildStepButton(Icons.add_rounded, () {
                  final v =
                      (double.tryParse(controller.text) ?? 0) +
                      (suffix == '%' ? 1 : 0.1);
                  controller.text = v.toStringAsFixed(1);
                  onChanged(v);
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepButton(IconData icon, VoidCallback onTap) {
    final colorScheme = Theme.of(context).colorScheme;

    return _HoldableButton(
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

/// A button that triggers repeatedly when held down
class _HoldableButton extends StatefulWidget {
  const _HoldableButton({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_HoldableButton> createState() => _HoldableButtonState();
}

class _HoldableButtonState extends State<_HoldableButton> {
  Timer? _timer;
  bool _isHolding = false;
  int _holdCount = 0;

  void _startHolding() {
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
          onTap: () {},
          child: widget.child,
        ),
      ),
    );
  }
}
