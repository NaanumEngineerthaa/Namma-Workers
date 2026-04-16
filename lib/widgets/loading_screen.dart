import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../theme.dart';

class PremiumLoadingScreen extends StatelessWidget {
  final String message;
  const PremiumLoadingScreen({super.key, this.message = "Loading..."});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF6A11CB),
              Color(0xFF2575FC),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 🔥 Lottie Animation
              SizedBox(
                height: 200,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 800),
                  opacity: 1,
                  child: Transform.scale(
                    scale: 1.05,
                    child: Lottie.asset(
                      'assets/animations/worker.json',
                      fit: BoxFit.contain,
                      repeat: true,
                      frameRate: FrameRate.max,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Title
              const Text(
                "Namma\nWorkers",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  height: 1.1,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(height: 40),
              const CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
