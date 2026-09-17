import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/user.dart';
import '../api/api_service.dart';
import '../utils/session_manager.dart';
import '../utils/app_localizations.dart';
import '../utils/app_theme.dart';
import '../widgets/custom_snackbar.dart';
import 'hover_action_button.dart';

class DataManagementModal extends StatefulWidget {
  final UserData user;
  final VoidCallback onSuccess;
  final FocusNode? usernameFocus;
  final FocusNode? nameFocus;
  final FocusNode? emailFocus;
  final FocusNode? phoneFocus;

  const DataManagementModal({
    super.key,
    required this.user,
    required this.onSuccess,
    this.usernameFocus,
    this.nameFocus,
    this.emailFocus,
    this.phoneFocus,
  });

  @override
  State<DataManagementModal> createState() => _DataManagementModalState();
}

class _DataManagementModalState extends State<DataManagementModal> {
  final ApiService _apiService = ApiService();
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  
  late TextEditingController usernameCtrl;
  late TextEditingController nameCtrl;
  late TextEditingController emailCtrl;
  late TextEditingController phoneCtrl;
  late TextEditingController truckCtrl;
  late String selectedPurok;

  late FocusNode usernameFocus;
  late FocusNode nameFocus;
  late FocusNode emailFocus;
  late FocusNode phoneFocus;
  final truckFocus = FocusNode();

  bool usernameTouched = false;
  bool nameTouched = false;
  bool emailTouched = false;
  bool phoneTouched = false;
  bool truckTouched = false;
  bool purokTouched = false;

  String? usernameError;
  String? nameError;
  String? emailError;
  String? phoneError;
  String? truckError;
  String? purokError;

  Color? usernameColor;
  Color? nameColor;
  Color? emailColor;
  Color? phoneColor;
  Color? truckColor;
  Color? purokColor;

  bool _isLoading = false;
  Timer? _debounce;

  final List<String> _puroks = [
    "Purok 1", "Purok 2", "Purok 3", "Purok 4", "Dos Riles", "Sentro",
    "San Isidro", "Paraiso", "Riverside", "Kalaw Street",
    "Home Subdivision", "Tanco Road / Ayala Highway", "Brixton Area"
  ];

  @override
  void initState() {
    super.initState();
    usernameCtrl = TextEditingController(text: widget.user.username);
    nameCtrl = TextEditingController(text: widget.user.name);
    emailCtrl = TextEditingController(text: widget.user.email);
    phoneCtrl = TextEditingController(text: widget.user.phone);
    truckCtrl = TextEditingController(text: widget.user.preferredTruck ?? "");
    selectedPurok = widget.user.purok ?? "Sentro";

    usernameFocus = widget.usernameFocus ?? FocusNode();
    nameFocus = widget.nameFocus ?? FocusNode();
    emailFocus = widget.emailFocus ?? FocusNode();
    phoneFocus = widget.phoneFocus ?? FocusNode();

    // Add listeners for real-time validation
    usernameCtrl.addListener(() => _validateUsername());
    nameCtrl.addListener(() => _validateFullName());
    emailCtrl.addListener(() => _validateEmail());
    phoneCtrl.addListener(() => _validatePhone());
    truckCtrl.addListener(() => _validateTruck());

    // Add listeners for focus color changes
    usernameFocus.addListener(() { if (mounted) setState(() {}); });
    nameFocus.addListener(() { if (mounted) setState(() {}); });
    emailFocus.addListener(() { if (mounted) setState(() {}); });
    phoneFocus.addListener(() { if (mounted) setState(() {}); });
    truckFocus.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    usernameCtrl.dispose();
    nameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    truckCtrl.dispose();
    usernameFocus.dispose();
    nameFocus.dispose();
    emailFocus.dispose();
    phoneFocus.dispose();
    truckFocus.dispose();
    super.dispose();
  }

