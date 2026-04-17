import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'theme.dart';
import 'widgets/loading_screen.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isLoading = false;

  Future<void> signInWithGoogle() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      
      // Attempt sign out first to ensure account picker always shows
      try {
        await googleSignIn.signOut(); 
      } catch (_) {}
      
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      debugPrint("Login Error: $e");
      String errorMsg = "Login failed. Please try again.";
      
      if (e.toString().contains("network_error")) {
        errorMsg = "Network error. Check your connection.";
      } else if (e.toString().contains("developer_error")) {
        errorMsg = "Configuration error (SHA-1/Package Name). Check Firebase Console.";
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
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
    if (_isLoading) {
      return const PremiumLoadingScreen(message: "Signing you in...");
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(gradient: AppTheme.bgGlowingEffect),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Hero(
                  tag: 'logo',
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundColor,
                      //borderRadius: BorderRadius.circular(32),
                      //boxShadow: AppTheme.glowingShadow,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset(
                        'assets/logo.png', 
                        height: 130, 
                        width: 130,
                        cacheHeight: 260, 
                        cacheWidth: 260,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 0),
                const Text(
                  "Namma Workers",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textColor,
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.2,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  "Connecting expert workers with those who need them.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.subtitleColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 60),
                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: ElevatedButton.icon(
                    onPressed: signInWithGoogle,
                    icon: ColorFiltered(
                      colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                      child: Image.network(
                        'https://www.gstatic.com/images/branding/product/2x/googleg_96dp.png',
                        height: 24,
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.account_circle_rounded),
                      ),
                    ),
                    label: const Text(
                      "Continue with Google",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      elevation: 12,
                      shadowColor: AppTheme.primaryColor.withAlpha(100),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

