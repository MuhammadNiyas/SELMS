// lib/screens/employee_directory_screen.dart
//
// Search is universal: it matches against every field on the backend
// (name, ID, department, job title, work location, employment status,
// emails, phone, line manager, IC/passport — see selms_backend.py).
// The Filters panel only narrows by four specific categories.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/employee.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/app_shell.dart';
import 'add_employee_screen.dart';
import 'employee_view_screen.dart';

const _departments = ['HR', 'IT', 'Marketing', 'Finance', 'Operations'];
const _employmentStatuses = ['Probation', 'Confirmed', 'Contract', 'Full-Time', 'Part-Time'];
const _workLocationTypes = ['Onsite', 'Remote'];

class EmployeeDirectoryScreen extends StatefulWidget {
  const EmployeeDirectoryScreen({super.key, required this.apiBaseUrl, required this.hrToken});

  final String apiBaseUrl;
  final String hrToken;

  @override
  State<EmployeeDirectoryScreen> createState() => _EmployeeDirectoryScreenState();
}

class _EmployeeDirectoryScreenState extends State<EmployeeDirectoryScreen> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.hrToken);
  final _searchCtrl = TextEditingController();

  String? _department;
  String? _employmentStatus;
  String? _workLocationType;

  List<Employee> _employees = [];
  bool _loading = true;
  String? _error;

  final _filterButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  int get _activeFilterCount =>
      [_department, _employmentStatus, _workLocationType].where((v) => v != null).length;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await _api.listEmployees(
        query: _searchCtrl.text,
        department: _department,
        employmentStatus: _employmentStatus,
        workLocationType: _workLocationType,
      );
      if (!mounted) return;
      setState(() {
        _employees = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _exportExcel() async {
    final params = <String, String>{'token': widget.hrToken};
    if (_searchCtrl.text.trim().isNotEmpty) params['q'] = _searchCtrl.text.trim();
    if (_department != null) params['department'] = _department!;
    if (_employmentStatus != null) params['employment_status'] = _employmentStatus!;
    if (_workLocationType != null) params['work_location_type'] = _workLocationType!;

    final uri = Uri.parse('${widget.apiBaseUrl}/api/employees/export').replace(queryParameters: params);
    final ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not start the export download.')));
    }
  }

  void _openFilterPanel() async {
    final renderBox = _filterButtonKey.currentContext!.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    String? dept = _department;
    String? empStatus = _employmentStatus;
    String? workLoc = _workLocationType;

    await showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height + 6,
        offset.dx + 260,
        offset.dy + size.height + 6,
      ),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: StatefulBuilder(
            builder: (context, setMenuState) {
              return Container(
                width: 230,
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _filterDropdown('Department', dept, _departments,
                        (v) => setMenuState(() => dept = v)),
                    const SizedBox(height: 12),
                    _filterDropdown('Employment status', empStatus, _employmentStatuses,
                        (v) => setMenuState(() => empStatus = v)),
                    const SizedBox(height: 12),
                    _filterDropdown('Work location type', workLoc, _workLocationTypes,
                        (v) => setMenuState(() => workLoc = v)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => setMenuState(() {
                              dept = null;
                              empStatus = null;
                              workLoc = null;
                            }),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: SelmsColors.border),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            child: const Text('Clear', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _department = dept;
                                _employmentStatus = empStatus;
                                _workLocationType = workLoc;
                              });
                              Navigator.of(context).pop();
                              _load();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: SelmsColors.ink,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            child: const Text('Apply', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _filterDropdown(
      String label, String? value, List<String> options, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: Colors.black45)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          hint: Text('All ${label.toLowerCase()}s', style: const TextStyle(fontSize: 12.5)),
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(fontSize: 12.5))))
              .toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: SelmsColors.border),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      apiBaseUrl: widget.apiBaseUrl,
      hrToken: widget.hrToken,
      activeRoute: SelmsRoute.employees,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Employees',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                    Text('${_employees.length} shown',
                        style: const TextStyle(fontSize: 13, color: SelmsColors.textSecondary)),
                  ],
                ),
                const TopBarActions(),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    constraints: const BoxConstraints(maxWidth: 420),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(left: 2),
                          child: Icon(Icons.search, size: 15, color: SelmsColors.textMuted),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: (_) => _load(),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              hintText: 'Search employees...',
                              hintStyle: TextStyle(fontSize: 12.5, color: SelmsColors.textMuted),
                            ),
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                InkWell(
                  key: _filterButtonKey,
                  onTap: _openFilterPanel,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(color: SelmsColors.ink, borderRadius: BorderRadius.circular(8)),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.filter_list, size: 15, color: Colors.white),
                        if (_activeFilterCount > 0)
                          Positioned(
                            right: -6,
                            top: -6,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(color: SelmsColors.rose, shape: BoxShape.circle),
                              child: Text('$_activeFilterCount',
                                  style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.w600)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _exportExcel,
                  icon: const Icon(Icons.table_chart_outlined, size: 16, color: Colors.white),
                  label: const Text('Export Excel'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    side: BorderSide.none,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: () async {
                    final created = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) =>
                            AddEmployeeScreen(apiBaseUrl: widget.apiBaseUrl, hrToken: widget.hrToken),
                      ),
                    );
                    if (created == true) _load();
                  },
                  icon: const Icon(Icons.person_add_alt, size: 16),
                  label: const Text('Add employee'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SelmsColors.ink,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: SelmsColors.rose, fontSize: 13)),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_employees.isEmpty) {
      return const Center(
        child: Text('No employees match your search.',
            style: TextStyle(color: SelmsColors.textMuted, fontSize: 13)),
      );
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.4,
      ),
      itemCount: _employees.length,
      itemBuilder: (context, i) => _EmployeeCard(
        employee: _employees[i],
        apiBaseUrl: widget.apiBaseUrl,
        onTap: () async {
          final changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => EmployeeViewScreen(
                apiBaseUrl: widget.apiBaseUrl,
                hrToken: widget.hrToken,
                employeeId: _employees[i].employeeId,
              ),
            ),
          );
          if (changed == true) _load();
        },
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({required this.employee, required this.apiBaseUrl, required this.onTap});

  final Employee employee;
  final String apiBaseUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  clipBehavior: Clip.hardEdge,
                  decoration: const BoxDecoration(color: SelmsColors.accentBg, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: (employee.profileImageUrl != null && employee.profileImageUrl!.isNotEmpty)
                      ? Image.network('${apiBaseUrl}${employee.profileImageUrl}',
                          fit: BoxFit.cover, width: 38, height: 38)
                      : Text(employee.initials,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600, color: SelmsColors.ink)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(employee.fullName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w500, color: SelmsColors.textPrimary)),
                      Text(employee.jobTitle ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('${employee.employeeId} · ${employee.department ?? ''}',
                style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
            const Spacer(),
            Row(
              children: [
                _iconButton(Icons.mail_outline, () {
                  if (employee.workEmail != null) {
                    launchUrl(Uri.parse('mailto:${employee.workEmail}'));
                  }
                }),
                const SizedBox(width: 8),
                _iconButton(Icons.call_outlined, () {
                  if (employee.mobileNumber != null) {
                    launchUrl(Uri.parse('tel:${employee.mobileNumber}'));
                  }
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        width: 26,
        height: 26,
        decoration: const BoxDecoration(color: Color(0xFFF3F4F6), shape: BoxShape.circle),
        child: Icon(icon, size: 13, color: const Color(0xFF6B7280)),
      ),
    );
  }
}
