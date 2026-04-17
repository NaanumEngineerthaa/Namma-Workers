import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'customer_page.dart';
import 'theme.dart';
import 'widgets/loading_screen.dart';

class CustomerProfileSetupPage extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  final bool isEditing;

  const CustomerProfileSetupPage({
    super.key,
    this.initialData,
    this.isEditing = false,
  });

  @override
  State<CustomerProfileSetupPage> createState() => _CustomerProfileSetupPageState();
}

class _CustomerProfileSetupPageState extends State<CustomerProfileSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  String _addressType = "home";
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _nameController.text = widget.initialData!['name'] ?? "";
      _phoneController.text = widget.initialData!['phone'] ?? "";
      _addressController.text = widget.initialData!['address'] ?? "";
      _addressType = widget.initialData!['addressType'] ?? "home";
    } else {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _nameController.text = user.displayName ?? "";
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        'addressType': _addressType,
        'email': user.email,
        'photoUrl': user.photoURL ?? "https://ui-avatars.com/api/?name=${_nameController.text}&background=random",
        'role': 'customer',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        if (widget.isEditing) {
          Navigator.pop(context);
        } else {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const CustomerPage()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error saving profile: $e"), backgroundColor: AppTheme.unselectedColor),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const PremiumLoadingScreen(message: "Saving Profile...");

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(
          widget.isEditing ? "Edit Profile" : "Setup Profile", 
          style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textColor)
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: widget.isEditing ? IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textColor),
          onPressed: () => Navigator.pop(context),
        ) : null,
      ),
      body: Container(
        height: MediaQuery.of(context).size.height,
        decoration: const BoxDecoration(gradient: AppTheme.bgGlowingEffect),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Personal Details",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppTheme.textColor),
                ),
                const SizedBox(height: 24),
                _buildTextField(
                  controller: _nameController,
                  label: "Full Name",
                  icon: Icons.person_rounded,
                  validator: (val) => val == null || val.isEmpty ? "Please enter your name" : null,
                ),
                const SizedBox(height: 20),
                _buildTextField(
                  controller: _phoneController,
                  label: "Phone Number",
                  icon: Icons.phone_iphone_rounded,
                  keyboardType: TextInputType.phone,
                  validator: (val) => val == null || val.length < 10 ? "Enter a valid phone number" : null,
                ),
                const SizedBox(height: 32),
                const Text(
                  "Service Address",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppTheme.textColor),
                ),
                const SizedBox(height: 24),
                _buildTextField(
                  controller: _addressController,
                  label: "Complete Address",
                  icon: Icons.location_on_rounded,
                  maxLines: 3,
                  validator: (val) => val == null || val.isEmpty ? "Please enter your address" : null,
                ),
                const SizedBox(height: 24),
                const Text("Address Type", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textColor)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildAddressTypeChip("home", Icons.home_rounded),
                    const SizedBox(width: 12),
                    _buildAddressTypeChip("office", Icons.work_rounded),
                  ],
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 8,
                      shadowColor: AppTheme.primaryColor.withAlpha(100),
                    ),
                    child: const Text("Complete Setup", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.subtitleColor, fontWeight: FontWeight.w500),
        prefixIcon: Icon(icon, color: AppTheme.primaryColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: AppTheme.primaryColor.withAlpha(20))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  Widget _buildAddressTypeChip(String type, IconData icon) {
    bool isSelected = _addressType == type;
    return GestureDetector(
      onTap: () => setState(() => _addressType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected ? AppTheme.glowingShadow : [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10)],
          border: Border.all(color: isSelected ? AppTheme.primaryColor : AppTheme.primaryColor.withAlpha(30)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: isSelected ? Colors.white : AppTheme.primaryColor),
            const SizedBox(width: 8),
            Text(
              type.toUpperCase(),
              style: TextStyle(
                color: isSelected ? Colors.white : AppTheme.primaryColor,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

