// lib/services/api_client.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/employee.dart';
import '../models/equipment.dart';
import '../models/employee_self_service.dart';
import '../models/chat.dart';
import '../models/message.dart';

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({required this.baseUrl, required this.hrToken});

  final String baseUrl;
  final String hrToken;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $hrToken',
      };

  Future<List<Employee>> listEmployees({
    String? query,
    String? department,
    String? employmentStatus,
    String? workLocationType,
  }) async {
    final params = <String, String>{};
    if (query != null && query.trim().isNotEmpty) params['q'] = query.trim();
    if (department != null && department.isNotEmpty) params['department'] = department;
    if (employmentStatus != null && employmentStatus.isNotEmpty) {
      params['employment_status'] = employmentStatus;
    }
    if (workLocationType != null && workLocationType.isNotEmpty) {
      params['work_location_type'] = workLocationType;
    }

    final uri = Uri.parse('$baseUrl/api/employees').replace(queryParameters: params);
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (data['employees'] as List).cast<Map<String, dynamic>>();
    return list.map(Employee.fromJson).toList();
  }

  Future<Employee> getEmployee(String employeeId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/employees/$employeeId'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return Employee.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<String> createEmployee(Map<String, dynamic> body) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/employees'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (res.statusCode != 201) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['employee_id'] as String;
  }

  /// Uploads/replaces the employee's profile photo. Takes raw PNG bytes —
  /// the crop dialog in ProfilePhotoField already renders exactly what
  /// should be saved, so no XFile/file-path handling is needed here.
  Future<String> uploadEmployeePhoto(String employeeId, List<int> photoBytes) async {
    final uri = Uri.parse('$baseUrl/api/employees/$employeeId/photo');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $hrToken';
    request.files.add(
      http.MultipartFile.fromBytes('photo', photoBytes, filename: '$employeeId.png'),
    );

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['profile_image_url'] as String;
  }

  /// Deletes the employee's profile photo on the server, so it disappears
  /// everywhere (the record's photo field is cleared and the file removed).
  Future<void> removeEmployeePhoto(String employeeId) async {
    final res = await http.delete(Uri.parse('$baseUrl/api/employees/$employeeId/photo'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  /// Same, for the signed-in employee's own photo.
  Future<void> removeMyPhoto() async {
    final res = await http.delete(Uri.parse('$baseUrl/api/employee/me/photo'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  /// Saves HR's edits. When the body asks for reset_password, returns the new
  /// temporary password (shown once to HR to pass on); otherwise null.
  Future<String?> updateEmployee(String employeeId, Map<String, dynamic> body) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/employees/$employeeId'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return (jsonDecode(res.body) as Map<String, dynamic>)['temporary_password'] as String?;
  }

  Future<List<Map<String, dynamic>>> onboardingCandidates() async {
    final res = await http.get(Uri.parse('$baseUrl/api/onboarding/candidates'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['candidates'] as List).cast<Map<String, dynamic>>();
  }

  /// Bird's-eye view of everyone currently onboarding, with real progress
  /// — each entry has employee_id, full_name, department, job_title,
  /// started_at, progress_percent.
  Future<List<Map<String, dynamic>>> onboardingActiveList() async {
    final res = await http.get(Uri.parse('$baseUrl/api/onboarding/active'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['employees'] as List).cast<Map<String, dynamic>>();
  }

  /// Everyone currently onboarding or offboarding, flattened into one list
  /// for the Lifecycle Insights tab. Returns {summary: {...counts}, records:
  /// [{employee_id, full_name, department, process, progress_percent,
  /// steps, current_step, status, status_reason, ...}]}.
  Future<Map<String, dynamic>> lifecycleOverview() async {
    final res = await http.get(Uri.parse('$baseUrl/api/lifecycle/overview'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// One-click automation: drafts the welcome email, then runs each
  /// remaining step only if that step's node is still present in this
  /// employee's own flow diagram (see onboarding_auto_start on the
  /// backend — the diagram is a real on/off switch, not decoration).
  /// Does not send the email — the caller still shows [subject]/[body]
  /// for review before calling sendOnboardingEmail.
  Future<({
    String subject,
    String body,
    Map<String, dynamic>? orientation,
    bool scheduleEnabled,
    bool itNotified,
    bool emailSent,
    String? meetingWarning,
    String? currentStep,
  })> autoStartOnboarding(String employeeId, {String mode = 'in_person'}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/onboarding/$employeeId/auto-start'),
      headers: _headers,
      body: jsonEncode({'mode': mode}),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (
      subject: data['subject'] as String,
      body: data['body'] as String,
      orientation: data['orientation'] as Map<String, dynamic>?,
      scheduleEnabled: data['schedule_enabled'] as bool? ?? true,
      itNotified: data['it_notified'] as bool? ?? false,
      emailSent: data['email_sent'] as bool? ?? false,
      meetingWarning: data['meeting_warning'] as String?,
      currentStep: data['current_step'] as String?,
    );
  }

  /// Where this employee is in their onboarding flow - one entry per step:
  /// {id, label, kind: auto|it|hr, state: done|current|upcoming, hint}.
  Future<List<Map<String, dynamic>>> getOnboardingRun(String employeeId) async {
    final res = await http.get(Uri.parse('$baseUrl/api/onboarding/$employeeId/run'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return ((jsonDecode(res.body) as Map<String, dynamic>)['steps'] as List).cast<Map<String, dynamic>>();
  }

  /// HR ticking off the current step when it's one only a person can finish.
  Future<void> completeOnboardingStep(String employeeId, String stepId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/onboarding/$employeeId/complete-step'),
      headers: _headers,
      body: jsonEncode({'step_id': stepId}),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  /// Undoes an accidental "Start onboarding" — see onboarding_cancel on
  /// the backend for exactly what is and isn't reversed.
  Future<({String message, List<String> warnings, bool itNotifiedOfCancellation})> cancelOnboarding(
      String employeeId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/onboarding/$employeeId/cancel'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (
      message: data['message'] as String,
      warnings: (data['warnings'] as List).cast<String>(),
      itNotifiedOfCancellation: data['it_notified_of_cancellation'] as bool? ?? false,
    );
  }

  Future<Map<String, dynamic>> draftOnboardingEmail(String employeeId, {String instruction = ''}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/onboarding/$employeeId/draft-email'),
      headers: _headers,
      body: jsonEncode({'instruction': instruction}),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return {
      'subject': data['subject'] as String,
      'body': data['body'] as String,
      'sent': data['sent'] == true,
      'started': data['started'] == true,
    };
  }

  Future<String> sendOnboardingEmail(String employeeId, String subject, String body) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/onboarding/$employeeId/send-email'),
      headers: _headers,
      body: jsonEncode({'subject': subject, 'body': body}),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['message'] as String;
  }

  /// Saves the reviewed welcome email on the employee's flow. The flow sends it
  /// when its step comes due (right away, or on the date set in its timing).
  /// "Review before Start": every step of the employee's flow, in order (read only).
  Future<Map<String, dynamic>> getStartReview(String process, String employeeId) async {
    final res = await http.get(Uri.parse('$baseUrl/api/$process/$employeeId/review'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<String> saveOnboardingEmail(String employeeId, String subject, String body) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/onboarding/$employeeId/save-email'),
      headers: _headers,
      body: jsonEncode({'subject': subject, 'body': body}),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return (jsonDecode(res.body) as Map<String, dynamic>)['message'] as String;
  }

  /// Same for the offboarding email.
  Future<String> saveOffboardingEmail(String employeeId, String subject, String body) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/offboarding/$employeeId/save-email'),
      headers: _headers,
      body: jsonEncode({'subject': subject, 'body': body}),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return (jsonDecode(res.body) as Map<String, dynamic>)['message'] as String;
  }

  Future<Map<String, dynamic>> onboardingStatus(String employeeId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/onboarding/$employeeId/status'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> markOnboardingStep(String employeeId, String step) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/onboarding/$employeeId/mark-step'),
      headers: _headers,
      body: jsonEncode({'step': step}),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  Future<String> resendWelcomeEmail(String employeeId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/employees/$employeeId/send-welcome-email'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['message'] as String;
  }

  Future<void> deleteEmployee(String employeeId) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/employees/$employeeId'),
      headers: _headers,
      body: jsonEncode({'confirm_employee_id': employeeId}),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  Future<List<Map<String, dynamic>>> getFlowTemplate() async {
    final res = await http.get(Uri.parse('$baseUrl/api/onboarding-flows/template'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['nodes'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> saveFlowTemplate(List<Map<String, dynamic>> nodes) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/onboarding-flows/template'),
      headers: _headers,
      body: jsonEncode({'nodes': nodes}),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  Future<List<Map<String, dynamic>>> getEmployeeFlow(String employeeId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/onboarding-flows/employee/$employeeId'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['nodes'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> saveEmployeeFlow(String employeeId, List<Map<String, dynamic>> nodes) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/onboarding-flows/employee/$employeeId'),
      headers: _headers,
      body: jsonEncode({'nodes': nodes}),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  Future<List<Map<String, dynamic>>> getOffboardingFlowTemplate() async {
    final res = await http.get(Uri.parse('$baseUrl/api/offboarding-flows/template'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['nodes'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> saveOffboardingFlowTemplate(List<Map<String, dynamic>> nodes) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/offboarding-flows/template'),
      headers: _headers,
      body: jsonEncode({'nodes': nodes}),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  Future<List<Map<String, dynamic>>> getOffboardingEmployeeFlow(String employeeId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/offboarding-flows/employee/$employeeId'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['nodes'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> saveOffboardingEmployeeFlow(String employeeId, List<Map<String, dynamic>> nodes) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/offboarding-flows/employee/$employeeId'),
      headers: _headers,
      body: jsonEncode({'nodes': nodes}),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  Future<List<Map<String, dynamic>>> listBookings({required DateTime start, required DateTime end}) async {
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final uri = Uri.parse('$baseUrl/api/bookings').replace(queryParameters: {'start': fmt(start), 'end': fmt(end)});
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['bookings'] as List).cast<Map<String, dynamic>>();
  }

  /// After Start: moves the booked orientation / exit interview to follow the
  /// step's saved plan. Returns the message to show.
  Future<String> rebookFlowMeeting(String process, String employeeId) async {
    final res = await http.post(Uri.parse('$baseUrl/api/$process/$employeeId/meeting/rebook'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return (jsonDecode(res.body) as Map<String, dynamic>)['message'] as String? ?? 'Saved.';
  }

  /// Flow steps timed "On a specific date" in this range (HR only) - shown on
  /// the Smart Schedule beside the meetings.
  Future<List<Map<String, dynamic>>> listScheduledSends({required DateTime start, required DateTime end}) async {
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final uri = Uri.parse('$baseUrl/api/schedule/sends').replace(queryParameters: {'start': fmt(start), 'end': fmt(end)});
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['sends'] as List).cast<Map<String, dynamic>>();
  }

  /// [notAfter] (YYYY-MM-DD) keeps the slot on or before that day (the last working day).
  /// IT's row on the Smart Schedule: equipment to assign / retrieve and parcels.
  Future<List<Map<String, dynamic>>> listItTasks({required DateTime start, required DateTime end}) async {
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final uri = Uri.parse('$baseUrl/api/schedule/it-tasks').replace(queryParameters: {'start': fmt(start), 'end': fmt(end)});
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return ((jsonDecode(res.body) as Map<String, dynamic>)['tasks'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> suggestBookingSlot({int durationMinutes = 30, String? notAfter}) async {
    final uri = Uri.parse('$baseUrl/api/bookings/suggest').replace(queryParameters: {
      'duration_minutes': '$durationMinutes',
      if (notAfter != null) 'not_after': notAfter,
    });
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createBooking({
    String? employeeId,
    String? employeeName,
    required String sessionType,
    String? title,
    required String date,
    required String startTime,
    int durationMinutes = 30,
    String? location,
    String mode = 'in_person',
    String? meetingUrl,
    List<String> attendeeIds = const [],
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/bookings'),
      headers: _headers,
      body: jsonEncode({
        if (employeeId != null) 'employee_id': employeeId,
        if (employeeName != null) 'employee_name': employeeName,
        'session_type': sessionType,
        if (title != null) 'title': title,
        'date': date,
        'start_time': startTime,
        'duration_minutes': durationMinutes,
        if (location != null) 'location': location,
        'mode': mode,
        if (meetingUrl != null && meetingUrl.isNotEmpty) 'meeting_url': meetingUrl,
        if (attendeeIds.isNotEmpty) 'attendees': attendeeIds.map((id) => {'id': id}).toList(),
      }),
    );
    if (res.statusCode != 201) throw ApiException(_extractMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ---------- Shipments (Pos Malaysia) ----------
  // Usable by both HR and IT tokens.

  Future<List<Map<String, dynamic>>> listShipments({String? direction}) async {
    final uri = Uri.parse('$baseUrl/api/shipments')
        .replace(queryParameters: {if (direction != null) 'direction': direction});
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return ((jsonDecode(res.body) as Map<String, dynamic>)['shipments'] as List).cast<Map<String, dynamic>>();
  }

  /// Remote employees a shipment can be started for, each with the
  /// recipient details and items, plus the company address and Pos URL:
  /// {employees: [...], company: {...}, pos_url}.
  Future<Map<String, dynamic>> shipmentEligibleEmployees(String direction) async {
    final uri = Uri.parse('$baseUrl/api/shipments/eligible').replace(queryParameters: {'direction': direction});
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createShipment(String employeeId, String direction) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/shipments'),
      headers: _headers,
      body: jsonEncode({'employee_id': employeeId, 'direction': direction}),
    );
    if (res.statusCode != 201) throw ApiException(_extractMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateShipment(String id, {String? posReference, String? status, String? notes}) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/api/shipments/$id'),
      headers: _headers,
      body: jsonEncode({
        if (posReference != null) 'pos_reference': posReference,
        if (status != null) 'status': status,
        if (notes != null) 'notes': notes,
      }),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Uploads the screenshot of the QR Pos Malaysia generated; returns its path.
  Future<String> uploadShipmentQr(String id, List<int> bytes, String filename) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/shipments/$id/qr'))
      ..headers['Authorization'] = 'Bearer $hrToken';
    request.files.add(http.MultipartFile.fromBytes('qr', bytes, filename: filename));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return (jsonDecode(res.body) as Map<String, dynamic>)['qr_image_url'] as String;
  }

  /// Return parcel: IT can't accept it - the employee is told why and sends it again.
  Future<Map<String, dynamic>> rejectReturnShipment(String id, String reason) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/shipments/$id/reject'),
      headers: _headers,
      body: jsonEncode({'reason': reason}),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> deleteShipment(String id) async {
    final res = await http.delete(Uri.parse('$baseUrl/api/shipments/$id'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  /// Cancels one session (also removes its Google event on the backend).
  Future<void> deleteBooking(String bookingId) async {
    final res = await http.delete(Uri.parse('$baseUrl/api/bookings/$bookingId'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  /// Edit a session's meeting link / location / mode after the fact.
  Future<void> updateBooking(String bookingId, {String? meetingUrl, String? location, String? mode}) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/api/bookings/$bookingId'),
      headers: _headers,
      body: jsonEncode({
        if (meetingUrl != null) 'meeting_url': meetingUrl,
        if (location != null) 'location': location,
        if (mode != null) 'mode': mode,
      }),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  /// {configured, connected, default_meeting_url} for the Google Meet link.
  Future<Map<String, dynamic>> googleStatus() async {
    final res = await http.get(Uri.parse('$baseUrl/api/google/status'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// The Google consent URL to open in a browser tab.
  Future<String> googleAuthUrl() async {
    final res = await http.get(Uri.parse('$baseUrl/api/google/auth-url'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return (jsonDecode(res.body) as Map<String, dynamic>)['url'] as String;
  }

  Future<void> googleDisconnect() async {
    final res = await http.post(Uri.parse('$baseUrl/api/google/disconnect'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  Future<List<Equipment>> listEquipment({
    String? query,
    String? type,
    String? status,
    String? condition,
  }) async {
    final params = <String, String>{};
    if (query != null && query.trim().isNotEmpty) params['q'] = query.trim();
    if (type != null) params['type'] = type;
    if (status != null) params['status'] = status;
    if (condition != null) params['condition'] = condition;

    final uri = Uri.parse('$baseUrl/api/equipment').replace(queryParameters: params.isEmpty ? null : params);
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['items'] as List)
        .map((e) => Equipment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// [onlyExisting]: just the types IT has created equipment for, rather
  /// than also the defaults offered when adding a new item.
  Future<List<String>> listEquipmentTypes({bool onlyExisting = false}) async {
    final uri = Uri.parse('$baseUrl/api/equipment/types').replace(queryParameters: onlyExisting ? {'only_existing': '1'} : null);
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['types'] as List).cast<String>();
  }

  Future<EquipmentSummary> equipmentSummary() async {
    final res = await http.get(Uri.parse('$baseUrl/api/equipment/summary'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return EquipmentSummary.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<Equipment> getEquipment(String id) async {
    final res = await http.get(Uri.parse('$baseUrl/api/equipment/$id'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return Equipment.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<Equipment> createEquipment({
    required String name,
    required String type,
    required String serialNumber,
    String? brand,
    String? model,
    String? assetTag,
    String? colorMarks,
    String? ram,
    String? storage,
    String? softwareLicenses,
    String? condition,
    String? accessoriesIncluded,
    String? purchaseDate,
    num? purchasePrice,
    String? vendor,
    String? warrantyExpiry,
    String? notes,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/equipment'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'type': type,
        'serial_number': serialNumber,
        if (brand != null) 'brand': brand,
        if (model != null) 'model': model,
        if (assetTag != null) 'asset_tag': assetTag,
        if (colorMarks != null) 'color_marks': colorMarks,
        if (ram != null) 'ram': ram,
        if (storage != null) 'storage': storage,
        if (softwareLicenses != null) 'software_licenses': softwareLicenses,
        if (condition != null) 'condition': condition,
        if (accessoriesIncluded != null) 'accessories_included': accessoriesIncluded,
        if (purchaseDate != null) 'purchase_date': purchaseDate,
        if (purchasePrice != null) 'purchase_price': purchasePrice,
        if (vendor != null) 'vendor': vendor,
        if (warrantyExpiry != null) 'warranty_expiry': warrantyExpiry,
        if (notes != null) 'notes': notes,
      }),
    );
    if (res.statusCode != 201) throw ApiException(_extractMessage(res));
    return Equipment.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<Equipment> updateEquipment(String id, Map<String, dynamic> body) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/equipment/$id'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return Equipment.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Everything HR's dashboard shows, in one call (see hr_dashboard on the
  /// backend): headcount, onboarding / offboarding summaries, the people in
  /// progress, HR's to-dos, the next week's sessions, equipment and messages.
  /// IT's dashboard: equipment, the work queue, parcels, sessions, warranties, messages.
  Future<Map<String, dynamic>> getItDashboard() async {
    final res = await http.get(Uri.parse('$baseUrl/api/it/dashboard'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getHrDashboard() async {
    final res = await http.get(Uri.parse('$baseUrl/api/hr/dashboard'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Everyone who can attend a session: employees plus HR and IT staff.
  /// Each: {id, name, role, email, department, profile_image_url}.
  Future<List<Map<String, dynamic>>> lookupPeople({String? query}) async {
    final params = <String, String>{};
    if (query != null && query.trim().isNotEmpty) params['q'] = query.trim();
    final uri = Uri.parse('$baseUrl/api/people/lookup').replace(queryParameters: params.isEmpty ? null : params);
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return ((jsonDecode(res.body) as Map<String, dynamic>)['people'] as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> lookupEmployees({String? query}) async {
    final params = <String, String>{};
    if (query != null && query.trim().isNotEmpty) params['q'] = query.trim();
    final uri = Uri.parse('$baseUrl/api/employees/lookup').replace(queryParameters: params.isEmpty ? null : params);
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['employees'] as List).cast<Map<String, dynamic>>();
  }

  Future<String> assignEquipment(
    String employeeId,
    List<String> equipmentIds, {
    String? notes,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/equipment/assign'),
      headers: _headers,
      body: jsonEncode({
        'employee_id': employeeId,
        'equipment_ids': equipmentIds,
        if (notes != null) 'notes': notes,
      }),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['message'] as String;
  }

  Future<Equipment> returnEquipment(String equipmentId, {String? condition, String? notes}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/equipment/$equipmentId/return'),
      headers: _headers,
      body: jsonEncode({
        if (condition != null) 'condition': condition,
        if (notes != null) 'notes': notes,
      }),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return Equipment.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }


  Future<String> uploadEquipmentPhoto(String equipmentId, List<int> photoBytes) async {
    final uri = Uri.parse('$baseUrl/api/equipment/$equipmentId/photo');
    final request = http.MultipartRequest('POST', uri)..headers['Authorization'] = 'Bearer $hrToken';
    request.files.add(http.MultipartFile.fromBytes('photo', photoBytes, filename: '$equipmentId.png'));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['photo_url'] as String;
  }

  Future<void> removeEquipmentPhoto(String equipmentId) async {
    final res = await http.delete(Uri.parse('$baseUrl/api/equipment/$equipmentId/photo'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  // ---------- Employee self-service ----------
  //
  // Called with an employee-role token (still just `hrToken` on this
  // class — it's really "whatever bearer token this session logged in
  // with", not HR-specific). Always "me", never take an employee_id: the
  // backend resolves the caller from the token itself.

  Future<Employee> getMyProfile() async {
    final res = await http.get(Uri.parse('$baseUrl/api/employee/me'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return Employee.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<String> uploadMyPhoto(List<int> photoBytes) async {
    final uri = Uri.parse('$baseUrl/api/employee/me/photo');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $hrToken';
    request.files.add(
      http.MultipartFile.fromBytes('photo', photoBytes, filename: 'profile.png'),
    );

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['profile_image_url'] as String;
  }

  Future<EmployeeChecklist> getMyChecklist() async {
    final res = await http.get(Uri.parse('$baseUrl/api/employee/me/checklist'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return EmployeeChecklist.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> updateMyContactInfo({String? mobileNumber, String? personalEmail}) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/employee/me/profile'),
      headers: _headers,
      body: jsonEncode({
        if (mobileNumber != null) 'mobile_number': mobileNumber,
        if (personalEmail != null) 'personal_email': personalEmail,
      }),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  Future<EmployeeNotifications> getMyNotifications() async {
    final res = await http.get(Uri.parse('$baseUrl/api/employee/me/notifications'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return EmployeeNotifications.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> markMyNotificationsRead() async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/employee/me/notifications/mark-read'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  Future<OffboardingChecklist> getMyOffboarding() async {
    final res = await http.get(Uri.parse('$baseUrl/api/employee/me/offboarding'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return OffboardingChecklist.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// The employee opened a tab (or the chat): its red badge restarts from now.
  Future<void> markSectionSeen(String section) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/employee/me/seen'),
      headers: _headers,
      body: jsonEncode({'section': section}),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  /// The signed-in employee's own sessions (all of them, oldest first).
  Future<List<Map<String, dynamic>>> getMyBookings() async {
    final res = await http.get(Uri.parse('$baseUrl/api/employee/me/bookings'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return ((jsonDecode(res.body) as Map<String, dynamic>)['bookings'] as List).cast<Map<String, dynamic>>();
  }

  /// Equipment currently assigned to the signed-in employee.
  Future<List<Map<String, dynamic>>> getMyEquipment() async {
    final res = await http.get(Uri.parse('$baseUrl/api/employee/me/equipment'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return ((jsonDecode(res.body) as Map<String, dynamic>)['equipment'] as List).cast<Map<String, dynamic>>();
  }

  /// Offboarding: what the employee has to hand back, with their checklist per item.
  Future<Map<String, dynamic>> getMyReturns() async {
    final res = await http.get(Uri.parse('$baseUrl/api/employee/me/returns'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Saves the "before you return" checklist for one item; returns the refreshed page data.
  Future<Map<String, dynamic>> saveReturnPrep(String equipmentId, Map<String, dynamic> prep) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/employee/me/returns/$equipmentId'),
      headers: _headers,
      body: jsonEncode(prep),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// "I'm ready to return" - tells IT; returns the refreshed page data.
  Future<Map<String, dynamic>> markReadyToReturn() async {
    final res = await http.post(Uri.parse('$baseUrl/api/employee/me/returns/ready'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Remote leaver: "I've posted it" - returns the refreshed page data.
  /// Remote leaver: the QR screenshot Pos gave them for the return parcel (IT sees it).
  Future<Map<String, dynamic>> uploadMyReturnQr(List<int> bytes, String filename) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/employee/me/returns/qr'))
      ..headers['Authorization'] = 'Bearer $hrToken';
    request.files.add(http.MultipartFile.fromBytes('qr', bytes, filename: filename));
    final res = await http.Response.fromStream(await request.send());
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Remote leaver: posted the parcel they booked on Pos - sends the tracking number to IT.
  Future<Map<String, dynamic>> markReturnPosted(String trackingNumber) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/employee/me/returns/posted'),
      headers: _headers,
      body: jsonEncode({'tracking_number': trackingNumber}),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> changeMyPassword(String currentPassword, String newPassword) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/employee/me/password'),
      headers: _headers,
      body: jsonEncode({'current_password': currentPassword, 'new_password': newPassword}),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  // ---------- Offboarding status (HR) ----------
  //
  // The real per-employee "HR marked this person as departing" state —
  // separate from getOffboardingFlowTemplate/getOffboardingEmployeeFlow
  // above, which only edit the shape of the automation node chain.

  /// Starts offboarding and runs its flow from the first step (see
  /// _advance_offboarding on the backend). If the first step is the
  /// offboarding email, an AI draft comes back in [subject]/[body] for HR to
  /// review and send with [sendOffboardingEmail].
  Future<({
    String subject,
    String body,
    bool itNotified,
    Map<String, dynamic>? exitInterview,
    bool emailSent,
    String? meetingWarning,
    String? currentStep,
  })> initiateOffboarding(
    String employeeId, {
    required String departureType,
    required String lastWorkingDay,
    String? notes,
    String exitInterviewMode = 'in_person',
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/employees/$employeeId/offboarding/initiate'),
      headers: _headers,
      body: jsonEncode({
        'departure_type': departureType,
        'last_working_day': lastWorkingDay,
        'exit_interview_mode': exitInterviewMode,
        if (notes != null) 'notes': notes,
      }),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (
      subject: (data['subject'] as String?) ?? '',
      body: (data['body'] as String?) ?? '',
      itNotified: data['it_notified'] as bool? ?? false,
      exitInterview: data['exit_interview'] as Map<String, dynamic>?,
      emailSent: data['email_sent'] as bool? ?? false,
      meetingWarning: data['meeting_warning'] as String?,
      currentStep: data['current_step'] as String?,
    );
  }

  /// Where this employee is in their offboarding flow: each step with
  /// {id, label, kind: auto|it|hr, state: done|current|upcoming, hint}.
  Future<List<Map<String, dynamic>>> getOffboardingRun(String employeeId) async {
    final res = await http.get(Uri.parse('$baseUrl/api/offboarding/$employeeId/run'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return ((jsonDecode(res.body) as Map<String, dynamic>)['steps'] as List).cast<Map<String, dynamic>>();
  }

  /// HR ticking off the current step when it's one only a person can finish.
  Future<void> completeOffboardingStep(String employeeId, String stepId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/offboarding/$employeeId/complete-step'),
      headers: _headers,
      body: jsonEncode({'step_id': stepId}),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  Future<Map<String, dynamic>> draftOffboardingEmail(String employeeId, {String instruction = ''}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/offboarding/$employeeId/draft-email'),
      headers: _headers,
      body: jsonEncode({'instruction': instruction}),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return {
      'subject': data['subject'] as String,
      'body': data['body'] as String,
      'sent': data['sent'] == true,
      'started': data['started'] == true,
    };
  }

  /// Sends the offboarding email; the flow then carries on by itself (IT is
  /// notified, then it waits for the equipment). Returns what happened.
  Future<String> sendOffboardingEmail(String employeeId, String subject, String body) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/offboarding/$employeeId/send-email'),
      headers: _headers,
      body: jsonEncode({'subject': subject, 'body': body}),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return (jsonDecode(res.body) as Map<String, dynamic>)['message'] as String;
  }

  /// Everyone HR has started offboarding for, with real progress - each has
  /// employee_id, full_name, department, last_working_day, departure_type,
  /// started_at, progress_percent.
  Future<List<Map<String, dynamic>>> offboardingActiveList() async {
    final res = await http.get(Uri.parse('$baseUrl/api/offboarding/active'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return ((jsonDecode(res.body) as Map<String, dynamic>)['employees'] as List).cast<Map<String, dynamic>>();
  }

  /// Undoes a started offboarding (status cleared, exit interview and IT's
  /// return request removed). Returns warnings for what can't be undone.
  Future<List<String>> cancelOffboarding(String employeeId) async {
    final res = await http.post(Uri.parse('$baseUrl/api/offboarding/$employeeId/cancel'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return ((data['warnings'] as List?) ?? const []).cast<String>();
  }

  /// Departure type, last working day and notes saved before offboarding starts.
  Future<void> saveOffboardingDetails(
    String employeeId, {
    required String departureType,
    required String lastWorkingDay,
    String? notes,
  }) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/employees/$employeeId/offboarding/details'),
      headers: _headers,
      body: jsonEncode({'departure_type': departureType, 'last_working_day': lastWorkingDay, 'notes': notes ?? ''}),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  Future<OffboardingChecklist> getEmployeeOffboarding(String employeeId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/employees/$employeeId/offboarding'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return OffboardingChecklist.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> offboardingMarkStep(String employeeId, String step) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/offboarding/$employeeId/mark-step'),
      headers: _headers,
      body: jsonEncode({'step': step}),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  // ---------- AI chatbot ----------
  //
  // Both grounded in a fresh server-side snapshot of real data on every
  // call (see _hr_chat_snapshot/_employee_chat_snapshot on the backend) —
  // history is sent back each time since nothing is persisted server-side.

  Future<ChatReply> _chat(String path, String message, List<ChatTurn> history) async {
    final res = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
      body: jsonEncode({
        'message': message,
        'history': history.map((t) => t.toJson()).toList(),
      }),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return ChatReply.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<ChatReply> hrChat(String message, List<ChatTurn> history) =>
      _chat('/api/hr/chat', message, history);

  Future<ChatReply> itChat(String message, List<ChatTurn> history) =>
      _chat('/api/it/chat', message, history);

  Future<ChatReply> employeeChat(String message, List<ChatTurn> history) =>
      _chat('/api/employee/me/chat', message, history);

  // ---------- Company documents (uploaded from the HR chat) ----------

  /// Uploads a document from the HR chat. Returns the reply to show: what was
  /// saved plus a short AI summary, with the new document attached.
  Future<ChatReply> uploadDocument(String filename, List<int> bytes, {String? title}) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/hr/documents'))
      ..headers['Authorization'] = 'Bearer $hrToken';
    if (title != null && title.trim().isNotEmpty) request.fields['title'] = title.trim();
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

    final res = await http.Response.fromStream(await request.send());
    if (res.statusCode != 201) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final doc = data['document'] as Map<String, dynamic>;
    final summary = (data['summary'] as String?) ?? '';
    final hasText = doc['has_text'] == true;
    final text = StringBuffer('Saved "${doc['title']}". HR, IT and employees can now ask me about it and download it.');
    if (summary.isNotEmpty) {
      text.write('\n\nSummary: $summary');
    } else if (!hasText) {
      text.write("\n\nI couldn't read any text in this file (it may be a scan), so it can be downloaded "
          "but I can't summarise it or search inside it.");
    }
    return ChatReply(text: text.toString(), documents: [ChatDocument.fromJson(doc)]);
  }

  Future<void> deleteDocument(String documentId) async {
    final res = await http.delete(Uri.parse('$baseUrl/api/hr/documents/$documentId'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  /// Opens in a new tab / the browser, so the token rides in the query string
  /// (same approach as the Excel export; the backend accepts ?token=).
  String documentDownloadUrl(String documentId) =>
      '$baseUrl/api/documents/$documentId/download?token=${Uri.encodeQueryComponent(hrToken)}';

  // ---------- Documents and surveys given out by flow steps ----------
  //
  // HR attaches files to a Documents step and reviews what comes back; the
  // employee sees their own items, downloads, acknowledges, uploads, answers.
  // Files only ever leave through these signed-in routes.

  String get _tokenQuery => 'token=${Uri.encodeQueryComponent(hrToken)}';

  /// HR: uploads a file to attach to a Documents step. Returns {file_id, filename}.
  Future<Map<String, dynamic>> uploadFlowFile(String filename, List<int> bytes) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/hr/flow-files'))
      ..headers['Authorization'] = 'Bearer $hrToken';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final res = await http.Response.fromStream(await request.send());
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Employee: the documents and surveys issued to me.
  Future<Map<String, dynamic>> getMyFlowItems() async {
    final res = await http.get(Uri.parse('$baseUrl/api/employee/me/flow-items'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  String myFlowDocFileUrl(String id) => '$baseUrl/api/employee/me/flow-documents/$id/file?$_tokenQuery';

  Future<void> acknowledgeFlowDoc(String id) async {
    final res = await http.post(Uri.parse('$baseUrl/api/employee/me/flow-documents/$id/acknowledge'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  Future<void> uploadFlowDocReturn(String id, String filename, List<int> bytes) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/employee/me/flow-documents/$id/upload'))
      ..headers['Authorization'] = 'Bearer $hrToken';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final res = await http.Response.fromStream(await request.send());
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  Future<void> submitFlowSurvey(String id, Map<String, dynamic> answers) async {
    final res = await http.post(Uri.parse('$baseUrl/api/employee/me/surveys/$id/submit'),
        headers: _headers, body: jsonEncode({'answers': answers}));
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  /// HR: everything issued to one employee, with their answers / uploads.
  Future<Map<String, dynamic>> getEmployeeFlowItems(String employeeId) async {
    final res = await http.get(Uri.parse('$baseUrl/api/hr/employees/$employeeId/flow-items'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  String hrFlowDocFileUrl(String id) => '$baseUrl/api/hr/flow-documents/$id/file?$_tokenQuery';
  String hrFlowDocReturnedUrl(String id) => '$baseUrl/api/hr/flow-documents/$id/returned?$_tokenQuery';

  Future<void> approveFlowDoc(String id) async {
    final res = await http.post(Uri.parse('$baseUrl/api/hr/flow-documents/$id/approve'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  Future<void> rejectFlowDoc(String id, String reason) async {
    final res = await http.post(Uri.parse('$baseUrl/api/hr/flow-documents/$id/reject'),
        headers: _headers, body: jsonEncode({'reason': reason}));
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  Future<void> remindFlowDoc(String id) async {
    final res = await http.post(Uri.parse('$baseUrl/api/hr/flow-documents/$id/remind'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  Future<void> remindFlowSurvey(String id) async {
    final res = await http.post(Uri.parse('$baseUrl/api/hr/flow-surveys/$id/remind'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  // ---------- Messaging (Talk to HR / Talk to IT) ----------
  //
  // Plain human messages, distinct from the AI chatbot above. No push —
  // callers re-poll getMyMessages/getHrThread/getItThread on a timer.

  Future<List<ChatMessage>> getMyMessages(String targetRole) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/employee/me/messages/$targetRole'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['messages'] as List).map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> sendMyMessage(String targetRole, String content) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/employee/me/messages/$targetRole'),
      headers: _headers,
      body: jsonEncode({'content': content}),
    );
    if (res.statusCode != 201) throw ApiException(_extractMessage(res));
  }

  Future<List<MessageConversation>> getHrConversations() async {
    final res = await http.get(Uri.parse('$baseUrl/api/hr/messages'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['conversations'] as List)
        .map((e) => MessageConversation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ChatMessage>> getHrThread(String employeeId) async {
    final res = await http.get(Uri.parse('$baseUrl/api/hr/messages/$employeeId'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['messages'] as List).map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> sendHrMessage(String employeeId, String content) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/hr/messages/$employeeId'),
      headers: _headers,
      body: jsonEncode({'content': content}),
    );
    if (res.statusCode != 201) throw ApiException(_extractMessage(res));
  }

  Future<List<MessageConversation>> getItConversations() async {
    final res = await http.get(Uri.parse('$baseUrl/api/it/messages'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['conversations'] as List)
        .map((e) => MessageConversation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ChatMessage>> getItThread(String employeeId) async {
    final res = await http.get(Uri.parse('$baseUrl/api/it/messages/$employeeId'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['messages'] as List).map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> sendItMessage(String employeeId, String content) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/it/messages/$employeeId'),
      headers: _headers,
      body: jsonEncode({'content': content}),
    );
    if (res.statusCode != 201) throw ApiException(_extractMessage(res));
  }

  /// IT explicitly acknowledging a system-authored notification (e.g.
  /// the onboarding equipment-prep message) — not meaningful on a human
  /// message, which the backend rejects.
  // ---------- Notifications for HR / IT (the top-bar bell) ----------

  /// {notifications: [{id, kind: notification|reminder|alert, title, message,
  /// link, at, read}], unread_count}.
  Future<Map<String, dynamic>> getStaffNotifications() async {
    final res = await http.get(Uri.parse('$baseUrl/api/staff/notifications'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> markStaffNotificationRead(String id) async {
    final res = await http.post(Uri.parse('$baseUrl/api/staff/notifications/$id/read'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  Future<void> markAllStaffNotificationsRead() async {
    final res = await http.post(Uri.parse('$baseUrl/api/staff/notifications/read-all'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  /// Opening a sidebar tab: marks the notifications that point to it as read.
  Future<void> markStaffNotificationTypesRead(List<String> types) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/staff/notifications/read-types'),
      headers: _headers,
      body: jsonEncode({'types': types}),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  /// IT's equipment requests with live assigned/not-assigned status and the
  /// employee + Microsoft-account details (IT token only).
  /// Returns {requests: [...], notices: [...]} - notices are short automatic
  /// notes (e.g. "onboarding cancelled - items released") IT can delete.
  Future<Map<String, dynamic>> getItRequests() async {
    final res = await http.get(Uri.parse('$baseUrl/api/it/requests'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Deletes an automatic notice (never a real conversation message).
  Future<void> deleteItNotice(String messageId) async {
    final res = await http.delete(Uri.parse('$baseUrl/api/it/messages/$messageId'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  Future<void> acceptMessage(String messageId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/it/messages/$messageId/accept'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  /// IT confirming a leaver with no equipment on record has nothing to hand back.
  Future<void> confirmNothingToCollect(String messageId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/it/returns/$messageId/nothing-to-collect'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  String _extractMessage(http.Response res) {
    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['message'] as String? ?? 'Something went wrong (${res.statusCode}).';
    } catch (_) {
      return 'Something went wrong (${res.statusCode}).';
    }
  }
}
