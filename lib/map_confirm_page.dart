import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'matching_page.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'customer_page.dart';
import 'theme.dart';

class MapConfirmPage extends StatefulWidget {
  final String service;
  final double lat;
  final double lng;
  final bool isScheduled;

  const MapConfirmPage({
    super.key,
    required this.service,
    required this.lat,
    required this.lng,
    this.isScheduled = false,
  });

  @override
  State<MapConfirmPage> createState() => _MapConfirmPageState();
}

class _MapConfirmPageState extends State<MapConfirmPage> {
  bool _isBooking = false;
  double _pricePerHour = 0.0; // Fetched from DB

  @override
  void initState() {
    super.initState();
    _fetchPrice();
  }

  Future<void> _fetchPrice() async {
    final prof = widget.service;
    
    try {
      final doc = await FirebaseFirestore.instance
          .collection('pricing')
          .doc(prof)
          .get(const GetOptions(source: Source.server));
          
      if (doc.exists && mounted) {
        setState(() {
          _pricePerHour = (doc.data()?['pricePerHour'] ?? 0).toDouble();
        });
      }
    } catch (e) {
       debugPrint("Error fetching pricing: $e");
    }
  }

  Future<String> _getAddress(double lat, double lng) async {
    try {
      final url = Uri.parse("https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1");
      final res = await http.get(url, headers: {'User-Agent': 'Namma Workers App'});
      
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final addr = data['address'] as Map<String, dynamic>;
        
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

  Future<void> _createLiveJobWithLocation(int hours, double tip) async {
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
        'status': 'searching',
        'customerId': user.uid,
        'workerId': null,
        'profession': widget.service,
        'amount': (_pricePerHour * hours) + tip,
        'baseAmount': _pricePerHour * hours,
        'pricePerHour': _pricePerHour,
        'hours': hours,
        'tip': tip,
        'latitude': widget.lat,
        'longitude': widget.lng,
        'location': readableAddress,
        'requestedWorkers': [],
        'serviceType': sType,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 30))),
      });

      if (mounted) {
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
          SnackBar(content: Text("Error: $e"), backgroundColor: AppTheme.unselectedColor),
        );
      }
    }
  }

  Future<void> _pickScheduleTime() async {
    final now = DateTime.now();
    final time = await showTimePicker(
      context: context, 
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primaryColor,
              onPrimary: Colors.white,
              onSurface: AppTheme.textColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (time == null) return;

    final startTime = DateTime(now.year, now.month, now.day, time.hour, time.minute);

    if (startTime.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cannot schedule in the past!"), backgroundColor: AppTheme.unselectedColor));
      return;
    }

    _showJobDetailsDialog(startTime);
  }

  void _showJobDetailsDialog([DateTime? startTime]) {
    int hours = 1;
    double tipAmount = 0.0;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            bool isLoadingPrice = _pricePerHour == 0;
            
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                top: 24, left: 24, right: 24,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                gradient: AppTheme.bgGlowingEffect,
                borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Align(
                     alignment: Alignment.center,
                     child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.primaryColor.withAlpha(50), borderRadius: BorderRadius.circular(10))),
                   ),
                   const SizedBox(height: 24),
                   const Text("Job Requirements", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.textColor)),
                   const SizedBox(height: 24),
                   Container(
                     padding: const EdgeInsets.all(16),
                     decoration: BoxDecoration(
                       color: Colors.white,
                       borderRadius: BorderRadius.circular(20),
                       boxShadow: AppTheme.glowingShadow,
                     ),
                     child: Row(
                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
                       children: [
                         const Text("Base Price", style: TextStyle(color: AppTheme.subtitleColor, fontWeight: FontWeight.w600)),
                         isLoadingPrice 
                           ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor))
                           : Text("₹$_pricePerHour / hr", style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textColor, fontSize: 18)),
                       ],
                     ),
                   ),
                   const SizedBox(height: 24),
                   const Text("Duration (Hours)", style: TextStyle(color: AppTheme.subtitleColor, fontWeight: FontWeight.bold)),
                   const SizedBox(height: 12),
                   Row(
                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                     children: [
                       Text("$hours Hour${hours > 1 ? 's' : ''}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.textColor)),
                       Row(
                         children: [
                           _buildRoundActionBtn(Icons.remove_rounded, (hours > 1 && !isLoadingPrice) ? () => setState(() => hours--) : null),
                           const SizedBox(width: 16),
                           _buildRoundActionBtn(Icons.add_rounded, !isLoadingPrice ? () => setState(() => hours++) : null),
                         ]
                       )
                     ]
                   ),
                   const SizedBox(height: 24),
                   const Text("Add a Tip (Optional)", style: TextStyle(color: AppTheme.subtitleColor, fontWeight: FontWeight.bold)),
                   const SizedBox(height: 12),
                   TextField(
                     enabled: !isLoadingPrice,
                     keyboardType: TextInputType.number,
                     inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                     decoration: InputDecoration(
                       hintText: "e.g. 50",
                       prefixIcon: const Icon(Icons.currency_rupee_rounded, color: AppTheme.primaryColor),
                       border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                       filled: true,
                       fillColor: Colors.white,
                       contentPadding: const EdgeInsets.all(20),
                     ),
                     onChanged: (val) {
                       setState(() {
                         tipAmount = double.tryParse(val) ?? 0.0;
                       });
                     },
                   ),
                   const SizedBox(height: 32),
                   ElevatedButton(
                     onPressed: isLoadingPrice ? null : () {
                       Navigator.pop(context);
                       if (startTime != null) {
                         final endTime = startTime.add(Duration(hours: hours));
                         _createScheduledJobWithLocation(startTime, endTime, hours, tipAmount);
                       } else {
                         _createLiveJobWithLocation(hours, tipAmount);
                       }
                     },
                     style: ElevatedButton.styleFrom(
                       minimumSize: const Size(double.infinity, 64),
                       backgroundColor: AppTheme.primaryColor,
                       foregroundColor: Colors.white,
                       elevation: 8,
                       shadowColor: AppTheme.primaryColor.withAlpha(100),
                       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                     ),
                     child: isLoadingPrice 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(
                        "Confirm & Book (₹${((_pricePerHour * hours) + tipAmount).toStringAsFixed(0)})", 
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)
                      ),
                   ),
                   const SizedBox(height: 12),
                ]
              ),
            );
          }
        );
      }
    );
  }

  Widget _buildRoundActionBtn(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: onTap == null ? AppTheme.subtitleColor.withAlpha(50) : AppTheme.primaryColor.withAlpha(20),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: onTap == null ? AppTheme.subtitleColor.withAlpha(100) : AppTheme.primaryColor, size: 30),
      ),
    );
  }

  Future<void> _createScheduledJobWithLocation(DateTime start, DateTime end, int hours, double tip) async {
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

      await FirebaseFirestore.instance.collection('jobs').add({
        'title': widget.service,
        'type': 'scheduled',
        'status': 'pending',
        'customerId': user.uid,
        'workerId': null,
        'profession': widget.service,
        'amount': (_pricePerHour * hours) + tip,
        'baseAmount': _pricePerHour * hours,
        'pricePerHour': _pricePerHour,
        'hours': hours,
        'tip': tip,
        'latitude': widget.lat,
        'longitude': widget.lng,
        'location': readableAddress,
        'serviceType': sType,
        'startTime': Timestamp.fromDate(start),
        'endTime': Timestamp.fromDate(end),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(end),
      });

      if (mounted) {
        setState(() => _isBooking = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Job scheduled successfully!"), backgroundColor: AppTheme.primaryColor));
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const CustomerPage(initialIndex: 2)),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isBooking = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: AppTheme.unselectedColor));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final LatLng point = LatLng(widget.lat, widget.lng);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text("Confirm Location", style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textColor)),
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
            options: MapOptions(
              initialCenter: point,
              initialZoom: 16, 
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
                    width: 80,
                    height: 80,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withAlpha(30),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.location_on_rounded, color: AppTheme.primaryColor, size: 50),
                    ),
                  )
                ],
              ),
            ],
          ),

          // Action Overlay
          Positioned(
            bottom: 24,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                gradient: AppTheme.bgGlowingEffect,
                borderRadius: BorderRadius.circular(32),
                boxShadow: AppTheme.glowingShadow,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppTheme.primaryColor.withAlpha(20), shape: BoxShape.circle),
                        child: const Icon(Icons.stars_rounded, color: AppTheme.primaryColor, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.service, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppTheme.textColor)),
                            const Text("Finalize your booking location", style: TextStyle(color: AppTheme.subtitleColor, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isBooking ? null : (widget.isScheduled ? _pickScheduleTime : _showJobDetailsDialog),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 64),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 10,
                      shadowColor: AppTheme.primaryColor.withAlpha(100),
                    ),
                    child: _isBooking 
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(widget.isScheduled ? "Confirm & Set Time" : "Confirm & Request Help", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
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
