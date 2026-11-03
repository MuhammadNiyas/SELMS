// lib/models/equipment.dart

class Equipment {
  Equipment({
    required this.id,
    required this.name,
    required this.type,
    required this.serialNumber,
    required this.status,
    this.brand,
    this.model,
    this.assetTag,
    this.colorMarks,
    this.ram,
    this.storage,
    this.softwareLicenses,
    this.condition,
    this.accessoriesIncluded,
    this.purchaseDate,
    this.purchasePrice,
    this.vendor,
    this.warrantyExpiry,
    this.notes,
    this.photoUrl,
    this.assignedToEmployeeId,
    this.assignedToEmployeeName,
    this.assignedToEmployeeDepartment,
    this.assignedToEmployeePhotoUrl,
    this.assignedDate,
    this.assignmentNotes,
  });

  final String id;
  final String name;
  final String type;
  final String serialNumber;
  final String status; // available | assigned | returned | under_repair | retired | lost

  // Identification (specs live here too — no separate section)
  final String? brand;
  final String? model;
  final String? assetTag;
  final String? colorMarks;
  final String? ram;
  final String? storage;
  final String? softwareLicenses;

  // Condition & status
  final String? condition; // New | Good | Fair | Damaged
  final String? accessoriesIncluded;

  // Purchase & warranty
  final String? purchaseDate;
  final num? purchasePrice;
  final String? vendor;
  final String? warrantyExpiry;

  // Notes & photo
  final String? notes;
  final String? photoUrl;
  final String? assignedToEmployeeId;
  final String? assignedToEmployeeName;
  final String? assignedToEmployeeDepartment;
  final String? assignedToEmployeePhotoUrl;
  final String? assignedDate;
  final String? assignmentNotes;

  factory Equipment.fromJson(Map<String, dynamic> j) => Equipment(
        id: j['_id'] as String,
        name: j['name'] as String,
        type: j['type'] as String,
        serialNumber: j['serial_number'] as String,
        status: j['status'] as String? ?? 'available',
        brand: j['brand'] as String?,
        model: j['model'] as String?,
        assetTag: j['asset_tag'] as String?,
        colorMarks: j['color_marks'] as String?,
        ram: j['ram'] as String?,
        storage: j['storage'] as String?,
        softwareLicenses: j['software_licenses'] as String?,
        condition: j['condition'] as String?,
        accessoriesIncluded: j['accessories_included'] as String?,
        purchaseDate: j['purchase_date'] as String?,
        purchasePrice: j['purchase_price'] as num?,
        vendor: j['vendor'] as String?,
        warrantyExpiry: j['warranty_expiry'] as String?,
        notes: j['notes'] as String?,
        photoUrl: j['photo_url'] as String?,
        assignedToEmployeeId: j['assigned_to_employee_id'] as String?,
        assignedToEmployeeName: j['assigned_to_employee_name'] as String?,
        assignedToEmployeeDepartment: j['assigned_to_employee_department'] as String?,
        assignedToEmployeePhotoUrl: j['assigned_to_employee_photo_url'] as String?,
        assignedDate: j['assigned_date'] as String?,
        assignmentNotes: j['assignment_notes'] as String?,
      );
}

class EquipmentSummary {
  EquipmentSummary({required this.total, required this.available, required this.assigned, required this.returned});

  final int total;
  final int available;
  final int assigned;
  final int returned;

  factory EquipmentSummary.fromJson(Map<String, dynamic> j) => EquipmentSummary(
        total: j['total'] as int? ?? 0,
        available: j['available'] as int? ?? 0,
        assigned: j['assigned'] as int? ?? 0,
        returned: j['returned'] as int? ?? 0,
      );
}