  void _validateUsername() {
    final val = usernameCtrl.text.trim();
    if (val.isEmpty) {
      setState(() { usernameError = "Username is required"; usernameColor = Colors.redAccent; });
      return;
    }
    if (val == widget.user.username) {
      setState(() { usernameError = "This is your current username"; usernameColor = Colors.blueAccent; });
      return;
    }
    
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final res = await _apiService.checkUsername(val);
        if (mounted) {
          setState(() {
            if (res.data['success'] == true) {
              usernameError = "This username is already taken";
              usernameColor = Colors.redAccent;
            } else {
              usernameError = null;
              usernameColor = null;
            }
          });
        }
      } catch (e) { debugPrint("Username check error: $e"); }
    });
  }

  void _validateFullName() {
    final val = nameCtrl.text.trim();
    if (val.isEmpty) {
      setState(() { nameError = "Full name is required"; nameColor = Colors.redAccent; });
      return;
    }
    if (val == widget.user.name) {
      setState(() { nameError = "This is your current name"; nameColor = Colors.blueAccent; });
      return;
    }
    if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(val)) {
      setState(() { nameError = "Letters and spaces only, no special characters"; nameColor = Colors.redAccent; });
    } else {
      setState(() { nameError = null; nameColor = null; });
    }
  }

  void _validateEmail() {
    final val = emailCtrl.text.trim();
    if (val.isEmpty) {
      setState(() { emailError = "Email address is required"; emailColor = Colors.redAccent; });
      return;
    }
    if (!RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(val)) {
      setState(() { emailError = "Please enter a valid email address"; emailColor = Colors.redAccent; });
      return;
    }
    if (val == widget.user.email) {
      setState(() { emailError = "This is your current email address"; emailColor = Colors.blueAccent; });
      return;
    }

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final res = await _apiService.checkEmail(val);
        if (mounted) {
          setState(() {
            if (res.data['success'] == true) {
              emailError = "This email address is already in use";
              emailColor = Colors.redAccent;
            } else {
              emailError = null;
              emailColor = null;
            }
          });
        }
      } catch (e) { debugPrint("Email check error: $e"); }
    });
  }

  void _validatePhone() {
    final val = phoneCtrl.text.trim();
    if (val.isEmpty) {
      setState(() { phoneError = "Contact number is required"; phoneColor = Colors.redAccent; });
      return;
    }
    if (!RegExp(r'^(09|63)\d{9}$').hasMatch(val)) {
      setState(() { phoneError = "Invalid PH format (e.g., 09123456789)"; phoneColor = Colors.redAccent; });
      return;
    }
    if (val == widget.user.phone) {
      setState(() { phoneError = "This is your current contact number"; phoneColor = Colors.blueAccent; });
      return;
    }

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final res = await _apiService.checkPhone(val);
        if (mounted) {
          setState(() {
            if (res.data['success'] == true) {
              phoneError = "This phone number is already registered";
              phoneColor = Colors.redAccent;
            } else {
              phoneError = null;
              phoneColor = null;
            }
          });
        }
      } catch (e) { debugPrint("Phone check error: $e"); }
    });
  }

  void _validateTruck() {
    final val = truckCtrl.text.trim();
    if (val == (widget.user.preferredTruck ?? "")) {
      setState(() { truckError = "This is your current truck number"; truckColor = Colors.blueAccent; });
    } else {
      setState(() { truckError = null; truckColor = null; });
    }
  }

  void _onPurokChanged(String? val) {
    setState(() {
      selectedPurok = val!;
      if (val == widget.user.purok) {
        purokError = "This is your current purok";
        purokColor = Colors.blueAccent;
      } else {
        purokError = null;
        purokColor = null;
      }
    });
  }

  Future<void> _submit() async {
    // Collect which fields have actually changed
    Map<String, String> changes = {};
    if (usernameCtrl.text.trim() != (widget.user.username ?? "")) changes['username'] = "username";
    if (nameCtrl.text.trim() != widget.user.name) changes['full name'] = "full name";
    if (emailCtrl.text.trim() != (widget.user.email ?? "")) changes['email'] = "email";
    if (phoneCtrl.text.trim() != (widget.user.phone ?? "")) changes['contact number'] = "contact number";
    if (truckCtrl.text.trim() != (widget.user.preferredTruck ?? "")) changes['assigned truck'] = "assigned truck";
    if (selectedPurok != (widget.user.purok ?? "")) changes['purok'] = "purok";

    if (changes.isEmpty) {
      Navigator.pop(context);
      return;
    }

    // Check for RED errors (blocking)
    if ((usernameError != null && usernameColor == Colors.redAccent) ||
        (nameError != null && nameColor == Colors.redAccent) ||
        (emailError != null && emailColor == Colors.redAccent) ||
        (widget.user.role != 'admin' && phoneError != null && phoneColor == Colors.redAccent)) {
      return;
    }

    bool confirm = await _showConfirmActionDialog(
      title: "Save Changes?",
      message: "Are you sure you want to update your profile information?",
      confirmText: "SAVE CHANGES",
    );
    if (!confirm) return;

    setState(() => _isLoading = true);
    
    try {
      final response = await _apiService.updateProfile(
        userId: widget.user.userId,
        role: widget.user.role,
        name: nameCtrl.text.trim(),
        username: usernameCtrl.text.trim(),
        phone: phoneCtrl.text.trim(),
        email: emailCtrl.text.trim(),
        purok: widget.user.role == 'resident' ? selectedPurok : null,
        preferredTruck: widget.user.role == 'driver' ? truckCtrl.text.trim() : null,
      );
      
      if (response.data['success'] == true) {
        // Sync to Firebase
        final String node = widget.user.role == 'resident' ? 'residents' : 'users';
        await _database.ref('$node/${widget.user.userId}').update({
          'name': nameCtrl.text.trim(),
          'username': usernameCtrl.text.trim(),
          'email': emailCtrl.text.trim(),
          'phone': phoneCtrl.text.trim(),
          if (widget.user.role == 'resident') 'purok': selectedPurok,
          if (widget.user.role == 'driver') 'preferred_truck': truckCtrl.text.trim(),
        });

        final updatedUser = widget.user.copyWith(
          name: nameCtrl.text.trim(),
          username: usernameCtrl.text.trim(),
          email: emailCtrl.text.trim(),
          phone: phoneCtrl.text.trim(),
          purok: selectedPurok,
          preferredTruck: truckCtrl.text.trim(),
        );
        await SessionManager.saveUser(updatedUser.toJson());
        
        if (mounted) {
          Navigator.pop(context);
          widget.onSuccess();
          
          String successMsg;
          if (changes.length == 1) {
            final field = changes.keys.first;
            successMsg = "Successfully updated your $field.";
          } else {
            bool allChanged = false;
            if (widget.user.role == 'admin') {
              allChanged = changes.length >= 3; // Username, Name, Email
            } else {
              allChanged = changes.length >= 5; // Username, Name, Email, Phone, + (Truck/Purok)
            }
            successMsg = allChanged ? "Successfully updated all account information." : "Successfully updated your profile information.";
          }
          
          CustomSnackBar.show(context, message: successMsg, isModal: true);
        }
      } else {
        CustomSnackBar.show(context, message: response.data['message'] ?? "Update failed", isError: true, isModal: true);
      }
    } catch (e) {
      CustomSnackBar.show(context, message: "Error: $e", isError: true, isModal: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _showConfirmActionDialog({
    required String title,
    required String message,
    String confirmText = "Confirm",
  }) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500, height: 1.5),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.grey),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w900)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00796B),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(confirmText.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero, // Removed extra padding to prevent double-spacing
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8), 
            _buildValidatedField(
              label: "Username", 
              controller: usernameCtrl, 
              focusNode: usernameFocus, 
              error: usernameError, 
              errorColor: usernameColor,
              prefixIcon: Icons.person_outline_rounded,
            ),
            const SizedBox(height: 10), 
            _buildValidatedField(
              label: "Full Name", 
              controller: nameCtrl, 
              focusNode: nameFocus, 
              error: nameError, 
              errorColor: nameColor,
              prefixIcon: Icons.badge_outlined,
            ),
            const SizedBox(height: 10),
            _buildValidatedField(
              label: "Email Address", 
              controller: emailCtrl, 
              focusNode: emailFocus, 
              error: emailError, 
              errorColor: emailColor,
              keyboardType: TextInputType.emailAddress,
              prefixIcon: Icons.email_outlined,
            ),
            if (widget.user.role != 'admin') ...[
              const SizedBox(height: 10),
              _buildValidatedField(
                label: "Contact Number", 
                controller: phoneCtrl, 
                focusNode: phoneFocus, 
                error: phoneError, 
                errorColor: phoneColor,
                keyboardType: TextInputType.phone,
                prefixIcon: Icons.phone_outlined,
              ),
            ],
            const SizedBox(height: 10),
            if (widget.user.role == 'driver')
              _buildValidatedField(
                label: "Assigned Truck", 
                controller: truckCtrl, 
                focusNode: truckFocus, 
                error: truckError, 
                errorColor: truckColor,
                prefixIcon: Icons.local_shipping_outlined,
              )
            else if (widget.user.role == 'resident')
              _buildPurokDropdownWithValidation(
                selectedPurok, 
                _onPurokChanged,
                purokError,
                purokColor,
              ),
            const SizedBox(height: 20), 
            HoverActionButton(
              text: "Save Changes",
              loadingText: "Saving changes...",
              isLoading: _isLoading,
              onTap: _submit,
            ),
            const SizedBox(height: 12), 
          ],
        ),
      ),
    );
  }

  Widget _buildValidatedField({
    required String label, 
    required TextEditingController controller, 
    required FocusNode focusNode, 
    String? error, 
    Color? errorColor,
    TextInputType? keyboardType,
    IconData? prefixIcon,
  }) {
    bool hasFocus = focusNode.hasFocus;
    bool isError = error != null && (errorColor == null || errorColor == Colors.redAccent);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        const SizedBox(height: 2), 
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              if (hasFocus)
                BoxShadow(color: (isError ? Colors.redAccent : AppColors.tealText).withAlpha(30), blurRadius: 12, spreadRadius: 2)
            ],
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: keyboardType,
            cursorColor: const Color(0xFF424242),
            style: const TextStyle(fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              filled: true,
              fillColor: hasFocus ? Colors.white : const Color(0xFFF3F5F7),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: isError ? Colors.redAccent : Colors.grey.shade200, width: 1.2)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: isError ? Colors.redAccent : AppColors.tealText, width: 2.0)),
              prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: hasFocus ? (isError ? Colors.redAccent : AppColors.tealText) : Colors.grey.shade400, size: 20) : null,
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(error, style: TextStyle(color: errorColor ?? Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }

  Widget _buildPurokDropdownWithValidation(String selected, ValueChanged<String?> onChanged, String? error, Color? errorColor) {
    bool isError = error != null && (errorColor == null || errorColor == Colors.redAccent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text("Purok / Area", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        const SizedBox(height: 2), 
        InkWell(
          onTap: () => _showPurokModal(selected, onChanged),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F5F7), 
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isError ? Colors.redAccent : Colors.transparent, width: 1.2),
            ),
            child: Row(
              children: [
                Icon(Icons.location_on_outlined, color: isError ? Colors.redAccent : const Color(0xB400796B), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    selected,
                    style: const TextStyle(color: AppColors.inputLabel, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(Icons.keyboard_arrow_down_rounded, color: isError ? Colors.redAccent : AppColors.tealText, size: 24),
              ],
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(error, style: TextStyle(color: errorColor ?? Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }

  void _showPurokModal(String current, ValueChanged<String?> onSelected) {
    final bool isDesktop = MediaQuery.of(context).size.width >= 900;
    if (isDesktop) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Select Purok",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.tealText)),
                  const SizedBox(height: 24),
                  Flexible(
                    child: Scrollbar(
                      thumbVisibility: true,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _puroks.length,
                        itemBuilder: (context, index) {
                          final p = _puroks[index];
                          bool isSelected = current == p;
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
                            title: Text(p,
                                style: TextStyle(
                                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                                    color: isSelected ? const Color(0xFF00897B) : const Color(0xFF1A1A1A))),
                            trailing: isSelected
                                ? Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration:
                                        const BoxDecoration(color: Color(0xFF00897B), shape: BoxShape.circle),
                                    child: const Icon(Icons.check, color: Colors.white, size: 14))
                                : null,
                            onTap: () {
                              onSelected(p);
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Select Purok", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.tealText)),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _puroks.length,
                  itemBuilder: (context, index) {
                    final p = _puroks[index];
                    bool isSelected = current == p;
                    return ListTile(
                      title: Text(p, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.inputLabel)),
                      leading: Icon(Icons.location_on_outlined, color: isSelected ? AppColors.tealText : Colors.grey),
                      trailing: isSelected 
                        ? Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Color(0xFF00897B), shape: BoxShape.circle),
                            child: const Icon(Icons.check, color: Colors.white, size: 14),
                          )
                        : null,
                      onTap: () {
                        onSelected(p);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
