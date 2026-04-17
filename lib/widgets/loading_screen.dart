import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../theme.dart';

class PremiumLoadingScreen extends StatelessWidget {
  final String message;
  final bool isFullPage;
  const PremiumLoadingScreen({super.key, this.message = "Loading...", this.isFullPage = true});

  @override
  Widget build(BuildContext context) {
    Widget content = Center(
      child: SizedBox(
        height: isFullPage ? 250 : 150,
        child: Lottie.asset(
          'assets/animations/worker.json',
          fit: BoxFit.contain,
          repeat: true,
        ),
      ),
    );

    if (!isFullPage) return content;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: content,
    );
  }
}
