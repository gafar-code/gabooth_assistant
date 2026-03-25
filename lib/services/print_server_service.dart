import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../models/print_job.dart';
import '../models/printer_settings.dart';
import 'logger_service.dart';
import 'printer_service.dart';
import 'printer_settings_repository.dart';

typedef OnPrintJobCallback = void Function(PrintJob job);

class PrintServerService {
  static const int defaultPort = 8899;

  HttpServer? _server;
  OnPrintJobCallback? onPrintJob;

  bool get isRunning => _server != null;

  /// Start the HTTP print server on the given port.
  Future<bool> start({
    int port = defaultPort,
    String? defaultPrinterName,
    String? defaultPrinterType,
  }) async {
    if (_server != null) return true;

    try {
      final router = Router();

      // ── GET /ping ──────────────────────────────────────────────
      router.get('/ping', (Request req) {
        return Response.ok(
          jsonEncode({'status': 'ok', 'timestamp': DateTime.now().toIso8601String()}),
          headers: _jsonHeaders,
        );
      });

      // ── GET /status ────────────────────────────────────────────
      router.get('/status', (Request req) {
        return Response.ok(
          jsonEncode({
            'app': 'gabooth_assistant',
            'version': '1.0.0',
            'status': 'running',
            'port': port,
          }),
          headers: _jsonHeaders,
        );
      });

      // ── GET /printers ──────────────────────────────────────────
      router.get('/printers', (Request req) async {
        try {
          final printers = await PrinterService.instance.getAvailablePrinters();
          return Response.ok(
            jsonEncode({
              'printers': printers
                  .map((p) => {
                        'name': p.printerName,
                        'isDefault': p.isDefault,
                        'isOnline': p.isOnline,
                        'type': p.printerType,
                      })
                  .toList(),
            }),
            headers: _jsonHeaders,
          );
        } catch (e) {
          return Response.internalServerError(
            body: jsonEncode({'error': e.toString()}),
            headers: _jsonHeaders,
          );
        }
      });

      // ── POST /print ────────────────────────────────────────────
      // Client sends:
      //   Content-Type: application/octet-stream  (raw PDF bytes in body)
      //   Headers (all optional):
      //     X-Printer-Name  : specific printer name
      //     X-Printer-Type  : 'strip'|'kolase'|'majalah'|'flipbook'|'thermal'
      //     X-Copies        : integer (default 1)
      //     X-Job-Name      : display name for the job
      //     X-File-Name     : original filename
      router.post('/print', (Request req) async {
        try {
          // Read PDF bytes
          final bytes = await req.read().fold<List<int>>(
            [],
            (acc, chunk) => acc..addAll(chunk),
          );

          if (bytes.isEmpty) {
            return Response(400,
                body: jsonEncode({'success': false, 'message': 'Empty body — send PDF bytes'}),
                headers: _jsonHeaders);
          }

          // Parse request metadata from headers
          final headers = req.headers;
          final requestedPrinterName = headers['x-printer-name'];
          final printerType = headers['x-printer-type'] ?? defaultPrinterType;
          final copies = int.tryParse(headers['x-copies'] ?? '1') ?? 1;
          final jobName = headers['x-job-name'] ?? 'Remote Print';
          final fileName = headers['x-file-name'] ?? 'document.pdf';

          // Resolve printer name
          final printerName = requestedPrinterName ?? defaultPrinterName;
          if (printerName == null || printerName.isEmpty) {
            return Response(400,
                body: jsonEncode({
                  'success': false,
                  'message': 'No printer configured. Set X-Printer-Name header or configure default printer in Gabooth Assistant.',
                }),
                headers: _jsonHeaders);
          }

          // Load calibration settings for printer type
          PrinterSettings? printerSettings;
          if (printerType != null && printerType.isNotEmpty) {
            printerSettings = await PrinterSettingsRepository().getSettingsByType(printerType);
          }
          printerSettings ??= await PrinterSettingsRepository().getDefaultSettings();

          Logger.i('[SERVER] Print job received: $fileName → $printerName ($printerType) ×$copies');

          // Execute print
          final success = await PrinterService.instance.printDocument(
            printerName: printerName,
            documentData: Uint8List.fromList(bytes),
            jobName: jobName,
            copies: copies,
            printerSettings: printerSettings,
            printerType: printerType,
          );

          final job = PrintJob(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            fileName: fileName,
            printerName: printerName,
            printerType: printerType,
            copies: copies,
            receivedAt: DateTime.now(),
            success: success,
            errorMessage: success ? null : 'Print failed',
            fileSizeBytes: bytes.length,
          );

          onPrintJob?.call(job);

          Logger.i('[SERVER] Print job result: ${success ? "success" : "failed"}');

          return Response.ok(
            jsonEncode({
              'success': success,
              'message': success ? 'Print job queued successfully' : 'Print failed',
              'job_id': job.id,
              'printer': printerName,
              'copies': copies,
            }),
            headers: _jsonHeaders,
          );
        } catch (e, st) {
          Logger.e('[SERVER] Error handling /print', e, st);
          return Response.internalServerError(
            body: jsonEncode({'success': false, 'message': e.toString()}),
            headers: _jsonHeaders,
          );
        }
      });

      // 404 fallback
      final handler = const Pipeline()
          .addMiddleware(_corsMiddleware())
          .addHandler(router.call);

      _server = await shelf_io.serve(
        handler,
        InternetAddress.anyIPv4,
        port,
        shared: false,
      );
      _server!.autoCompress = true;

      Logger.i('[SERVER] Print server started on port $port');
      return true;
    } catch (e, st) {
      Logger.e('[SERVER] Failed to start server', e, st);
      _server = null;
      return false;
    }
  }

  /// Stop the HTTP print server.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    Logger.i('[SERVER] Print server stopped');
  }

  /// Get the local IPv4 address (first non-loopback interface).
  static Future<String?> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (e) {
      Logger.w('[SERVER] Could not determine local IP: $e');
    }
    return null;
  }

  static const Map<String, Object> _jsonHeaders = {
    'content-type': 'application/json; charset=utf-8',
  };

  /// CORS middleware so browsers / web clients can call the server.
  static Middleware _corsMiddleware() {
    return (Handler inner) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders);
        }
        final response = await inner(request);
        return response.change(headers: _corsHeaders);
      };
    };
  }

  static const Map<String, String> _corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, X-Printer-Name, X-Printer-Type, X-Copies, X-Job-Name, X-File-Name',
  };
}

