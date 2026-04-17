import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../theme.dart';

class NoInternetScreen extends StatelessWidget {
  const NoInternetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Lottie.asset(
                'assets/no internet screen/noInternet.json',
                width: 280,
                height: 280,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 24),
              const Text(
                "No Internet Connection",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
