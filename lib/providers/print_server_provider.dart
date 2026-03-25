import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/print_job.dart';
import '../services/network_discovery_service.dart';
import '../services/print_server_service.dart';

class PrintServerState {
  final bool isRunning;
  final String? localIp;
  final int port;
  final bool discoveryEnabled;
  final List<PrintJob> recentJobs;
  final String? defaultPrinterName;
  final String? defaultPrinterType;

  const PrintServerState({
    this.isRunning = false,
    this.localIp,
    this.port = PrintServerService.defaultPort,
    this.discoveryEnabled = true,
    this.recentJobs = const [],
    this.defaultPrinterName,
    this.defaultPrinterType,
  });

  PrintServerState copyWith({
    bool? isRunning,
    String? localIp,
    int? port,
    bool? discoveryEnabled,
    List<PrintJob>? recentJobs,
    String? defaultPrinterName,
    String? defaultPrinterType,
    bool clearDefaultPrinter = false,
  }) {
    return PrintServerState(
      isRunning: isRunning ?? this.isRunning,
      localIp: localIp ?? this.localIp,
      port: port ?? this.port,
      discoveryEnabled: discoveryEnabled ?? this.discoveryEnabled,
      recentJobs: recentJobs ?? this.recentJobs,
      defaultPrinterName: clearDefaultPrinter ? null : (defaultPrinterName ?? this.defaultPrinterName),
      defaultPrinterType: defaultPrinterType ?? this.defaultPrinterType,
    );
  }

  String? get serverUrl {
    if (localIp == null) return null;
    return 'http://$localIp:$port';
  }
}

class PrintServerNotifier extends AsyncNotifier<PrintServerState> {
  final _serverService = PrintServerService();
  final _discoveryService = NetworkDiscoveryService();

  @override
  Future<PrintServerState> build() async {
    final localIp = await PrintServerService.getLocalIp();
    return PrintServerState(localIp: localIp);
  }

  Future<void> startServer() async {
    final current = state.valueOrNull ?? const PrintServerState();
    final localIp = current.localIp ?? await PrintServerService.getLocalIp();

    state = const AsyncLoading();

    _serverService.onPrintJob = _addJob;

    final success = await _serverService.start(
      port: current.port,
      defaultPrinterName: current.defaultPrinterName,
      defaultPrinterType: current.defaultPrinterType,
    );

    if (success && current.discoveryEnabled && localIp != null) {
      await _discoveryService.start(localIp: localIp, serverPort: current.port);
    }

    state = AsyncData(current.copyWith(
      isRunning: success,
      localIp: localIp,
    ));
  }

  Future<void> stopServer() async {
    await _serverService.stop();
    await _discoveryService.stop();

    final current = state.valueOrNull ?? const PrintServerState();
    state = AsyncData(current.copyWith(isRunning: false));
  }

  Future<void> toggleServer() async {
    final isRunning = state.valueOrNull?.isRunning ?? false;
    if (isRunning) {
      await stopServer();
    } else {
      await startServer();
    }
  }

  void setDefaultPrinter(String? printerName) {
    final current = state.valueOrNull ?? const PrintServerState();
    _serverService.onPrintJob = _addJob;
    state = AsyncData(current.copyWith(
      defaultPrinterName: printerName,
      clearDefaultPrinter: printerName == null,
    ));
    // Update the running server's callback context
    if (current.isRunning) {
      _serverService.onPrintJob = _addJob;
    }
  }

  void setDiscoveryEnabled(bool enabled) async {
    final current = state.valueOrNull ?? const PrintServerState();
    state = AsyncData(current.copyWith(discoveryEnabled: enabled));

    if (current.isRunning) {
      if (enabled && current.localIp != null) {
        await _discoveryService.start(localIp: current.localIp!, serverPort: current.port);
      } else {
        await _discoveryService.stop();
      }
    }
  }

  void _addJob(PrintJob job) {
    final current = state.valueOrNull ?? const PrintServerState();
    final updated = [job, ...current.recentJobs].take(20).toList();
    state = AsyncData(current.copyWith(recentJobs: updated));
  }
}

final printServerProvider =
    AsyncNotifierProvider<PrintServerNotifier, PrintServerState>(
  PrintServerNotifier.new,
);
