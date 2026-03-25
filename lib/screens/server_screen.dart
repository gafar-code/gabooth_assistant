import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/print_job.dart';
import '../providers/print_server_provider.dart';
import '../providers/printer_providers.dart';

class ServerScreen extends ConsumerWidget {
  const ServerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverAsync = ref.watch(printServerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        title: Text(
          'Print Server',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w500,
            fontSize: 18,
          ),
        ),
        actions: [
          serverAsync.when(
            data: (state) => _ServerToggleButton(state: state),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
            error: (e, s) => const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: serverAsync.when(
        data: (state) => _ServerBody(state: state),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

// ─── Toggle Button in AppBar ─────────────────────────────────────────────────

class _ServerToggleButton extends ConsumerWidget {
  final PrintServerState state;
  const _ServerToggleButton({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isRunning = state.isRunning;

    return FilledButton.icon(
      onPressed: () => ref.read(printServerProvider.notifier).toggleServer(),
      icon: Icon(
        isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
        size: 18,
      ),
      label: Text(isRunning ? 'Stop' : 'Start'),
      style: FilledButton.styleFrom(
        backgroundColor: isRunning ? colorScheme.errorContainer : colorScheme.primaryContainer,
        foregroundColor: isRunning ? colorScheme.onErrorContainer : colorScheme.onPrimaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }
}

// ─── Main Body ────────────────────────────────────────────────────────────────

class _ServerBody extends ConsumerWidget {
  final PrintServerState state;
  const _ServerBody({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        // Top panel: QR + Info
        Expanded(
          flex: 5,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // QR Code panel
              SizedBox(
                width: 280,
                child: _QrPanel(state: state),
              ),
              // Info + Settings panel
              Expanded(
                child: _InfoPanel(state: state),
              ),
            ],
          ),
        ),
        // Divider
        const Divider(height: 1),
        // Jobs panel
        Expanded(
          flex: 4,
          child: _JobsPanel(jobs: state.recentJobs),
        ),
      ],
    );
  }
}

// ─── QR Code Panel ────────────────────────────────────────────────────────────

class _QrPanel extends StatelessWidget {
  final PrintServerState state;
  const _QrPanel({required this.state});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final serverUrl = state.serverUrl;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(
          right: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Status indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: state.isRunning ? Colors.green : Colors.grey,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                state.isRunning ? 'Server Running' : 'Server Stopped',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: state.isRunning
                      ? Colors.green[700]
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // QR Code
          if (state.isRunning && serverUrl != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: QrImageView(
                data: serverUrl,
                version: QrVersions.auto,
                size: 160,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Scan to connect',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              serverUrl,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colorScheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
          ] else ...[
            Container(
              width: 184,
              height: 184,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outlineVariant,
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.qr_code_2_rounded,
                    size: 64,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start server to\nshow QR code',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Info & Settings Panel ────────────────────────────────────────────────────

class _InfoPanel extends ConsumerWidget {
  final PrintServerState state;
  const _InfoPanel({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final serverUrl = state.serverUrl;
    final printersAsync = ref.watch(availablePrintersProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Connection Info ─────────────────────────────────────
          _SectionLabel('Connection Info'),
          const SizedBox(height: 12),
          _InfoRow(
            label: 'IP Address',
            value: state.localIp ?? 'Not detected',
            icon: Icons.wifi_rounded,
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Port',
            value: '${state.port}',
            icon: Icons.electrical_services_rounded,
          ),
          const SizedBox(height: 8),
          if (serverUrl != null)
            _InfoRow(
              label: 'URL',
              value: serverUrl,
              icon: Icons.link_rounded,
              copyable: true,
            ),
          const SizedBox(height: 24),

          // ── Default Printer ─────────────────────────────────────
          _SectionLabel('Default Printer'),
          const SizedBox(height: 12),
          printersAsync.when(
            data: (printers) => _PrinterDropdown(
              printers: printers.map((p) => p.printerName).toList(),
              selected: state.defaultPrinterName,
              onChanged: (name) =>
                  ref.read(printServerProvider.notifier).setDefaultPrinter(name),
            ),
            loading: () => const SizedBox(height: 46, child: Center(child: LinearProgressIndicator())),
            error: (e, _) => Text('Error loading printers: $e', style: const TextStyle(color: Colors.red)),
          ),
          const SizedBox(height: 8),
          Text(
            'Client dapat menentukan printer via header X-Printer-Name.\nJika tidak ditentukan, printer ini yang digunakan.',
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // ── Auto-Discovery ──────────────────────────────────────
          _SectionLabel('Auto-Discovery'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: SwitchListTile(
              title: const Text('UDP Broadcast', style: TextStyle(fontSize: 14)),
              subtitle: Text(
                'Broadcast ke UDP port ${NetworkDiscoveryServiceConstants.discoveryPort} setiap 3 detik',
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
              value: state.discoveryEnabled,
              onChanged: (v) =>
                  ref.read(printServerProvider.notifier).setDiscoveryEnabled(v),
              dense: true,
            ),
          ),
          const SizedBox(height: 16),

          // ── API Reference ───────────────────────────────────────
          _SectionLabel('API Reference'),
          const SizedBox(height: 8),
          _ApiReference(baseUrl: serverUrl ?? 'http://{ip}:${state.port}'),
        ],
      ),
    );
  }
}

// ─── API Reference Widget ─────────────────────────────────────────────────────

class _ApiReference extends StatelessWidget {
  final String baseUrl;
  const _ApiReference({required this.baseUrl});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ApiEndpoint('GET', '$baseUrl/ping', 'Health check'),
          const SizedBox(height: 6),
          _ApiEndpoint('GET', '$baseUrl/printers', 'List printers'),
          const SizedBox(height: 6),
          _ApiEndpoint('POST', '$baseUrl/print', 'Send PDF to print'),
          const SizedBox(height: 8),
          Text(
            'POST /print headers:\n  X-Printer-Name  (optional)\n  X-Printer-Type  (strip|kolase|majalah|flipbook|thermal)\n  X-Copies        (default: 1)\n  X-Job-Name      (optional)\n  X-File-Name     (optional)\nBody: raw PDF bytes (Content-Type: application/octet-stream)',
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ApiEndpoint extends StatelessWidget {
  final String method;
  final String url;
  final String description;
  const _ApiEndpoint(this.method, this.url, this.description);

  @override
  Widget build(BuildContext context) {
    final methodColor = method == 'GET' ? Colors.blue : Colors.orange;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: methodColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            method,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: methodColor,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            url,
            style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          description,
          style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ─── Print Jobs Panel ─────────────────────────────────────────────────────────

class _JobsPanel extends StatelessWidget {
  final List<PrintJob> jobs;
  const _JobsPanel({required this.jobs});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Row(
            children: [
              _SectionLabel('Recent Print Jobs'),
              const Spacer(),
              if (jobs.isNotEmpty)
                Text(
                  '${jobs.length} job${jobs.length > 1 ? 's' : ''}',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
        Expanded(
          child: jobs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 40,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No print jobs yet',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: jobs.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 4),
                  itemBuilder: (_, i) => _JobTile(job: jobs[i], index: jobs.length - i),
                ),
        ),
      ],
    );
  }
}

class _JobTile extends StatelessWidget {
  final PrintJob job;
  final int index;
  const _JobTile({required this.job, required this.index});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final timeStr = _formatTime(job.receivedAt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          // Status icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: job.success
                  ? Colors.green.withValues(alpha: 0.12)
                  : colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              job.success ? Icons.check_rounded : Icons.error_outline_rounded,
              size: 18,
              color: job.success ? Colors.green[700] : colorScheme.error,
            ),
          ),
          const SizedBox(width: 12),
          // Job info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.fileName,
                  style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${job.printerName}${job.printerType != null ? ' · ${job.printerType}' : ''} · ×${job.copies} · ${job.fileSizeLabel}',
                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Time
          Text(
            timeStr,
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool copyable;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.icon,
    this.copyable = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colorScheme.primary),
          const SizedBox(width: 10),
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (copyable)
            IconButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copied to clipboard'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              icon: Icon(Icons.copy, size: 16, color: colorScheme.primary),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }
}

class _PrinterDropdown extends StatelessWidget {
  final List<String> printers;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _PrinterDropdown({
    required this.printers,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final validSelected = printers.contains(selected) ? selected : null;

    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: validSelected,
          hint: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(Icons.print_outlined, size: 18, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Text(
                  'Select default printer',
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
                ),
              ],
            ),
          ),
          isExpanded: true,
          borderRadius: BorderRadius.circular(10),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          dropdownColor: colorScheme.surface,
          style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
          icon: Icon(Icons.unfold_more, size: 16, color: colorScheme.onSurfaceVariant),
          items: printers.map((name) {
            return DropdownMenuItem(
              value: name,
              child: Row(
                children: [
                  Icon(Icons.print_outlined, size: 18, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(name, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// Expose the constant so _InfoPanel can reference it
class NetworkDiscoveryServiceConstants {
  static const int discoveryPort = 8765;
}
