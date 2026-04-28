/// DTO untuk satu printer yang ditemukan oleh sistem. Bukan entity DB —
/// gabooth_assistant tidak mempersist daftar printer.
class PrinterDevice {
  const PrinterDevice({
    required this.printerName,
    this.printerType,
    this.description,
    this.isDefault = false,
    this.isOnline = true,
  });

  final String printerName;
  final String? printerType;
  final String? description;
  final bool isDefault;
  final bool isOnline;
}
