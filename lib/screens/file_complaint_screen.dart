import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../api/api_service.dart';
import '../utils/session_manager.dart';
import '../utils/app_theme.dart';

import '../widgets/custom_snackbar.dart';

class FileComplaintScreen extends StatefulWidget {
  const FileComplaintScreen({super.key});

  @override
  State<FileComplaintScreen> createState() => _FileComplaintScreenState();
}

class _FileComplaintScreenState extends State<FileComplaintScreen> {
  final ApiService _apiService = ApiService();
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final TextEditingController _descriptionController = TextEditingController();
  String _selectedCategory = 'Uncollected Garbage';
  bool _isLoading = false;

  final List<String> _categories = [
    'Uncollected Garbage',
    'Spilled Waste',
    'Driver Behavior',
    'Schedule Issue',
    'Other'
  ];

  void _submitComplaint() async {
    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      CustomSnackBar.show(context, message: "Please describe the issue", isError: true);
      return;
    }

    setState(() => _isLoading = true);
    final user = await SessionManager.getUser();
    
    try {
      final response = await _apiService.fileComplaint(
        user?.userId.toString() ?? "0",
        _selectedCategory,
        description,
      );

      if (response.data['success'] == true) {
        // TRIGGER APP NOTIFICATION FOR ADMIN VIA FIREBASE
        try {
          await _database.ref('notifications').push().set({
            'type': 'RESIDENT_COMPLAINT',
            'title': 'New Resident Complaint',
            'message': '${user?.name ?? 'A resident'} filed a complaint: $_selectedCategory',
            'resident_id': user?.userId,
            'timestamp': ServerValue.timestamp,
            'isRead': false,
          });
        } catch (e) {
          debugPrint("Firebase notification error: $e");
        }

        if (!mounted) return;
        CustomSnackBar.show(context, message: "Complaint submitted successfully");
        Navigator.pop(context);
      } else {
        throw response.data['message'] ?? "Submission failed";
      }
    } catch (e) {
      if (!mounted) return;
      CustomSnackBar.show(context, message: "Error: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            // Header (activity_file_complaint.xml line 12-42)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))]),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back, color: Color(0xFF333333)), onPressed: () => Navigator.pop(context)),
                  const SizedBox(width: 8),
                  const Text("File a Complaint", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Select Category Label (line 55-60)
                    const Text("Select Category", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF757575))),
                    const SizedBox(height: 8),
                    // Spinner Category (line 62-67)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE0E0E0))),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedCategory,
                          isExpanded: true,
                          items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                          onChanged: (val) => setState(() => _selectedCategory = val!),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Description Label (line 69-74)
                    const Text("Description", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF757575))),
                    const SizedBox(height: 8),
                    // EditText Description (line 76-85)
                    Container(
                      decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE0E0E0))),
                      child: TextField(
                        controller: _descriptionController,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          hintText: "Provide details about your complaint...",
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Submit Button (line 87-97)
                    ElevatedButton(
                      onPressed: _isLoading ? null : _submitComplaint,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4CAF50),
                        minimumSize: const Size(double.infinity, 56),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("Submit Complaint", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
