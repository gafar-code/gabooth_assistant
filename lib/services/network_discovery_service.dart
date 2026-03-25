import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'logger_service.dart';

/// Broadcasts server presence via UDP so clients on the same LAN can
/// auto-discover gabooth_assistant without entering the IP manually.
///
/// Broadcast format (JSON, UTF-8):
/// {
///   "app": "gabooth_assistant",
///   "ip": "192.168.x.x",
///   "port": 8899,
///   "name": "Gabooth Print Server"
/// }
///
/// Clients should listen on UDP port 8765 for these broadcasts.
class NetworkDiscoveryService {
  static const int discoveryPort = 8765;
  static const Duration broadcastInterval = Duration(seconds: 3);

  RawDatagramSocket? _socket;
  Timer? _timer;

  bool get isRunning => _socket != null;

  /// Start broadcasting server presence.
  Future<bool> start({required String localIp, required int serverPort}) async {
    if (_socket != null) return true;

    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _socket!.broadcastEnabled = true;

      final payload = jsonEncode({
        'app': 'gabooth_assistant',
        'ip': localIp,
        'port': serverPort,
        'name': 'Gabooth Print Server',
      });
      final data = utf8.encode(payload);

      _timer = Timer.periodic(broadcastInterval, (_) {
        try {
          _socket?.send(data, InternetAddress('255.255.255.255'), discoveryPort);
        } catch (e) {
          Logger.w('[DISCOVERY] Broadcast error: $e');
        }
      });

      // Send the first broadcast immediately
      _socket!.send(data, InternetAddress('255.255.255.255'), discoveryPort);

      Logger.i('[DISCOVERY] Broadcasting on UDP port $discoveryPort every ${broadcastInterval.inSeconds}s');
      return true;
    } catch (e) {
      Logger.e('[DISCOVERY] Failed to start broadcast', e);
      _socket = null;
      return false;
    }
  }

  /// Stop broadcasting.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
    Logger.i('[DISCOVERY] Discovery broadcast stopped');
  }
}
