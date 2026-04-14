import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
      // This line forces the account selection dialog to appear
      await googleSignIn.signOut(); 
      
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
      if (mounted) {
        String errorMsg = e.toString();
        if (errorMsg.contains('12500')) {
          errorMsg = "Google Sign-In failed (Code 12500). Please check if your SHA-1 fingerprint is added in Firebase Console.";
        } else if (errorMsg.contains('10')) {
            errorMsg = "Google Sign-In failed (Code 10). Possible SHA-1/package name mismatch in Firebase.";
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to sign in: $errorMsg"),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
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
    // Safety check: if already logged in, the parent StreamBuilder should handle this,
    // but we add this here as a backup to prevent being stuck on the Login screen.
    if (FirebaseAuth.instance.currentUser != null) {
      // We don't return another widget because that might cause nested MaterialApps
      // or navigation issues. Instead, we let the StreamBuilder in main.dart do its job.
      // But we can add a small log or a direct push if it's really stuck.
    }
    
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
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Hero(
                  tag: 'logo',
                  child: Icon(Icons.handyman_outlined, color: Colors.white, size: 80),
                ),
                const SizedBox(height: 24),
                const Text(
                  "Namma\nWorkers",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "Connecting expert workers with those who need them.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withAlpha(200),
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 60),
                if (_isLoading)
                  const CircularProgressIndicator(color: Colors.white)
                else
                  ElevatedButton.icon(
                    onPressed: signInWithGoogle,
                    icon: Image.network(
                      'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_\"G\"_logo.svg/1200px-Google_\"G\"_logo.svg.png',
                      height: 24,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.login),
                    ),
                    label: const Text(
                      "Continue with Google",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 5,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
