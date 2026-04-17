import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'worker_page.dart';
import 'theme.dart';
import 'widgets/loading_screen.dart';

class WorkerProfileSetupPage extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  final bool isEditing;

  const WorkerProfileSetupPage({
    super.key, 
    this.initialData, 
    this.isEditing = false,
  });

  @override
  State<WorkerProfileSetupPage> createState() => _WorkerProfileSetupPageState();
}

class _WorkerProfileSetupPageState extends State<WorkerProfileSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _experienceController = TextEditingController();
  String? _selectedProfession;
  File? _imageFile;
  String? _currentPhotoUrl;
  bool _isLoading = false;

  // Stream for dynamic categories
  Stream<List<Map<String, dynamic>>> _getCategories() {
    return FirebaseFirestore.instance
        .collection('pricing')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          final docs = snapshot.docs.map((doc) => doc.data()).toList();
          docs.sort((a, b) => (a['order'] ?? 0).compareTo(b['order'] ?? 0));
          return docs;
        });
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _nameController.text = widget.initialData!['name'] ?? '';
      _experienceController.text = widget.initialData!['experience']?.toString() ?? '';
      _selectedProfession = widget.initialData!['profession'];
      _currentPhotoUrl = widget.initialData!['photoUrl'];
    } else {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _nameController.text = user.displayName ?? '';
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    try {
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );
      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProfession == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your profession')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      String? photoUrl = _currentPhotoUrl ?? user.photoURL;

      if (_imageFile != null) {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('worker_photos')
            .child('${user.uid}.jpg');
        await storageRef.putFile(_imageFile!);
        photoUrl = await storageRef.getDownloadURL();
      }

      final workerData = {
        'uid': user.uid,
        'name': _nameController.text.trim(),
        'experience': int.tryParse(_experienceController.text.trim()) ?? 0,
        'profession': _selectedProfession,
        'photoUrl': photoUrl,
        'email': user.email,
        'role': 'worker',
        'isOnline': false,
        'latitude': null,
        'longitude': null,
        'profileCompleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastActive': FieldValue.serverTimestamp(),
      };

      if (!widget.isEditing) {
        workerData['createdAt'] = FieldValue.serverTimestamp();
        workerData['isVerified'] = false;
        workerData['rating'] = 5.0;
        workerData['totalJobs'] = 0;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(workerData, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));

      if (mounted) {
        if (widget.isEditing) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile updated successfully!')),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const WorkerPage()),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving profile: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const PremiumLoadingScreen(message: "Saving Profile...");

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(
          widget.isEditing ? 'Edit Profile' : 'Complete Profile',
          style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textColor),
        ),
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Stack(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.primaryColor.withAlpha(50), width: 2),
                        ),
                        child: CircleAvatar(
                          radius: 70,
                          backgroundColor: AppTheme.primaryColor.withAlpha(10),
                          backgroundImage: _imageFile != null
                              ? FileImage(_imageFile!)
                              : (_currentPhotoUrl != null
                                  ? NetworkImage(_currentPhotoUrl!)
                                  : (FirebaseAuth.instance.currentUser?.photoURL != null
                                      ? NetworkImage(FirebaseAuth.instance.currentUser!.photoURL!)
                                      : null)) as ImageProvider?,
                          child: _imageFile == null && _currentPhotoUrl == null && FirebaseAuth.instance.currentUser?.photoURL == null
                              ? const Icon(Icons.person_rounded, size: 70, color: AppTheme.primaryColor)
                              : null,
                        ),
                      ),
                      Positioned(
                        bottom: 5,
                        right: 5,
                        child: CircleAvatar(
                          backgroundColor: AppTheme.primaryColor,
                          radius: 22,
                          child: IconButton(
                            icon: const Icon(Icons.camera_alt_rounded, size: 22, color: Colors.white),
                            onPressed: _pickImage,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                _buildTextField(
                  controller: _nameController,
                  label: "Full Name",
                  icon: Icons.person_rounded,
                  validator: (val) => val == null || val.isEmpty ? "Please enter your name" : null,
                ),
                const SizedBox(height: 20),
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: _getCategories(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
                  }
                  final List<String> professionNames = snapshot.hasData 
                      ? snapshot.data!.map((e) => e['name'] as String).toList() 
                      : [];
                  
                  return DropdownButtonFormField<String>(
                    value: _selectedProfession,
                    decoration: InputDecoration(
                      labelText: 'Profession',
                      labelStyle: const TextStyle(color: AppTheme.subtitleColor, fontWeight: FontWeight.w500),
                      prefixIcon: const Icon(Icons.work_outline_rounded, color: AppTheme.primaryColor),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: AppTheme.primaryColor.withAlpha(20))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    items: professionNames.map((String profession) {
                      return DropdownMenuItem<String>(
                        value: profession,
                        child: Text(profession),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedProfession = newValue;
                      });
                    },
                    validator: (value) => value == null ? 'Please select your profession' : null,
                  );
                },
              ),
                const SizedBox(height: 20),
                _buildTextField(
                  controller: _experienceController,
                  label: "Years of Experience",
                  icon: Icons.history_rounded,
                  keyboardType: TextInputType.number,
                  validator: (val) => val == null || val.isEmpty ? 'Please enter experience' : null,
                ),
                const SizedBox(height: 48),
                SizedBox(
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
                    child: Text(
                      widget.isEditing ? 'Save Changes' : 'Complete Registration', 
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
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
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
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
}

