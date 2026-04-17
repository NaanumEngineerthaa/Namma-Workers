import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';

class ForceUpdatePage extends StatelessWidget {
  final String updateUrl;
  const ForceUpdatePage({super.key, required this.updateUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.system_update_rounded,
                  size: 80,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                "Update Required",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textColor,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "To continue providing you with the best experience and latest security features, we require you to update the app to the latest version.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: AppTheme.subtitleColor,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: () async {
                    final url = Uri.parse(updateUrl);
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 8,
                    shadowColor: AppTheme.primaryColor.withAlpha(100),
                  ),
                  child: const Text(
                    "UPDATE NOW",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
