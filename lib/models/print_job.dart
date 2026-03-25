/// Represents a single print job received by the HTTP print server
class PrintJob {
  final String id;
  final String fileName;
  final String printerName;
  final String? printerType;
  final int copies;
  final DateTime receivedAt;
  final bool success;
  final String? errorMessage;
  final int fileSizeBytes;

  const PrintJob({
    required this.id,
    required this.fileName,
    required this.printerName,
    this.printerType,
    required this.copies,
    required this.receivedAt,
    required this.success,
    this.errorMessage,
    required this.fileSizeBytes,
  });

  String get fileSizeLabel {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
