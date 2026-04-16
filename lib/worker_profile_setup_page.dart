import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'worker_page.dart';

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

  final List<String> _professions = [
    'Painter',
    'Plumber',
    'Electrician',
    'Carpenter',
    'Mason',
    'Mechanic',
    'Gardener',
    'Cleaner',
    'Driver',
    'Tailor',
    'Other',
  ];

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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Profile' : 'Complete Your Profile'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.indigo[900],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 60,
                            backgroundColor: Colors.indigo[50],
                            backgroundImage: _imageFile != null
                                ? FileImage(_imageFile!)
                                : (_currentPhotoUrl != null
                                    ? NetworkImage(_currentPhotoUrl!)
                                    : (FirebaseAuth.instance.currentUser?.photoURL != null
                                        ? NetworkImage(FirebaseAuth.instance.currentUser!.photoURL!)
                                        : null)) as ImageProvider?,
                            child: _imageFile == null && _currentPhotoUrl == null && FirebaseAuth.instance.currentUser?.photoURL == null
                                ? Icon(Icons.person, size: 60, color: Colors.indigo[200])
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: CircleAvatar(
                              backgroundColor: Colors.indigo,
                              radius: 20,
                              child: IconButton(
                                icon: const Icon(Icons.camera_alt, size: 20, color: Colors.white),
                                onPressed: _pickImage,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (value) => value == null || value.isEmpty ? 'Please enter your name' : null,
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      value: _selectedProfession,
                      decoration: InputDecoration(
                        labelText: 'Profession',
                        prefixIcon: const Icon(Icons.work_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: _professions.map((String profession) {
                        return DropdownMenuItem(
                          value: profession,
                          child: Text(profession),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedProfession = value;
                        });
                      },
                      validator: (value) => value == null ? 'Please select your profession' : null,
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _experienceController,
                      decoration: InputDecoration(
                        labelText: 'Years of Experience',
                        prefixIcon: const Icon(Icons.history),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) => value == null || value.isEmpty ? 'Please enter experience' : null,
                    ),
                    const SizedBox(height: 40),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo[900],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        widget.isEditing ? 'Save Changes' : 'Complete Registration', 
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
