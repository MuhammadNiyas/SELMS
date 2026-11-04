// lib/utils/employee_rules.dart
//
// The rules for an employee's details, used by the Add and Edit forms. The
// backend checks the same rules (_employee_field_problem in selms_backend.py).

const _maxBaseSalary = 1000000;
const _minEmployeeAge = 18;

final _nameChars = RegExp(r"^[\p{L}\p{M} @'\-./]+$", unicode: true);
final _hasLetter = RegExp(r'\p{L}', unicode: true);
final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final _phone = RegExp(r'^\+?\d{9,15}$');

String? _emailProblem(String value, String label) =>
    value.length > 254 || !_email.hasMatch(value) ? '$label is not a valid email address.' : null;

String? _phoneProblem(String value, String label) =>
    _phone.hasMatch(value) ? null : '$label must be 9 to 15 digits, with an optional + at the start.';

String? _requiredTextProblem(String value, String label, int limit) {
  if (value.isEmpty) return '$label is required.';
  return value.length > limit ? "$label can't be longer than $limit characters." : null;
}

String? _personNameProblem(String name, String label) {
  if (name.length < 2 || name.length > 100) return '$label must be 2 to 100 characters.';
  if (!_nameChars.hasMatch(name) || !_hasLetter.hasMatch(name)) {
    return "$label can only use letters, spaces and @ ' - . /";
  }
  return null;
}

/// The first rule these details break, or null. Text is compared trimmed.
String? employeeDetailsProblem({
  required String fullName,
  required DateTime? dateOfBirth,
  required String nationality,
  required String icPassport,
  required String personalEmail,
  required String workEmail,
  required String mobile,
  required String emergencyPhone,
  required String postcode,
  required String address,
  required String jobTitle,
  required String lineManager,
  required String emergencyName,
  required String remarks,
  required num? baseSalary,
}) {
  final nameProblem = _personNameProblem(fullName.trim(), 'Full name');
  if (nameProblem != null) return nameProblem;

  final born = dateOfBirth;
  if (born == null) return 'Date of birth is not valid.';
  final now = DateTime.now();
  if (DateTime(born.year, born.month, born.day).isAfter(DateTime(now.year, now.month, now.day))) {
    return "Date of birth can't be in the future.";
  }
  final hadBirthday = now.month > born.month || (now.month == born.month && now.day >= born.day);
  if (now.year - born.year - (hadBirthday ? 0 : 1) < _minEmployeeAge) {
    return 'The employee must be at least $_minEmployeeAge years old.';
  }

  final number = icPassport.trim();
  if (nationality.trim().toLowerCase().startsWith('malaysia')) {
    if (!RegExp(r'^[0-9]{12}$').hasMatch(number)) return 'IC number must be exactly 12 digits.';
  } else if (!RegExp(r'^[A-Za-z0-9]{6,20}$').hasMatch(number)) {
    return 'Passport number must be 6 to 20 letters and numbers.';
  }

  return _emailProblem(personalEmail.trim(), 'Personal email') ??
      _emailProblem(workEmail.trim(), 'Work email') ??
      _phoneProblem(mobile.trim(), 'Mobile number') ??
      _phoneProblem(emergencyPhone.trim(), 'Emergency contact number') ??
      (RegExp(r'^[0-9]{5}$').hasMatch(postcode.trim()) ? null : 'Postcode must be exactly 5 digits.') ??
      _requiredTextProblem(address.trim(), 'Address', 200) ??
      _requiredTextProblem(jobTitle.trim(), 'Job title', 100) ??
      _personNameProblem(lineManager.trim(), 'Line manager') ??
      _personNameProblem(emergencyName.trim(), 'Emergency contact name') ??
      (remarks.trim().length > 500 ? "Remarks can't be longer than 500 characters." : null) ??
      (baseSalary == null
          ? 'Base salary must be a valid number.'
          : (baseSalary > 0 && baseSalary <= _maxBaseSalary)
              ? null
              : 'Base salary must be more than 0 and at most 1,000,000.');
}
