import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/print_job.dart';
import '../providers/print_server_provider.dart';

import 'printer_settings_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(printServerProvider.notifier).startServer();
    });
  }

  @override
  Widget build(BuildContext context) {
    final serverAsync = ref.watch(printServerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        title: Text(
          'Gabooth Assistant',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        actions: [
          serverAsync.when(
            data: (state) => _ServerToggleButton(state: state),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (e, s) => const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PrinterSettingsScreen(),
                ),
              );
            },
            icon: const Icon(Icons.settings_rounded),
            tooltip: 'Printer Settings',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: serverAsync.when(
        data: (state) => _DashboardBody(state: state),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

// --- Server Toggle Button ---

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
        backgroundColor:
            isRunning ? colorScheme.errorContainer : colorScheme.primaryContainer,
        foregroundColor: isRunning
            ? colorScheme.onErrorContainer
            : colorScheme.onPrimaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }
}

// --- Dashboard Body (responsive layout) ---

class _DashboardBody extends StatelessWidget {
  final PrintServerState state;
  const _DashboardBody({required this.state});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;

        if (isWide) {
          // Landscape / desktop: side-by-side
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 280,
                  child: _ConnectionPanel(state: state),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _PrintQueuePanel(jobs: state.recentJobs),
                ),
              ],
            ),
          );
        }

        // Portrait / narrow: stacked
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _ConnectionPanelCompact(state: state),
              const SizedBox(height: 16),
              Expanded(
                child: _PrintQueuePanel(jobs: state.recentJobs),
              ),
            ],
          ),
        );
      },
    );
  }
}

// --- Compact Connection Panel (portrait) ---

class _ConnectionPanelCompact extends StatelessWidget {
  final PrintServerState state;
  const _ConnectionPanelCompact({required this.state});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final serverUrl = state.serverUrl;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // QR Code (smaller)
          if (state.isRunning && serverUrl != null)
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: QrImageView(
                data: serverUrl,
                version: QrVersions.auto,
                size: 80,
                backgroundColor: Colors.white,
              ),
            )
          else
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Icon(
                Icons.qr_code_2_rounded,
                size: 40,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              ),
            ),
          const SizedBox(width: 16),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusBadge(isRunning: state.isRunning),
                const SizedBox(height: 8),
                Text(
                  state.localIp ?? 'Not detected',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    color: colorScheme.onSurface,
                  ),
                ),
                Text(
                  'Port ${state.port}',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (serverUrl != null) ...[
                  const SizedBox(height: 8),
                  _CopyableUrl(url: serverUrl),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Left Panel: Connection ---

class _ConnectionPanel extends StatelessWidget {
  final PrintServerState state;
  const _ConnectionPanel({required this.state});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final serverUrl = state.serverUrl;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Status badge
                  _StatusBadge(isRunning: state.isRunning),
                  const SizedBox(height: 24),

                  // QR Code
                  _QrSection(state: state),
                  const SizedBox(height: 24),

                  // IP Address
                  Text(
                    state.localIp ?? 'Not detected',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      color: colorScheme.onSurface,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Port ${state.port}',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // URL chip (copyable)
                  if (serverUrl != null)
                    _CopyableUrl(url: serverUrl),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Status Badge ---

class _StatusBadge extends StatelessWidget {
  final bool isRunning;
  const _StatusBadge({required this.isRunning});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isRunning
            ? Colors.green.withValues(alpha: 0.12)
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isRunning ? Colors.green : Colors.grey,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isRunning ? 'Server Running' : 'Server Stopped',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isRunning ? Colors.green[700] : colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// --- QR Code Section ---

class _QrSection extends StatelessWidget {
  final PrintServerState state;
  const _QrSection({required this.state});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final serverUrl = state.serverUrl;

    if (state.isRunning && serverUrl != null) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: QrImageView(
          data: serverUrl,
          version: QrVersions.auto,
          size: 160,
          backgroundColor: Colors.white,
        ),
      );
    }

    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant, width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.qr_code_2_rounded,
            size: 56,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 8),
          Text(
            'Start server to\nshow QR code',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Copyable URL Chip ---

class _CopyableUrl extends StatelessWidget {
  final String url;
  const _CopyableUrl({required this.url});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: url));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('URL copied to clipboard'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link_rounded, size: 14, color: colorScheme.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                url,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.primary,
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.copy_rounded, size: 13, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }
}

// --- Print Queue Panel ---

class _PrintQueuePanel extends StatelessWidget {
  final List<PrintJob> jobs;
  const _PrintQueuePanel({required this.jobs});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                Icon(
                  Icons.queue_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  'Print Queue',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 8),
                if (jobs.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${jobs.length}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          // Jobs List
          Expanded(
            child: jobs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 44,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Waiting for print jobs...',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: jobs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (_, i) => _JobTile(job: jobs[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

// --- Job Tile ---

class _JobTile extends StatelessWidget {
  final PrintJob job;
  const _JobTile({required this.job});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final h = job.receivedAt.hour.toString().padLeft(2, '0');
    final m = job.receivedAt.minute.toString().padLeft(2, '0');
    final s = job.receivedAt.second.toString().padLeft(2, '0');
    final timeStr = '$h:$m:$s';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
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
                  '${job.printerName}${job.printerType != null ? ' \u00b7 ${job.printerType}' : ''} \u00b7 \u00d7${job.copies} \u00b7 ${job.fileSizeLabel}',
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
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
