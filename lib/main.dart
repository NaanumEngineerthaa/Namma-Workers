import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'customer_page.dart';
import 'worker_page.dart';
import 'login_page.dart';
import 'worker_profile_setup_page.dart';
import 'customer_profile_setup_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Namma Workers',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        initialData: FirebaseAuth.instance.currentUser,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(child: Text("Auth Error: ${snapshot.error}")),
            );
          }
          
          if (snapshot.connectionState == ConnectionState.waiting && snapshot.data == null) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }
          
          // User logged in
          if (snapshot.data != null) {
            return const RoleSelectionPage();
          }
          
          // User logged out
          return const LoginPage();
        },
      ),
    );
  }
}

class RoleSelectionPage extends StatefulWidget {
  const RoleSelectionPage({super.key});

  @override
  State<RoleSelectionPage> createState() => _RoleSelectionPageState();
}

class _RoleSelectionPageState extends State<RoleSelectionPage> {
  bool _isNavigating = false;

  Future<void> _handleRoleSelection(BuildContext context, String role) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _isNavigating) return;

    setState(() => _isNavigating = true);

    try {
      // 1. Save role immediately
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'role': role,
      }, SetOptions(merge: true));

      // 2. Check if profile exists (Check if name field is filled)
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data();

      if (!mounted) return;

      if (data == null || data['name'] == null) {
        // FIRST TIME USER -> Setup Form
        if (role == 'worker') {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkerProfileSetupPage()));
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerProfileSetupPage()));
        }
      } else {
        // EXISTING USER -> Respective Dashboard
        if (role == 'worker') {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkerPage()));
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerPage()));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.indigo[900]!,
              Colors.indigo[600]!,
            ],
          ),
        ),
        child: Stack(
          children: [
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Hero(
                          tag: 'logo',
                          child: Icon(Icons.handyman_outlined, color: Colors.white, size: 48),
                        ),
                        IconButton(
                          icon: const Icon(Icons.logout, color: Colors.white),
                          onPressed: () async {
                            await FirebaseAuth.instance.signOut();
                          },
                          tooltip: 'Logout',
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      "Hello, ${user?.displayName?.split(' ').first ?? 'User'}",
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Namma\nWorkers",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Connecting expert workers with those who need them.",
                      style: TextStyle(
                        color: Colors.white.withAlpha(200),
                        fontSize: 18,
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      "Begin Your Journey as",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildRoleCard(
                      context,
                      title: "I Need a Worker",
                      subtitle: "Hire local professionals for your home tasks.",
                      icon: Icons.search_rounded,
                      color: Colors.white,
                      textColor: Colors.indigo[900]!,
                      onTap: () => _handleRoleSelection(context, 'customer'),
                    ),
                    const SizedBox(height: 16),
                    _buildRoleCard(
                      context,
                      title: "I am a Worker",
                      subtitle: "Find jobs nearby and grow your earnings.",
                      icon: Icons.work_outline_rounded,
                      color: Colors.indigo[400]!.withAlpha(100),
                      border: Border.all(color: Colors.white.withAlpha(50), width: 1),
                      textColor: Colors.white,
                      onTap: () => _handleRoleSelection(context, 'worker'),
                    ),
                  ],
                ),
              ),
            ),
            if (_isNavigating)
              Container(
                color: Colors.black.withAlpha(100),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color textColor,
    BoxBorder? border,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(24),
          border: border,
          boxShadow: color == Colors.white
              ? [
                  BoxShadow(
                    color: Colors.black.withAlpha(50),
                    blurRadius: 15,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: textColor.withAlpha(20),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: textColor, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: textColor.withAlpha(150),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: textColor.withAlpha(100), size: 16),
          ],
        ),
      ),
    );
  }
}