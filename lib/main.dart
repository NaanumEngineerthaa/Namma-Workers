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

import 'theme.dart';
import 'widgets/loading_screen.dart';
import 'widgets/no_internet_wrapper.dart';
import 'widgets/force_update_page.dart';
import 'services/version_service.dart';

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
      theme: AppTheme.lightTheme,
      builder: (context, child) {
        return NoInternetWrapper(child: child!);
      },
      home: FutureBuilder<Map<String, dynamic>?>(
          future: VersionService.checkVersion(),
          builder: (context, versionSnapshot) {
            // While checking version
            if (versionSnapshot.connectionState == ConnectionState.waiting) {
              return const PremiumLoadingScreen(message: "Checking for updates...");
            }

            // If a force update is required
            if (versionSnapshot.hasData && versionSnapshot.data!['forceUpdate'] == true) {
              return ForceUpdatePage(updateUrl: versionSnapshot.data!['updateUrl']);
            }

            // Normal Flow
            return StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              initialData: FirebaseAuth.instance.currentUser,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Scaffold(
                    body: Center(child: Text("Auth Error: ${snapshot.error}")),
                  );
                }
                
                if (snapshot.connectionState == ConnectionState.waiting && snapshot.data == null) {
                  return const PremiumLoadingScreen(message: "Initializing Namma Workers...");
                }
                
                // User logged in
                if (snapshot.data != null) {
                  return const RoleSelectionPage();
                }
                
                // User logged out
                return const LoginPage();
              },
            );
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
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF6A1B9A), 
              Color(0xFF8E24AA),
              AppTheme.backgroundColor,
            ],
          ),
        ),
        child: Stack(
          children: [
            // Decorative Background Circles
            Positioned(
              top: -100,
              right: -50,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withAlpha(20),
                ),
              ),
            ),
            Positioned(
              bottom: -50,
              left: -50,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primaryColor.withAlpha(30),
                ),
              ),
            ),
            
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 30.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                       /* Hero(
                          tag: 'logo',
                          child: Container(
                            width: 95,
                            height: 95,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(30),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.asset(
                                'assets/logo.png', 
                                fit: BoxFit.cover,
                                cacheHeight: 130, // 2x height for high-PPI screens
                                cacheWidth: 130,
                              ),
                            ),
                          ),
                        ),*/
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(30),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 22),
                            onPressed: () async {
                              await FirebaseAuth.instance.signOut();
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Text(
                      "Hello, ${user?.displayName?.split(' ').first ?? 'User'}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "Welcome to",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 0),
                    const Text(
                      "Namma Workers",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        height: 0,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Transforming the way you find and provide professional services.",
                      style: TextStyle(
                        color: Colors.white.withAlpha(180),
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const Spacer(),
                    Center(
                      child: Container(
                        height: 4,
                        width: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(50),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      "HOW WOULD YOU LIKE TO CONTINUE?",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildRoleCard(
                      context,
                      title: "I Need a Service",
                      subtitle: "Find skilled professionals for any job",
                      icon: Icons.person_search_rounded,
                      isPrimary: true,
                      onTap: () => _handleRoleSelection(context, 'customer'),
                    ),
                    const SizedBox(height: 16),
                    _buildRoleCard(
                      context,
                      title: "I'm a Professional",
                      subtitle: "Join our network and start earning today",
                      icon: Icons.business_center_rounded,
                      isPrimary: false,
                      onTap: () => _handleRoleSelection(context, 'worker'),
                    ),
                  ],
                ),
              ),
            ),
            if (_isNavigating)
              const PremiumLoadingScreen(message: "Setting up your journey..."),
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
    required bool isPrimary,
    required VoidCallback onTap,
  }) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 400),
      tween: Tween<double>(begin: 0.95, end: 1.0),
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isPrimary ? Colors.white : Colors.white.withAlpha(40),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withAlpha(30), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isPrimary ? 40 : 10),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isPrimary ? AppTheme.primaryColor.withAlpha(20) : Colors.white.withAlpha(40),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, color: isPrimary ? AppTheme.primaryColor : Colors.white, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isPrimary ? AppTheme.textColor : Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: isPrimary ? AppTheme.subtitleColor : Colors.white.withAlpha(180),
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded, 
                color: isPrimary ? AppTheme.primaryColor.withAlpha(100) : Colors.white.withAlpha(100), 
                size: 14
              ),
            ],
          ),
        ),
      ),
    );
  }
}