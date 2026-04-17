import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'manual_location_picker.dart';
import 'map_confirm_page.dart';
import 'theme.dart';

class LocationChoicePage extends StatelessWidget {
  final String service;
  final bool isScheduled;

  const LocationChoicePage({
    super.key, 
    required this.service, 
    this.isScheduled = false
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text("Select Location", style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textColor)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Container(
        height: double.infinity,
        width: double.infinity,
        decoration: const BoxDecoration(gradient: AppTheme.bgGlowingEffect),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Where do you need help?",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppTheme.textColor),
              ),
              const SizedBox(height: 10),
              const Text(
                "Find the best workers for your precise location",
                style: TextStyle(color: AppTheme.subtitleColor, fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 48),

              _buildOptionCard(
                context: context,
                icon: Icons.my_location_rounded,
                title: "Current Location",
                subtitle: "Best for immediate onsite services",
                color: AppTheme.primaryColor,
                onTap: () async {
                  showDialog(
                    context: context, 
                    barrierDismissible: false, 
                    builder: (context) => Center(
                      child: Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
                        child: const CircularProgressIndicator(color: AppTheme.primaryColor),
                      ),
                    )
                  );

                  try {
                    final position = await Geolocator.getCurrentPosition();
                    if (context.mounted) Navigator.pop(context); 

                    if (context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MapConfirmPage(
                            service: service,
                            lat: position.latitude,
                            lng: position.longitude,
                            isScheduled: isScheduled,
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) Navigator.pop(context);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Error fetching location: $e"), backgroundColor: AppTheme.unselectedColor),
                      );
                    }
                  }
                },
              ),

              const SizedBox(height: 24),

              _buildOptionCard(
                context: context,
                icon: Icons.map_rounded,
                title: "Pick on Map",
                subtitle: "Select a different address manually",
                color: AppTheme.accentColor,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ManualLocationPicker(service: service, isScheduled: isScheduled),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppTheme.glowingShadow,
        border: Border.all(color: color.withAlpha(20)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withAlpha(20),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: color, size: 30),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title, 
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: AppTheme.textColor)
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle, 
                      style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 13, fontWeight: FontWeight.w500)
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, color: color.withAlpha(100), size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
