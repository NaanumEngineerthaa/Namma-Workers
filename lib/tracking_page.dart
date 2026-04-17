import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'theme.dart';

class TrackingPage extends StatefulWidget {
  final String jobId;
  final String workerId;
  final double userLat;
  final double userLng;

  const TrackingPage({
    super.key,
    required this.jobId,
    required this.workerId,
    required this.userLat,
    required this.userLng,
  });

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage> {
  StreamSubscription? _jobStatusSubscription;

  @override
  void initState() {
    super.initState();
    _listenToJobStatus();
  }

  @override
  void dispose() {
    _jobStatusSubscription?.cancel();
    super.dispose();
  }

  void _listenToJobStatus() {
    _jobStatusSubscription = FirebaseFirestore.instance
        .collection('jobs')
        .doc(widget.jobId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) return;
      
      final data = snapshot.data() as Map<String, dynamic>;
      final status = data['status'];

      // If the job is cancelled, completed, or closed by the worker or system
      if (status == 'cancelled' || status == 'completed' || status == 'closed') {
        if (mounted) {
          Navigator.popUntil(context, (route) => route.isFirst);
          String message = "Job was $status";
          if (status == 'completed') message = "Job Completed! 🎉";
          if (status == 'cancelled') message = "Job Cancelled 🔴";
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), backgroundColor: status == 'completed' ? AppTheme.primaryColor : AppTheme.unselectedColor),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text("Worker Tracking", style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textColor)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textColor), onPressed: () => Navigator.popUntil(context, (route) => route.isFirst)),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(widget.workerId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final workerLat = (data['latitude'] as num?)?.toDouble() ?? widget.userLat;
          final workerLng = (data['longitude'] as num?)?.toDouble() ?? widget.userLng;
          final workerName = data['name'] ?? "Worker";

          // Calculate distance and ETA
          final dist = _calculateDistance(widget.userLat, widget.userLng, workerLat, workerLng);
          final etaMinutes = (dist / 30) * 60; // 30km/h avg speed

          return Stack(
            children: [
              FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng((widget.userLat + workerLat)/2, (widget.userLng + workerLng)/2),
                  initialZoom: 14,
                ),
                children: [
                  TileLayer(
                    urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                    userAgentPackageName: 'com.namma_workers.app',
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [LatLng(widget.userLat, widget.userLng), LatLng(workerLat, workerLng)],
                        color: AppTheme.primaryColor.withAlpha(200),
                        strokeWidth: 4,
                        isDotted: true,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      // User Marker
                      Marker(
                        point: LatLng(widget.userLat, widget.userLng),
                        width: 80,
                        height: 80,
                        child: const Icon(Icons.person_pin_circle_rounded, color: AppTheme.primaryColor, size: 45),
                      ),
                      // Worker Marker
                      Marker(
                        point: LatLng(workerLat, workerLng),
                        width: 80,
                        height: 80,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: AppTheme.glowingShadow),
                              child: Text(workerName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10, color: AppTheme.textColor)),
                            ),
                            const Icon(Icons.directions_car_filled_rounded, color: AppTheme.primaryColor, size: 40),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Bottom Tracking Card
              Positioned(
                bottom: 30,
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Estimated Arrival", style: TextStyle(color: AppTheme.subtitleColor, fontSize: 14, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(
                                etaMinutes < 1 ? "Arriving Now" : "${etaMinutes.toInt()} mins",
                                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppTheme.primaryColor),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(color: AppTheme.primaryColor.withAlpha(20), borderRadius: BorderRadius.circular(16)),
                            child: Text("${dist.toStringAsFixed(1)} km", style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.primaryColor)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          CircleAvatar(radius: 25, backgroundColor: AppTheme.primaryColor.withAlpha(20), child: const Icon(Icons.person_rounded, color: AppTheme.primaryColor)),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(workerName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.textColor)),
                                const Text("Service Provider • On the way", style: TextStyle(color: AppTheme.subtitleColor, fontSize: 13, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                          IconButton(onPressed: () {}, icon: const Icon(Icons.phone_rounded, color: AppTheme.primaryColor, size: 28)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () async {
                          bool? confirm = await showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text("Cancel Booking?"),
                              content: const Text("Are you sure you want to cancel this booking? This will release the worker."),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("No")),
                                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Yes, Cancel", style: TextStyle(color: AppTheme.unselectedColor, fontWeight: FontWeight.bold))),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            try {
                              // 1. Update job status
                              await FirebaseFirestore.instance.collection('jobs').doc(widget.jobId).update({
                                'status': 'cancelled',
                                'cancelledAt': FieldValue.serverTimestamp(),
                                'updatedAt': FieldValue.serverTimestamp(),
                              });

                              // 2. Mark worker as NOT busy
                              await FirebaseFirestore.instance.collection('users').doc(widget.workerId).update({
                                'isBusy': false,
                              });

                              if (context.mounted) {
                                Navigator.popUntil(context, (route) => route.isFirst);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Booking Cancelled 🔴"), backgroundColor: AppTheme.unselectedColor),
                                );
                              }
                            } catch (e) {
                              debugPrint("Error cancelling: $e");
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.unselectedColor.withAlpha(20), 
                          foregroundColor: AppTheme.unselectedColor, 
                          minimumSize: const Size(double.infinity, 56), 
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), 
                          elevation: 0,
                          side: BorderSide(color: AppTheme.unselectedColor.withAlpha(50))
                        ),
                        child: const Text("Cancel Booking", style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () async {
                          bool? confirm = await showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text("Complete Booking?"),
                              content: const Text("Has the worker completed the job?"),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("No")),
                                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Yes, Complete", style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold))),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            try {
                              // Update job status
                              await FirebaseFirestore.instance.collection('jobs').doc(widget.jobId).update({
                                'status': 'completed',
                                'completedAt': FieldValue.serverTimestamp(),
                                'updatedAt': FieldValue.serverTimestamp(),
                              });

                              // Mark worker as NOT busy and increment total jobs
                              await FirebaseFirestore.instance.collection('users').doc(widget.workerId).update({
                                'isBusy': false,
                                'totalJobs': FieldValue.increment(1),
                              });

                              if (context.mounted) {
                                Navigator.popUntil(context, (route) => route.isFirst);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Job Completed! 🎉"), backgroundColor: AppTheme.primaryColor),
                                );
                              }
                            } catch (e) {
                              debugPrint("Error completing: $e");
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor, 
                          foregroundColor: Colors.white, 
                          minimumSize: const Size(double.infinity, 56), 
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), 
                          elevation: 8,
                          shadowColor: AppTheme.primaryColor.withAlpha(100),
                        ),
                        child: const Text("Mark as Completed", style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371; // km
    final dLat = (lat2 - lat1) * (pi / 180);
    final dLon = (lon2 - lon1) * (pi / 180);
    final a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * (pi / 180)) * cos(lat2 * (pi / 180)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }
}
