import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'matching_page.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class MapConfirmPage extends StatefulWidget {
  final String service;
  final double lat;
  final double lng;

  const MapConfirmPage({
    super.key,
    required this.service,
    required this.lat,
    required this.lng,
  });

  @override
  State<MapConfirmPage> createState() => _MapConfirmPageState();
}

class _MapConfirmPageState extends State<MapConfirmPage> {
  bool _isBooking = false;

  Future<String> _getAddress(double lat, double lng) async {
    try {
      // Use Nominatim (free OSM reverse geocoding)
      final url = Uri.parse("https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1");
      final res = await http.get(url, headers: {'User-Agent': 'Namma Workers App'});
      
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final addr = data['address'] as Map<String, dynamic>;
        
        // Pick Area (Suburb/Neighbourhood) and District (City/District)
        String area = addr['suburb'] ?? addr['neighbourhood'] ?? addr['residential'] ?? addr['road'] ?? '';
        String district = addr['city_district'] ?? addr['city'] ?? addr['county'] ?? addr['state_district'] ?? '';
        
        if (area.isNotEmpty && district.isNotEmpty) {
          return "$area, $district";
        } else if (area.isNotEmpty || district.isNotEmpty) {
          return area.isNotEmpty ? area : district;
        }
      }
    } catch (e) {
      debugPrint("Reverse geocode failed: $e");
    }
    return "Current Location on Map";
  }

  Future<void> _createLiveJobWithLocation() async {
    setState(() => _isBooking = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final String readableAddress = await _getAddress(widget.lat, widget.lng);

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      String sType = "Home Service";
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        if (userData['addressType']?.toString().toLowerCase() == 'office') {
          sType = 'Office Service';
        }
      }

      final docRef = await FirebaseFirestore.instance.collection('jobs').add({
        'title': widget.service,
        'type': 'live',
        'status': 'active',
        'userId': user.uid,
        'workerId': null,
        'profession': widget.service,
        'amount': 500,
        'latitude': widget.lat,
        'longitude': widget.lng,
        'location': readableAddress,
        'requestedWorkers': [],
        'serviceType': sType,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        // Reset loading state so if user comes back, button is clickable again
        setState(() => _isBooking = false);
        
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MatchingPage(
              jobId: docRef.id,
              service: widget.service,
              userLat: widget.lat,
              userLng: widget.lng,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isBooking = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final LatLng point = LatLng(widget.lat, widget.lng);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Confirm Location", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: point,
              initialZoom: 16, // Zoom in for precision
            ),
            children: [
              TileLayer(
                urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                userAgentPackageName: 'com.namma_workers.app',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: point,
                    width: 100,
                    height: 100,
                    child: const Icon(Icons.location_pin, color: Colors.red, size: 50),
                  )
                ],
              ),
            ],
          ),

          // Action Overlay
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, -5))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.blue[50], shape: BoxShape.circle),
                        child: Icon(Icons.pin_drop, color: Colors.blue[800], size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.service, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            const Text("Finalize your booking location", style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isBooking ? null : _createLiveJobWithLocation,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[800],
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 60),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 10,
                      shadowColor: Colors.blue.withAlpha(50),
                    ),
                    child: _isBooking 
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("Confirm & Request Help", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
