// lib/screens/employee_documents_screen.dart
//
// Company documents the employee needs to acknowledge (report fig 3.29).
// "Signing" records a real timestamp per document per employee in Mongo
// (signed_documents.<doc_id>) — there's no actual PDF to view yet since
// none exist in this project, so each card just states what the document
// covers and lets the employee acknowledge it.

import 'package:flutter/material.dart';
import '../models/employee_self_service.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';

class EmployeeDocumentsScreen extends StatefulWidget {
  const EmployeeDocumentsScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<EmployeeDocumentsScreen> createState() => _EmployeeDocumentsScreenState();
}

class _EmployeeDocumentsScreenState extends State<EmployeeDocumentsScreen> {
  late Future<List<CompanyDocument>> _future;
  String? _signingId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = widget.api.getMyDocuments();
  }

  Future<void> _refresh() async {
    setState(() => _future = widget.api.getMyDocuments());
    await _future;
  }

  Future<void> _sign(String docId) async {
    setState(() {
      _signingId = docId;
      _error = null;
    });
    try {
      await widget.api.signMyDocument(docId);
      await _refresh();
    } catch (e) {
      setState(() => _error = 'Could not sign: $e');
    } finally {
      if (mounted) setState(() => _signingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<CompanyDocument>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('Could not load documents.\n${snapshot.error}',
                    style: const TextStyle(color: SelmsColors.rose, fontSize: 13)),
              ],
            );
          }

          final docs = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              const Text('Company Documents',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('Review and acknowledge each document below.',
                  style: TextStyle(fontSize: 12, color: SelmsColors.textMuted)),
              const SizedBox(height: 14),
              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: SelmsColors.roseBg,
                    border: Border.all(color: SelmsColors.roseBorder),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!, style: const TextStyle(fontSize: 12, color: SelmsColors.rose)),
                ),
              ],
              ...docs.map((doc) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: SelmsColors.cardWhite,
                      border: Border.all(color: SelmsColors.border),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: SelmsColors.accentBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(Icons.description_outlined, size: 18, color: SelmsColors.ink),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(doc.title,
                                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(doc.description,
                                  style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (doc.signed)
                          const Chip(
                            label: Text('Signed ✓', style: TextStyle(fontSize: 11, color: SelmsColors.statusActiveText)),
                            backgroundColor: SelmsColors.statusActiveBg,
                            side: BorderSide.none,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          )
                        else
                          SizedBox(
                            height: 32,
                            child: ElevatedButton(
                              onPressed: _signingId == doc.id ? null : () => _sign(doc.id),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: SelmsColors.ink,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                              ),
                              child: _signingId == doc.id
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('Sign'),
                            ),
                          ),
                      ],
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }
}
