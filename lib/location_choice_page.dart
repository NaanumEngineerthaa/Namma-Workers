import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'manual_location_picker.dart';
import 'map_confirm_page.dart';

class LocationChoicePage extends StatelessWidget {
  final String service;

  const LocationChoicePage({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Select Location", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Where do you need help?",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              "Find the best workers for your precise location",
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            const SizedBox(height: 40),

            _buildOptionCard(
              context: context,
              icon: Icons.my_location_rounded,
              title: "Current Location",
              subtitle: "Best for immediate onsite services",
              color: Colors.blue,
              onTap: () async {
                // Show loading indicator
                showDialog(
                  context: context, 
                  barrierDismissible: false, 
                  builder: (context) => const Center(child: CircularProgressIndicator())
                );

                try {
                  final position = await Geolocator.getCurrentPosition();
                  Navigator.pop(context); // Remove loading

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MapConfirmPage(
                        service: service,
                        lat: position.latitude,
                        lng: position.longitude,
                      ),
                    ),
                  );
                } catch (e) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Error fetching location: $e")),
                  );
                }
              },
            ),

            const SizedBox(height: 20),

            _buildOptionCard(
              context: context,
              icon: Icons.map_rounded,
              title: "Pick on Map",
              subtitle: "Select a different address manually",
              color: Colors.orange,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ManualLocationPicker(service: service),
                  ),
                );
              },
            ),
          ],
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withAlpha(15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withAlpha(30), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color.withAlpha(150)),
          ],
        ),
      ),
    );
  }
}
