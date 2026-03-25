import 'package:objectbox/objectbox.dart';

@Entity()
class PrinterDevice {
  @Id()
  int id = 0;

  String printerName;
  String? printerType; // e.g., "PDF", "Inkjet", "LaserJet", etc.
  String? description;
  bool isDefault;
  bool isOnline;

  @Property(type: PropertyType.date)
  DateTime lastDetected;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  @Property(type: PropertyType.date)
  DateTime updatedAt;

  PrinterDevice({
    required this.printerName,
    this.printerType,
    this.description,
    this.isDefault = false,
    this.isOnline = true,
    DateTime? lastDetected,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : lastDetected = lastDetected ?? DateTime.now(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();
}
