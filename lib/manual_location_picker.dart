import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'map_confirm_page.dart';
import 'theme.dart';

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
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low, 
      );
      
      if (mounted) {
        final newPos = LatLng(position.latitude, position.longitude);
        setState(() {
          selected = newPos;
        });
        _mapController.move(newPos, 14);
      }
    } catch (e) {
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
      SnackBar(content: Text(msg), backgroundColor: AppTheme.unselectedColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text("Pick Location", style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textColor)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
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
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withAlpha(30),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.location_on_rounded, size: 45, color: AppTheme.primaryColor),
                    ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: AppTheme.glowingShadow,
                    border: Border.all(color: AppTheme.primaryColor.withAlpha(20)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onSubmitted: (val) => _searchLocation(val),
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textColor),
                    decoration: InputDecoration(
                      hintText: "Search area city or landmark...",
                      border: InputBorder.none,
                      hintStyle: const TextStyle(color: AppTheme.subtitleColor, fontWeight: FontWeight.normal),
                      suffixIcon: _isSearching 
                        ? const SizedBox(width: 20, height: 20, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor)))
                        : IconButton(
                            icon: const Icon(Icons.search_rounded, color: AppTheme.primaryColor),
                            onPressed: () => _searchLocation(_searchController.text),
                          ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                
                // Tip Overlay
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.textColor.withAlpha(220),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [BoxShadow(color: Colors.black.withAlpha(50), blurRadius: 10)],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                       Icon(Icons.touch_app_rounded, color: Colors.white, size: 18),
                       SizedBox(width: 10),
                       Text("Or tap on map to pick precisely", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
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
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 64),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                elevation: 10,
                shadowColor: AppTheme.primaryColor.withAlpha(100),
              ),
              child: const Text("Confirm Selection", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            ),
          )
        ],
      ),
    );
  }
}
