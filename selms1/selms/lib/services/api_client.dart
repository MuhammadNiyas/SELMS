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

  Future<void> updateEmployee(String employeeId, Map<String, dynamic> body) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/employees/$employeeId'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
  }

  Future<List<Map<String, dynamic>>> onboardingCandidates() async {
    final res = await http.get(Uri.parse('$baseUrl/api/onboarding/candidates'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['candidates'] as List).cast<Map<String, dynamic>>();
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
  })> autoStartOnboarding(String employeeId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/onboarding/$employeeId/auto-start'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (
      subject: data['subject'] as String,
      body: data['body'] as String,
      orientation: data['orientation'] as Map<String, dynamic>?,
      scheduleEnabled: data['schedule_enabled'] as bool? ?? true,
      itNotified: data['it_notified'] as bool? ?? false,
    );
  }

  Future<Map<String, String>> draftOnboardingEmail(String employeeId, {String instruction = ''}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/onboarding/$employeeId/draft-email'),
      headers: _headers,
      body: jsonEncode({'instruction': instruction}),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return {'subject': data['subject'] as String, 'body': data['body'] as String};
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

  Future<Map<String, dynamic>> suggestBookingSlot({int durationMinutes = 30}) async {
    final uri = Uri.parse('$baseUrl/api/bookings/suggest')
        .replace(queryParameters: {'duration_minutes': '$durationMinutes'});
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
      }),
    );
    if (res.statusCode != 201) throw ApiException(_extractMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
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

  Future<List<String>> listEquipmentTypes() async {
    final res = await http.get(Uri.parse('$baseUrl/api/equipment/types'), headers: _headers);
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

  Future<List<CompanyDocument>> getMyDocuments() async {
    final res = await http.get(Uri.parse('$baseUrl/api/employee/me/documents'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['documents'] as List)
        .map((e) => CompanyDocument.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> signMyDocument(String docId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/employee/me/documents/$docId/sign'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
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

  // ---------- Offboarding status (HR) ----------
  //
  // The real per-employee "HR marked this person as departing" state —
  // separate from getOffboardingFlowTemplate/getOffboardingEmployeeFlow
  // above, which only edit the shape of the automation node chain.

  Future<void> initiateOffboarding(
    String employeeId, {
    required String departureType,
    required String lastWorkingDay,
    String? notes,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/employees/$employeeId/offboarding/initiate'),
      headers: _headers,
      body: jsonEncode({
        'departure_type': departureType,
        'last_working_day': lastWorkingDay,
        if (notes != null) 'notes': notes,
      }),
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

  Future<String> hrChat(String message, List<ChatTurn> history) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/hr/chat'),
      headers: _headers,
      body: jsonEncode({
        'message': message,
        'history': history.map((t) => t.toJson()).toList(),
      }),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return (jsonDecode(res.body) as Map<String, dynamic>)['reply'] as String;
  }

  Future<String> employeeChat(String message, List<ChatTurn> history) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/employee/me/chat'),
      headers: _headers,
      body: jsonEncode({
        'message': message,
        'history': history.map((t) => t.toJson()).toList(),
      }),
    );
    if (res.statusCode != 200) throw ApiException(_extractMessage(res));
    return (jsonDecode(res.body) as Map<String, dynamic>)['reply'] as String;
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

  String _extractMessage(http.Response res) {
    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['message'] as String? ?? 'Something went wrong (${res.statusCode}).';
    } catch (_) {
      return 'Something went wrong (${res.statusCode}).';
    }
  }
}
