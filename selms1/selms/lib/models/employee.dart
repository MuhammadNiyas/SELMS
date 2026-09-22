// lib/models/employee.dart

/// Some older records may have base_salary stored as a string (e.g. "RM2,000")
/// from before input validation was added. Strip anything that isn't a digit
/// or decimal point and try again, rather than crashing on a hard cast.
num? _parseNum(dynamic value) {
  if (value == null) return null;
  if (value is num) return value;
  if (value is String) {
    final cleaned = value.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return null;
    return num.tryParse(cleaned);
  }
  return null;
}

class Employee {
  Employee({
    required this.employeeId,
    required this.fullName,
    this.gender,
    this.dateOfBirth,
    this.nationality,
    this.icPassportNo,
    this.maritalStatus,
    this.addressLine,
    this.postcode,
    this.state,
    this.personalEmail,
    this.mobileNumber,
    this.emergencyContactName,
    this.emergencyContactNumber,
    this.emergencyContactRelationship,
    this.jobTitle,
    this.department,
    this.lineManager,
    this.hireDate,
    this.confirmationDate,
    this.employmentStatus,
    this.workLocationType,
    this.baseSalary,
    this.equipmentNeeded = const [],
    this.remarks,
    this.workEmail,
    this.onboardingStage,
    this.profileImageUrl,
  });

  final String employeeId;
  final String fullName;
  final String? gender;
  final String? dateOfBirth; // ISO string
  final String? nationality;
  final String? icPassportNo;
  final String? maritalStatus;
  final String? addressLine;
  final String? postcode;
  final String? state;
  final String? personalEmail;
  final String? mobileNumber;
  final String? emergencyContactName;
  final String? emergencyContactNumber;
  final String? emergencyContactRelationship;
  final String? jobTitle;
  final String? department;
  final String? lineManager;
  final String? hireDate; // ISO string
  final String? confirmationDate; // ISO string, optional
  final String? employmentStatus;
  final String? workLocationType;
  final num? baseSalary;
  final List<String> equipmentNeeded;
  final String? remarks;
  final String? workEmail;
  final String? onboardingStage;
  /// Relative path returned by the backend, e.g. "/uploads/EMP-004.jpg".
  /// Callers should prefix with apiBaseUrl to load it.
  final String? profileImageUrl;

  /// Derived pill: Onboarding / Active. (Offboarding not modeled yet.)
  String get statusLabel =>
      (onboardingStage == null || onboardingStage == 'Completed') ? 'Active' : 'Onboarding';

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
        employeeId: j['employee_id'] as String? ?? '',
        fullName: j['full_name'] as String? ?? '',
        gender: j['gender'] as String?,
        dateOfBirth: j['date_of_birth'] as String?,
        nationality: j['nationality'] as String?,
        icPassportNo: j['ic_passport_no'] as String?,
        maritalStatus: j['marital_status'] as String?,
        addressLine: j['address_line'] as String?,
        postcode: j['postcode'] as String?,
        state: j['state'] as String?,
        personalEmail: j['personal_email'] as String?,
        mobileNumber: j['mobile_number'] as String?,
        emergencyContactName: j['emergency_contact_name'] as String?,
        emergencyContactNumber: j['emergency_contact_number'] as String?,
        emergencyContactRelationship: j['emergency_contact_relationship'] as String?,
        jobTitle: j['job_title'] as String?,
        department: j['department'] as String?,
        lineManager: j['line_manager'] as String?,
        hireDate: j['hire_date'] as String?,
        confirmationDate: j['confirmation_date'] as String?,
        employmentStatus: j['employment_status'] as String?,
        workLocationType: j['work_location_type'] as String?,
        baseSalary: _parseNum(j['base_salary']),
        equipmentNeeded: (j['equipment_needed'] as List?)?.map((e) => e.toString()).toList() ?? [],
        remarks: j['remarks'] as String?,
        workEmail: j['work_email'] as String? ?? j['email'] as String?,
        onboardingStage: j['onboarding_stage'] as String?,
        profileImageUrl: j['profile_image_url'] as String?,
      );
}
