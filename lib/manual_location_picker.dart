import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'map_confirm_page.dart';

class ManualLocationPicker extends StatefulWidget {
  final String service;
  final bool isScheduled;

  const ManualLocationPicker({
    super.key, 
    required this.service, 
    this.isScheduled = false
  });

  @override
  State<ManualLocationPicker> createState() => _ManualLocationPickerState();
}

class _ManualLocationPickerState extends State<ManualLocationPicker> {
  LatLng selected = const LatLng(12.9716, 77.5946); // Fallback (Bangalore)
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _setInitialLocation();
  }

  Future<void> _setInitialLocation() async {
    try {
      // Try to get current position for a better default
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low, // Fast fetch for initial map load
      );
      
      if (mounted) {
        final newPos = LatLng(position.latitude, position.longitude);
        setState(() {
          selected = newPos;
        });
        _mapController.move(newPos, 14);
      }
    } catch (e) {
      // If GPS fails, we stick to the default Bangalore position
      debugPrint("Could not set initial location: $e");
    }
  }

  Future<void> _searchLocation(String query) async {
    if (query.isEmpty) return;

    setState(() => _isSearching = true);
    try {
      final url = Uri.parse(
          "https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=1");
      
      final response = await http.get(url, headers: {
        'User-Agent': 'namma_workers_app_v1.0'
      });

      if (response.statusCode == 200) {
        final List results = json.decode(response.body);
        if (results.isNotEmpty) {
          final lat = double.parse(results[0]['lat']);
          final lon = double.parse(results[0]['lon']);
          final newPos = LatLng(lat, lon);

          setState(() {
            selected = newPos;
            _mapController.move(newPos, 15);
          });
        } else {
          _showError("Location not found. Try a different name.");
        }
      }
    } catch (e) {
      _showError("Error searching location. Please check your connection.");
    } finally {
      setState(() => _isSearching = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pick Location", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: selected,
              initialZoom: 13,
              onTap: (tapPosition, point) {
                setState(() => selected = point);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                userAgentPackageName: 'com.namma_workers.app',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: selected,
                    width: 80,
                    height: 80,
                    child: const Icon(Icons.location_pin, size: 45, color: Colors.red),
                  )
                ],
              ),
            ],
          ),

          // 🔍 SEARCH BAR UI
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, 5))],
                  ),
                  child: TextField(
                    controller: _searchController,
                    onSubmitted: (val) => _searchLocation(val),
                    decoration: InputDecoration(
                      hintText: "Search area, city or landmark...",
                      border: InputBorder.none,
                      suffixIcon: _isSearching 
                        ? const SizedBox(width: 20, height: 20, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)))
                        : IconButton(
                            icon: const Icon(Icons.search, color: Colors.blue),
                            onPressed: () => _searchLocation(_searchController.text),
                          ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                
                // Tip Overlay
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue[900]?.withAlpha(200),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                       Icon(Icons.touch_app, color: Colors.white, size: 16),
                       SizedBox(width: 8),
                       Text("Or tap on map to pick precisely", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MapConfirmPage(
                      service: widget.service,
                      lat: selected.latitude,
                      lng: selected.longitude,
                      isScheduled: widget.isScheduled,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[800],
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 10,
              ),
              child: const Text("Confirm Selection", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }
}
