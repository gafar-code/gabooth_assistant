import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../models/print_job.dart';
import 'logger_service.dart';
import 'printer_calibration_repository.dart';
import 'printer_service.dart';

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
      //   Headers:
      //     X-Printer-Name      : nama printer (wajib, atau pakai default)
      //     X-Paper-Width-Mm    : lebar kertas mm — diteruskan ke DEVMODE
      //     X-Paper-Height-Mm   : tinggi kertas mm — diteruskan ke DEVMODE
      //     X-Printer-Type      : metadata kategori (untuk tampilan saja)
      //     X-Copies            : integer (default 1)
      //     X-Job-Name          : display name untuk antrian print
      //     X-File-Name         : nama file asli
      //
      // Calibration headers (X-Target-*, X-Offset-*, X-Scale-Percent) DI-LOG
      // saja untuk debug. Nilai sebenarnya yang dipakai diambil dari local
      // PrinterCalibrationRepository, di-lookup pakai printer name.
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
          final paperWidthMm =
              double.tryParse(headers['x-paper-width-mm'] ?? '') ?? 0.0;
          final paperHeightMm =
              double.tryParse(headers['x-paper-height-mm'] ?? '') ?? 0.0;

          // Client may still send calibration headers, but we ignore the
          // values — they're parsed only so we can log them for debugging.
          final clientTargetWidthMm =
              double.tryParse(headers['x-target-width-mm'] ?? '') ?? 0.0;
          final clientTargetHeightMm =
              double.tryParse(headers['x-target-height-mm'] ?? '') ?? 0.0;
          final clientOffsetXMm =
              double.tryParse(headers['x-offset-x-mm'] ?? '') ?? 0.0;
          final clientOffsetYMm =
              double.tryParse(headers['x-offset-y-mm'] ?? '') ?? 0.0;
          final clientScalePercent =
              double.tryParse(headers['x-scale-percent'] ?? '') ?? 100.0;

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

          // Local calibration is keyed by printer name. Missing entry =
          // PrinterCalibration.zero() (no-op = old default behavior).
          final localCal =
              PrinterCalibrationRepository.instance.getSync(printerName);

          Logger.i(
            '[SERVER] Print job received: $fileName → $printerName '
            '($printerType) $paperWidthMm×${paperHeightMm}mm ×$copies '
            'client_calibration=target=${clientTargetWidthMm}x${clientTargetHeightMm}mm '
            'offset=($clientOffsetXMm,$clientOffsetYMm)mm scale=$clientScalePercent% '
            '[IGNORED] | local_calibration=$localCal',
          );

          // Execute print — paper size dari client, kalibrasi dari local repo.
          final success = await PrinterService.instance.printDocument(
            printerName: printerName,
            documentData: Uint8List.fromList(bytes),
            jobName: jobName,
            copies: copies,
            paperWidthMm: paperWidthMm,
            paperHeightMm: paperHeightMm,
            targetWidthMm: localCal.targetWidthMm,
            targetHeightMm: localCal.targetHeightMm,
            offsetXMm: localCal.offsetXMm,
            offsetYMm: localCal.offsetYMm,
            scalePercent: localCal.scalePercent,
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

      // Open Windows Firewall for server port so other devices can connect
      if (Platform.isWindows) {
        await _ensureFirewallRules(port);
      }

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

  /// Get the local IPv4 address, preferring real LAN adapters over virtual ones.
  ///
  /// Skips virtual adapters (Hyper-V, WSL, VMware, VirtualBox, Docker, etc.)
  /// and prefers common LAN prefixes (192.168.x.x, 10.x.x.x).
  static Future<String?> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      // Names that indicate virtual/non-physical adapters
      final virtualPatterns = RegExp(
        r'(hyper-v|vethernet|wsl|vmware|vmnet|virtualbox|vbox|docker|br-|virbr)',
        caseSensitive: false,
      );

      String? fallback;

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          final ip = addr.address;
          final name = iface.name;

          // Skip virtual adapters
          if (virtualPatterns.hasMatch(name)) {
            Logger.d('[SERVER] Skipping virtual interface: $name ($ip)');
            continue;
          }

          // Prefer typical LAN ranges: 192.168.x.x or 10.x.x.x
          if (ip.startsWith('192.168.') || ip.startsWith('10.')) {
            Logger.i('[SERVER] Selected LAN IP: $ip ($name)');
            return ip;
          }

          // Keep first non-virtual as fallback
          fallback ??= ip;
        }
      }

      if (fallback != null) {
        Logger.i('[SERVER] Using fallback IP: $fallback');
      }
      return fallback;
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
    'Access-Control-Allow-Headers': 'Content-Type, X-Printer-Name, X-Printer-Type, X-Copies, X-Job-Name, X-File-Name, X-Paper-Width-Mm, X-Paper-Height-Mm',
  };

  /// Add Windows Firewall inbound rules for the HTTP server (TCP) and
  /// UDP discovery broadcast so other devices on the LAN can reach us.
  static Future<void> _ensureFirewallRules(int port) async {
    const tcpRuleName = 'Gabooth Assistant Print Server (TCP)';
    const udpRuleName = 'Gabooth Assistant Discovery (UDP)';
    const udpPort = 8765;

    try {
      // Check if TCP rule already exists
      final tcpCheck = await Process.run('netsh', [
        'advfirewall', 'firewall', 'show', 'rule',
        'name=$tcpRuleName',
      ]);

      if (tcpCheck.exitCode != 0 ||
          !(tcpCheck.stdout as String).contains(tcpRuleName)) {
        await Process.run('netsh', [
          'advfirewall', 'firewall', 'add', 'rule',
          'name=$tcpRuleName',
          'dir=in', 'action=allow', 'protocol=TCP',
          'localport=$port',
          'profile=private,domain',
        ]);
        Logger.i('[SERVER] Firewall rule added: TCP port $port');
      }

      // Check if UDP rule already exists
      final udpCheck = await Process.run('netsh', [
        'advfirewall', 'firewall', 'show', 'rule',
        'name=$udpRuleName',
      ]);

      if (udpCheck.exitCode != 0 ||
          !(udpCheck.stdout as String).contains(udpRuleName)) {
        await Process.run('netsh', [
          'advfirewall', 'firewall', 'add', 'rule',
          'name=$udpRuleName',
          'dir=in', 'action=allow', 'protocol=UDP',
          'localport=$udpPort',
          'profile=private,domain',
        ]);
        Logger.i('[SERVER] Firewall rule added: UDP port $udpPort');
      }
    } catch (e) {
      Logger.w('[SERVER] Could not configure firewall (may need admin): $e');
    }
  }
}

