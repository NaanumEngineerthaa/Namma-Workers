import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'worker_profile_setup_page.dart';
import 'worker_live_page.dart';
import 'live_requests_page.dart';
import 'scheduled_requests_page.dart';
import 'worker_history_page.dart';
import 'login_page.dart';
import 'theme.dart';
import 'widgets/loading_screen.dart';

class WorkerPage extends StatefulWidget {
  const WorkerPage({super.key});

  @override
  State<WorkerPage> createState() => _WorkerPageState();
}

class _WorkerPageState extends State<WorkerPage> {
  int _currentIndex = 0;
  bool _isOnline = false;
  LatLng? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  final MapController _mapController = MapController();
  final List<Marker> _markers = [];

  StreamSubscription<ServiceStatus>? _serviceStatusStreamSubscription;
  StreamSubscription<QuerySnapshot>? _jobRequestSubscription;
  StreamSubscription<QuerySnapshot>? _activeJobSubscription;

  @override
  void initState() {
    super.initState();
    _checkInitialLocation();
    _subscribeToServiceStatus();
    _listenForJobRequests();
    _listenToJobStatusChanges();
  }

  void _listenForJobRequests() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _jobRequestSubscription = FirebaseFirestore.instance
        .collection('job_requests')
        .where('workerId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docChanges) {
        if (doc.type == DocumentChangeType.added) {
          _showJobRequestDialog(doc.doc);
        }
      }
    });
  }

  void _listenToJobStatusChanges() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _activeJobSubscription = FirebaseFirestore.instance
        .collection('jobs')
        .where('workerId', isEqualTo: user.uid)
        .snapshots()
        .listen((snapshot) async {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.modified) {
          final data = change.doc.data() as Map<String, dynamic>;
          final status = data['status'];
          
          if (status == 'cancelled' || status == 'closed') {
            await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
              'isBusy': false,
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Job ${status == 'cancelled' ? 'Cancelled' : 'Closed'} by customer. 🔴"),
                  backgroundColor: AppTheme.unselectedColor,
                ),
              );
            }
          }
        }
      }
    });
  }

  void _showJobRequestDialog(DocumentSnapshot requestDoc) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => IncomingJobDialog(requestDoc: requestDoc, isOnline: _isOnline),
    );
  }

  @override
  void dispose() {
    _stopTracking();
    _serviceStatusStreamSubscription?.cancel();
    _jobRequestSubscription?.cancel();
    _activeJobSubscription?.cancel();
    super.dispose();
  }

  Stream<double> _monthlyEarnings(String workerId) {
    // start of the current month
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);

    return FirebaseFirestore.instance
        .collection('jobs')
        .where('workerId', isEqualTo: workerId)
        .where('status', isEqualTo: 'completed')
        .snapshots()
        .map((snapshot) {
          double total = 0;
          for (var doc in snapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
            
            // Fallback to updatedAt if completedAt is missing (e.g. during server sync)
            final Timestamp? ts = data['completedAt'] as Timestamp? ?? data['updatedAt'] as Timestamp?;
            final completedAt = ts?.toDate();
            
            if (completedAt != null && completedAt.isAfter(start)) {
              final rawVal = data['amount'] ?? data['price'] ?? 0;
              double val = 0;
              if (rawVal is num) {
                val = rawVal.toDouble();
              } else if (rawVal is String) {
                val = double.tryParse(rawVal) ?? 0;
              }
              total += val;
            }
          }
          return total;
        });
  }

  Future<void> _checkInitialLocation() async {
    // Only fetch if logged in
    if (FirebaseAuth.instance.currentUser == null) return;
    
    bool permissionGranted = await _handlePermission(showMessages: false);
    if (permissionGranted) {
      Position position = await Geolocator.getCurrentPosition();
      _updateUI(position);
    }
  }

  Future<void> _toggleOnlineStatus() async {
    if (_isOnline) {
      await _stopTracking();
    } else {
      bool permissionGranted = await _handlePermission();
      if (permissionGranted) {
        await _startTracking();
      }
    }
  }

  Future<bool> _handlePermission({bool showMessages = true}) async {
    LocationPermission permission;

    // Check permissions first - this helps wake up the OS on some devices
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted && showMessages) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Location permission was denied.")));
        }
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted && showMessages) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Location permissions are permanently denied."),
            action: SnackBarAction(label: "Settings", onPressed: () => Geolocator.openAppSettings()),
          ),
        );
      }
      return false;
    }

    // Now check if service is enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted && showMessages) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("GPS is OFF. Please turn it on in your phone's notification bar."),
            action: SnackBarAction(label: "Open Settings", onPressed: () => Geolocator.openLocationSettings()),
          ),
        );
      }
      return false;
    }

    return true;
  }

  // --- JOB MANAGEMENT LOGIC ---

  Future<bool> _hasActiveLiveJob(String uid) async {
    final jobs = await FirebaseFirestore.instance
        .collection('jobs')
        .where('workerId', isEqualTo: uid)
        .where('status', isEqualTo: 'picked')
        .where('type', isEqualTo: 'live')
        .get();
    return jobs.docs.isNotEmpty;
  }

  Future<bool> _hasTimeConflict(String uid, DateTime start, DateTime end) async {
    final jobs = await FirebaseFirestore.instance
        .collection('jobs')
        .where('workerId', isEqualTo: uid)
        .where('status', isEqualTo: 'picked')
        .where('type', isEqualTo: 'scheduled')
        .get();

    for (var doc in jobs.docs) {
      final data = doc.data();
      final existingStart = (data['startTime'] as Timestamp?)?.toDate();
      final existingEnd = (data['endTime'] as Timestamp?)?.toDate();

      if (existingStart != null && existingEnd != null) {
        // Check for overlap: [start, end] intersects [existingStart, existingEnd]
        if (start.isBefore(existingEnd) && end.isAfter(existingStart)) {
          return true; // Conflict detected
        }
      }
    }
    return false;
  }

  Future<void> _acceptJob(String jobId, Map<String, dynamic> jobData) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!_isOnline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("You must be ONLINE to accept jobs! 🔴"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    final type = jobData['type'] ?? 'live';

    if (type == 'live') {
      if (await _hasActiveLiveJob(user.uid)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Cannot accept! You already have an active Live job. 🚫")),
          );
        }
        return;
      }
    } else if (type == 'scheduled') {
      final start = (jobData['startTime'] as Timestamp).toDate();
      final end = (jobData['endTime'] as Timestamp).toDate();

      if (await _hasTimeConflict(user.uid, start, end)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Time conflict! You have another job scheduled for this time. ❌")),
          );
        }
        return;
      }
    }

    await FirebaseFirestore.instance.collection('jobs').doc(jobId).update({
      'workerId': user.uid,
      'status': 'picked',
      'acceptedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 🔥 SET ISBUSY for Live Jobs
    if (type == 'live') {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'isBusy': true,
      });
    }

    if (mounted) {
      if (type == 'live') {
        setState(() {
          _currentIndex = 2; // Move to Map Tab
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Job accepted successfully! ✅")),
      );
    }
  }

  Future<void> _rejectJob(String jobId) async {
    await FirebaseFirestore.instance.collection('jobs').doc(jobId).update({
      'status': 'rejected',
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Job proposal rejected.")),
      );
    }
  }

  Future<void> _completeJob(String jobId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 🏆 Set worker free and increment total jobs count
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'isBusy': false,
      'totalJobs': FieldValue.increment(1),
    });

    await FirebaseFirestore.instance.collection('jobs').doc(jobId).update({
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Job marked as completed! 🏁")),
      );
    }
  }

  Future<void> _cancelActiveJob(String jobId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'isBusy': false,
    });

    await FirebaseFirestore.instance.collection('jobs').doc(jobId).update({
      'status': 'cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Job cancelled by you. 🔴")),
      );
    }
  }

  // 🔄 Automatic Busy Sync Logic
  void _syncBusyState(List<DocumentSnapshot> activeJobs, bool currentBusy) {
    if (!mounted) return;
    
    final now = DateTime.now();
    bool shouldBeBusy = activeJobs.any((job) {
      final data = job.data() as Map<String, dynamic>;
      if (data['type'] == 'live') return true;
      if (data['type'] == 'scheduled') {
        final start = (data['startTime'] as Timestamp?)?.toDate();
        final end = (data['endTime'] as Timestamp?)?.toDate();
        // Busy if started and not yet passed end time (though UI button usually clears it)
        if (start != null && now.isAfter(start)) {
          if (end == null || now.isBefore(end)) return true;
        }
      }
      return false;
    });

    // Only update if mismatch
    if (shouldBeBusy != currentBusy) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'isBusy': shouldBeBusy,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  void _subscribeToServiceStatus() {
    _serviceStatusStreamSubscription = Geolocator.getServiceStatusStream().listen((ServiceStatus status) {
      if (status == ServiceStatus.enabled && _isOnline) {
        _startTracking();
      } else if (status == ServiceStatus.disabled) {
        _stopTracking();
      }
    });
  }

  Future<void> _startTracking() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!await _handlePermission()) {
      debugPrint("Location service or permission disabled");
      return;
    }

    // 🔥 Important: Cancel existing before starting new
    await _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;

    setState(() {
      _isOnline = true;
    });

    try {
      // Initialize availability in Firestore
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'isOnline': true,
        'isBusy': false,
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5, // Update every 5 meters
      );

      _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
        (Position position) {
          _updateLocationInFirestore(position);
          _updateUI(position);
        },
        onError: (error) {
          debugPrint("Location tracking error: $error");
          _stopTracking(); // Stop if there's a fatal error
        },
      );
      debugPrint("🚀 Continuous GPS Stream ACTIVE");

      Position currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      _updateLocationInFirestore(currentPosition);
      _updateUI(currentPosition);
      
    } catch (e) {
      debugPrint("Error starting location tracking: $e");
      _stopTracking();
    }
  }

  Future<void> _stopTracking() async {
    await _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'isOnline': false,
        'isBusy': false,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    if (mounted) {
      setState(() {
        _isOnline = false;
      });
    }
    debugPrint("🛑 Location tracking stopped");
  }

  void _updateLocationInFirestore(Position position) {
    if (!_isOnline) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'latitude': position.latitude,
      'longitude': position.longitude,
      'isOnline': true,
      'lastActive': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _updateUI(Position position) {
    if (!mounted) return;
    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
      _markers.clear();
      _markers.add(Marker(
          point: _currentPosition!,
          width: 80,
          height: 80,
          rotate: true,
          child: const Icon(
            Icons.location_on,
            color: AppTheme.primaryColor,
            size: 40,
          )));
    });

    if (_currentPosition != null && _currentIndex == 2) {
      _mapController.move(_currentPosition!, 15);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (FirebaseAuth.instance.currentUser == null) {
      return const LoginPage();
    }
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(_getPageTitle(), style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none)),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.bgGlowingEffect),
        child: _buildCurrentPage(),
      ),
      floatingActionButton: (_currentIndex == 0)
          ? FloatingActionButton.extended(
              onPressed: _toggleOnlineStatus,
              label: Text(_isOnline ? "Go Offline" : "Go Online"),
              icon: Icon(_isOnline ? Icons.power_settings_new : Icons.play_arrow),
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppTheme.primaryColor,
        unselectedItemColor: AppTheme.unselectedColor,
        backgroundColor: Colors.white,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: "Dashboard"),
          BottomNavigationBarItem(icon: Icon(Icons.wifi_rounded), label: "Live"),
          BottomNavigationBarItem(icon: Icon(Icons.map_rounded), label: "Map"),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month_rounded), label: "Schedule"),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline_rounded), label: "Profile"),
        ],
      ),
    );
  }

  String _getPageTitle() {
    switch (_currentIndex) {
      case 0: return "Worker Dashboard";
      case 1: return "Live Status";
      case 2: return "Live Map";
      case 3: return "My Schedule";
      case 4: return "My Profile";
      default: return "Worker Page";
    }
  }

  Widget _buildCurrentPage() {
    switch (_currentIndex) {
      case 0: return _buildDashboard();
      case 1: return WorkerLivePage(isOnline: _isOnline, onToggle: _toggleOnlineStatus);
      case 2: return _buildMapPage();
      case 3: return _buildSchedulePage();
      case 4: return _buildProfilePage();
      default: return _buildDashboard();
    }
  }

  Widget _buildProfilePage() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text("Please login"));

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots().asyncMap((event) async {
        await Future.delayed(const Duration(milliseconds: 1500));
        return event;
      }),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const PremiumLoadingScreen();
        if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: Text("Profile not found"));

        final data = snapshot.data!.data() as Map<String, dynamic>;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => WorkerProfileSetupPage(initialData: data, isEditing: true)));
                    },
                    icon: const Icon(Icons.edit_rounded, size: 20),
                    label: const Text("Edit Profile"),
                    style: TextButton.styleFrom(foregroundColor: AppTheme.primaryColor),
                  ),
                ],
              ),
              Center(
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.primaryColor.withAlpha(50), width: 4),
                      ),
                      child: CircleAvatar(
                        radius: 60,
                        backgroundColor: AppTheme.primaryColor.withAlpha(20),
                        backgroundImage: data['photoUrl'] != null 
                          ? NetworkImage(data['photoUrl']) 
                          : null,
                        child: data['photoUrl'] == null 
                          ? const Icon(Icons.person, size: 60, color: AppTheme.primaryColor) 
                          : null,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: AppTheme.primaryColor, shape: BoxShape.circle),
                        child: const Icon(Icons.verified, color: Colors.white, size: 24),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                data['name'] ?? 'Worker Name',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textColor),
              ),
              Text(
                data['email'] ?? 'Email Not Found',
                style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 16),
              ),
              const SizedBox(height: 32),
              _buildProfileTile(Icons.work_rounded, "Profession", data['profession'] ?? 'N/A'),
              FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('pricing').doc(data['profession'] ?? 'Other').get(),
                builder: (context, priceSnapshot) {
                  String priceText = "₹... / hr";
                  if (priceSnapshot.hasData && priceSnapshot.data!.exists) {
                    final priceData = priceSnapshot.data!.data() as Map<String, dynamic>;
                    priceText = "₹${priceData['pricePerHour'] ?? 0} / hr";
                  }
                  return _buildProfileTile(Icons.payments_rounded, "Hourly Price", priceText);
                },
              ),
              _buildProfileTile(Icons.history_edu_rounded, "Experience", "${data['experience'] ?? 0} Years"),
              _buildProfileTile(Icons.star_rounded, "Rating", (data['rating'] ?? 5.0).toString()),
              _buildProfileTile(Icons.work_outline, "Total Jobs", "${data['totalJobs'] ?? 0}"),
              _buildProfileTile(Icons.email_outlined, "Email", data['email'] ?? FirebaseAuth.instance.currentUser?.email ?? ""),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text("Logout from Service"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    side: const BorderSide(color: AppTheme.primaryColor),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProfileTile(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor.withAlpha(150),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primaryColor.withAlpha(20)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppTheme.primaryColor.withAlpha(20), shape: BoxShape.circle),
            child: Icon(icon, color: AppTheme.primaryColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 12, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textColor)),
              ],
            ),
          ),
        ],
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

  Widget _buildMapPage() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text("Please Login"));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('jobs')
          .where('workerId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'picked')
          .snapshots()
          .asyncMap((event) async {
            await Future.delayed(const Duration(milliseconds: 1500));
            return event;
          }),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const PremiumLoadingScreen();
        if (!snapshot.hasData) return const PremiumLoadingScreen();
        
        final snapshots = snapshot.data!.docs;
        final now = DateTime.now();

        // Filter for truly "Active" jobs (Live jobs or Scheduled jobs that have started)
        final docs = snapshots.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['type'] == 'live') return true;
          if (data['type'] == 'scheduled') {
            final start = (data['startTime'] as Timestamp?)?.toDate();
            return start != null && now.isAfter(start);
          }
          return false;
        }).toList();
        
        // No Active In-Progress Jobs -> Standard Passive Map
        if (docs.isEmpty) {
          return FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition ?? const LatLng(12.9716, 77.5946),
              initialZoom: 15,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.namma_workers.app',
              ),
              MarkerLayer(markers: _markers),
              if (_currentPosition == null)
                const Center(child: Text("Locating you...")),
            ],
          );
        }

        // Active Live Job Tracking
        final jobDoc = docs.first;
        final jobData = jobDoc.data() as Map<String, dynamic>;
        
        final customerLat = (jobData['latitude'] as num?)?.toDouble();
        final customerLng = (jobData['longitude'] as num?)?.toDouble();
        
        if (customerLat == null || customerLng == null || _currentPosition == null) {
           return const Center(child: Text("Waiting for exact coordinates..."));
        }
        
        final workerLat = _currentPosition!.latitude;
        final workerLng = _currentPosition!.longitude;
        
        final dist = _calculateDistance(workerLat, workerLng, customerLat, customerLng);
        final etaMinutes = (dist / 30) * 60; // Assumed 30km/h relative city speed

        return Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: LatLng((customerLat + workerLat)/2, (customerLng + workerLng)/2),
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
                      points: [LatLng(customerLat, customerLng), LatLng(workerLat, workerLng)],
                      color: AppTheme.primaryColor.withAlpha(200),
                      strokeWidth: 4,
                      isDotted: true,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
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
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 5)]),
                            child: const Text("You", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                          ),
                          const Icon(Icons.directions_car, color: AppTheme.primaryColor, size: 40),
                        ],
                      ),
                    ),
                    // Customer Marker
                    Marker(
                      point: LatLng(customerLat, customerLng),
                      width: 80,
                      height: 80,
                      child: const Icon(Icons.person_pin_circle, color: AppTheme.primaryColor, size: 45),
                    ),
                  ],
                ),
              ],
            ),
            
            // Floating Route Details
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, 5))],
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
                            const Text("Drive to Customer", style: TextStyle(color: Colors.grey, fontSize: 14)),
                            const SizedBox(height: 4),
                            Text(
                              etaMinutes < 1 ? "Arriving Now" : "${etaMinutes.toInt()} mins away",
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(color: AppTheme.primaryColor.withAlpha(20), borderRadius: BorderRadius.circular(16)),
                          child: Text("${dist.toStringAsFixed(1)} km", style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Navigation starting...")));
                            },
                            icon: const Icon(Icons.navigation),
                            label: const Text("Navigate"),
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          onPressed: () {}, 
                          style: IconButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor.withAlpha(20),
                            padding: const EdgeInsets.all(12),
                          ),
                          icon: const Icon(Icons.call, color: AppTheme.primaryColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _completeJob(jobDoc.id),
                        icon: const Icon(Icons.check_circle),
                        label: const Text("Mark Job as Completed", style: TextStyle(fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryColor,
                          side: const BorderSide(color: AppTheme.primaryColor, width: 2),
                          padding: const EdgeInsets.symmetric(vertical: 14)
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          bool? confirm = await showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text("Cancel Job?"),
                              content: const Text("Are you sure you want to cancel this picked job?"),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("No")),
                                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Yes, Cancel", style: const TextStyle(color: AppTheme.unselectedColor, fontWeight: FontWeight.bold))),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await _cancelActiveJob(jobDoc.id);
                          }
                        },
                        icon: const Icon(Icons.cancel),
                        label: const Text("Cancel Job", style: TextStyle(fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.unselectedColor,
                          side: const BorderSide(color: AppTheme.unselectedColor, width: 2),
                          padding: const EdgeInsets.symmetric(vertical: 14)
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDashboard() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text("Please Login"));

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots().asyncMap((event) async {
        await Future.delayed(const Duration(milliseconds: 1500));
        return event;
      }),
      builder: (context, profileSnapshot) {
        if (profileSnapshot.connectionState == ConnectionState.waiting) return const PremiumLoadingScreen();
        if (!profileSnapshot.hasData) return const PremiumLoadingScreen();
        
        final profileData = profileSnapshot.data?.data() as Map<String, dynamic>? ?? {};
        final int target = profileData['monthlyTarget'] ?? 15000;
        final String profession = profileData['profession'] ?? '';

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('jobs')
              .where('workerId', isEqualTo: user.uid)
              .where('status', isEqualTo: 'picked')
              .snapshots(),
          builder: (context, acceptedSnapshot) {
            if (acceptedSnapshot.connectionState == ConnectionState.waiting) return const PremiumLoadingScreen();
            final List<DocumentSnapshot> activeJobs = acceptedSnapshot.data?.docs ?? [];
            final bool alreadyHasLiveJob = activeJobs.any((doc) => doc['type'] == 'live');

            // 🔄 Automatic Sync for isBusy (Scheduled Jobs)
            _syncBusyState(activeJobs, profileData['isBusy'] ?? false);

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header / Status
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Service Status", style: TextStyle(color: AppTheme.subtitleColor, fontSize: 14)),
                          Text(
                            _isOnline ? "ONLINE" : "OFFLINE",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _isOnline ? AppTheme.primaryColor : AppTheme.unselectedColor,
                            ),
                          ),
                        ],
                      ),
                      _buildEarningsMini(),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  _buildEarningsCard(target),
                  const SizedBox(height: 30),

                  // 1. LIVE JOBS SECTION (PENDING)
                  _buildSectionHeader("Live Requests", true),
                  const SizedBox(height: 12),
                  _buildLiveJobsStream(user.uid, alreadyHasLiveJob, profession, limit: 2),

                  const SizedBox(height: 30),

                  // 2. SCHEDULED JOBS SECTION (PENDING)
                  _buildSectionHeader("Scheduled Bookings", true),
                  const SizedBox(height: 12),
                  _buildScheduledJobsStream(user.uid, activeJobs, profession, limit: 2),

                  const SizedBox(height: 30),

                  // 3. MY TIMELINE (ACCEPTED JOBS)
                  _buildSectionHeader("My Timeline (Accepted)", false),
                  const SizedBox(height: 12),
                  _buildAcceptedJobsTimeline(user.uid),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, bool showBadge) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textColor)),
          ],
        ),
        if (showBadge)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withAlpha(20),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              "Pending", 
              style: TextStyle(color: AppTheme.primaryColor, fontSize: 12, fontWeight: FontWeight.bold)
            ),
          ),
      ],
    );
  }

  Widget _buildLiveJobsStream(String uid, bool alreadyHasLiveJob, String profession, {int? limit}) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('jobs')
          .where('type', isEqualTo: 'live')
          .where('status', isEqualTo: 'searching')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const PremiumLoadingScreen(isFullPage: false);
        if (!snapshot.hasData) return const PremiumLoadingScreen(isFullPage: false);
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return _buildEmptyState("No live requests currently");

        final now = DateTime.now();
        List<DocumentSnapshot> validFilteredDocs = [];

        for (var doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final title = (data['title'] ?? '').toString().toLowerCase();
          final prof = profession.toLowerCase();
          
          if (title.contains(prof) || prof.contains(title)) {
            final isExpired = data['isExpired'] ?? false;
            if (isExpired) continue;

            final expiresAtField = (data['expiresAt'] as Timestamp?)?.toDate();
            final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
            final effectiveExpiresAt = expiresAtField ?? createdAt.add(const Duration(hours: 24)); 

            if (now.isAfter(effectiveExpiresAt)) {
              doc.reference.update({'isExpired': true});
              continue;
            } else {
              validFilteredDocs.add(doc);
            }
          }
        }

        final filteredDocs = validFilteredDocs;

        if (filteredDocs.isEmpty) return _buildEmptyState("No requests matching your profession ($profession)");

        // 🕒 Sort by createdAt Ascending (Actually Descending is better for "Newest first" but user asked for "less time is on top" which I did as Desc)
        // Wait, I did t2.compareTo(t1) which is Descending (Newest first).
        filteredDocs.sort((a, b) {
          final t1 = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
          final t2 = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
          return t2.compareTo(t1);
        });

        final bool hasMore = limit != null && filteredDocs.length > limit;
        final displayDocs = limit != null ? filteredDocs.take(limit).toList() : filteredDocs;

        return Column(
          children: [
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: displayDocs.length,
              itemBuilder: (context, index) => _buildJobCard(
                displayDocs[index], 
                isDisabled: alreadyHasLiveJob || !_isOnline,
                disabledReason: alreadyHasLiveJob ? "Already has active live job" : (!_isOnline ? "Go ONLINE to accept requests" : null),
              ),
            ),
            if (hasMore)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Center(
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LiveRequestsPage(
                            profession: profession,
                            currentPosition: _currentPosition != null ? Position(
                                latitude: _currentPosition!.latitude,
                                longitude: _currentPosition!.longitude,
                                timestamp: DateTime.now(),
                                accuracy: 0,
                                altitude: 0,
                                altitudeAccuracy: 0,
                                heading: 0,
                                headingAccuracy: 0,
                                speed: 0,
                                speedAccuracy: 0,
                            ) : null,
                            alreadyHasLiveJob: alreadyHasLiveJob,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                    label: const Text("View More Live Requests", style: TextStyle(fontWeight: FontWeight.bold)),
                    style: TextButton.styleFrom(foregroundColor: Colors.orange[800], padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildScheduledJobsStream(String uid, List<DocumentSnapshot> activeJobs, String profession, {int? limit}) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('jobs')
          .where('type', isEqualTo: 'scheduled')
          .where('status', whereIn: ['active', 'pending'])
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const PremiumLoadingScreen(isFullPage: false);
        if (!snapshot.hasData) return const PremiumLoadingScreen(isFullPage: false);
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return _buildEmptyState("No scheduled jobs found");

        final filteredDocs = docs.where((pendingDoc) {
          final pData = pendingDoc.data() as Map<String, dynamic>;
          
          // 1. Filter by profession
          final title = (pData['title'] ?? '').toString().toLowerCase();
          final prof = profession.toLowerCase();
          final isMatch = title.contains(prof) || prof.contains(title);
          if (!isMatch) return false;

          // 1.5 Filter and auto-close if expired
          final isExpired = pData['isExpired'] ?? false;
          if (isExpired) return false;

          final expiresAtField = (pData['expiresAt'] as Timestamp?)?.toDate();
          final createdAt = (pData['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
          final startFallback = (pData['startTime'] as Timestamp?)?.toDate() ?? createdAt;
          final effectiveExpiresAt = expiresAtField ?? startFallback.add(Duration(hours: pData['hours'] ?? 1));

          if (DateTime.now().isAfter(effectiveExpiresAt)) {
             pendingDoc.reference.update({'isExpired': true});
             return false;
          }

          // 2. Conflict check
          final pStart = (pData['startTime'] as Timestamp?)?.toDate();
          final pEnd = (pData['endTime'] as Timestamp?)?.toDate();

          if (pStart == null || pEnd == null) return false;

          /*
          for (var activeDoc in activeJobs) {
            final aData = activeDoc.data() as Map<String, dynamic>;
            final aStart = (aData['startTime'] as Timestamp?)?.toDate();
            final aEnd = (aData['endTime'] as Timestamp?)?.toDate();

            if (aStart != null && aEnd != null) {
              if (pStart.isBefore(aEnd) && pEnd.isAfter(aStart)) {
                return false; 
              }
            }
          }
          */
          return true;
        }).toList();

        if (filteredDocs.isEmpty) return _buildEmptyState("No pending jobs match your profession or schedule");

        // 🕒 Sort by startTime Descending (Newest first) 
        filteredDocs.sort((a, b) {
          final t1 = (a['startTime'] as Timestamp?)?.toDate() ?? DateTime.now();
          final t2 = (b['startTime'] as Timestamp?)?.toDate() ?? DateTime.now();
          return t1.compareTo(t2);
        });

        final bool hasMore = limit != null && filteredDocs.length > limit;
        final displayDocs = limit != null ? filteredDocs.take(limit).toList() : filteredDocs;

        return Column(
          children: [
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: displayDocs.length,
              itemBuilder: (context, index) => _buildJobCard(
                displayDocs[index], 
                isDisabled: !_isOnline,
                disabledReason: !_isOnline ? "Go ONLINE to accept requests" : null,
              ),
            ),
            if (hasMore)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Center(
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ScheduledRequestsPage(
                            profession: profession,
                            currentPosition: _currentPosition != null ? Position(
                                latitude: _currentPosition!.latitude,
                                longitude: _currentPosition!.longitude,
                                timestamp: DateTime.now(),
                                accuracy: 0, altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0,
                            ) : null,
                            activeJobs: activeJobs,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                    label: const Text("View More Scheduled Bookings", style: TextStyle(fontWeight: FontWeight.bold)),
                    style: TextButton.styleFrom(foregroundColor: Colors.orange[800], padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildAcceptedJobsTimeline(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('jobs')
          .where('workerId', isEqualTo: uid)
          .where('status', isEqualTo: 'picked')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _buildEmptyState("Error loading jobs");
        if (!snapshot.hasData) return const PremiumLoadingScreen(isFullPage: false);
        
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return _buildEmptyState("Your timeline is empty");

        // 🕒 Sort by acceptedAt Descending
        final sortedDocs = docs.toList()..sort((a, b) {
          final t1 = (a['acceptedAt'] as Timestamp?)?.toDate() ?? DateTime.now();
          final t2 = (b['acceptedAt'] as Timestamp?)?.toDate() ?? DateTime.now();
          return t2.compareTo(t1);
        });

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: sortedDocs.length,
          itemBuilder: (context, index) => _buildJobCard(sortedDocs[index], isAccepted: true),
        );
      },
    );
  }

  Widget _buildEmptyState(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Center(child: Text(msg, style: TextStyle(color: Colors.grey[500]))),
    );
  }

  Widget _buildEarningsMini() {
    final user = FirebaseAuth.instance.currentUser;
    return StreamBuilder<double>(
      stream: _monthlyEarnings(user!.uid),
      builder: (context, snapshot) {
        final earnings = snapshot.data ?? 0;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withAlpha(20),
            borderRadius: BorderRadius.circular(20),
          ),
          child: InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkerHistoryPage())),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined, size: 16, color: AppTheme.primaryColor),
                const SizedBox(width: 4),
                Text(
                  "₹${NumberFormat('#,###').format(earnings)}", 
                  style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)
                ),
              ],
            ),
          ),
        );
      }
    );
  }

  Widget _buildEarningsCard(int target) {
    final user = FirebaseAuth.instance.currentUser;
    return StreamBuilder<double>(
      stream: _monthlyEarnings(user!.uid),
      builder: (context, snapshot) {
        final earnings = snapshot.data ?? 0;
        final progress = (earnings / target).clamp(0.0, 1.0);

        return GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkerHistoryPage())),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.primaryColor, AppTheme.accentColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: AppTheme.glowingShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Total Earnings This Month",
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  "₹${earnings.toStringAsFixed(0)}",
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildProgressBar(progress, target),
              ],
            ),
          ),
        );
      }
    );
  }

  Widget _buildProgressBar(double progress, int target) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Goal: ₹$target",
              style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            GestureDetector(
              onTap: _showTargetEditDialog,
              child: const Icon(Icons.edit, color: Colors.white70, size: 14),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 6,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(20),
            borderRadius: BorderRadius.circular(3),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showTargetEditDialog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final currentTarget = doc.data()?['monthlyTarget'] ?? 15000;
    final controller = TextEditingController(text: currentTarget.toString());

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Set Monthly Goal"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: "Target Amount (₹)",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              final newTarget = int.tryParse(controller.text);
              if (newTarget != null && newTarget > 0) {
                await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
                  'monthlyTarget': newTarget,
                });
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text("Update"),
          ),
        ],
      ),
    );
  }

  Widget _buildJobCard(DocumentSnapshot doc, {bool isAccepted = false, bool isDisabled = false, String? disabledReason}) {
    final data = doc.data() as Map<String, dynamic>;
    final title = data['title'] ?? 'Job';
    final address = data['location'] ?? 'Address N/A';
    final price = (data['amount'] ?? data['price'] ?? 'TBD').toString();
    final type = data['type'] ?? 'live';
    final userId = data['customerId'] ?? data['userId'] ?? '';
    
    String _getRelativeTime(DateTime dateTime) {
      final Duration diff = DateTime.now().difference(dateTime);
      if (diff.inDays >= 7) return "${(diff.inDays / 7).floor()} weeks ago";
      if (diff.inDays >= 1) return "${diff.inDays} days ago";
      if (diff.inHours >= 1) return "${diff.inHours} hours ago";
      if (diff.inMinutes >= 1) return "${diff.inMinutes} mins ago";
      return "Just now";
    }

    String timeDisplay = "Now";
    if (type == 'scheduled') {
      final start = (data['startTime'] as Timestamp?)?.toDate();
      final end = (data['endTime'] as Timestamp?)?.toDate();
      if (start != null && end != null) {
        timeDisplay = "${DateFormat('jm').format(start)} - ${DateFormat('jm').format(end)}";
      }
    } else {
      final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
      if (createdAt != null) {
        timeDisplay = _getRelativeTime(createdAt);
      }
    }

    // Distance calculation
    String distanceStr = "N/A";
    if (_currentPosition != null && data['latitude'] != null && data['longitude'] != null) {
      double dist = Geolocator.distanceBetween(
        _currentPosition!.latitude, 
        _currentPosition!.longitude, 
        (data['latitude'] as num).toDouble(), 
        (data['longitude'] as num).toDouble()
      );
      distanceStr = "${(dist / 1000).toStringAsFixed(1)} km away";
    }

    return Opacity(
      opacity: isDisabled ? 0.6 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Badges and Price
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        type.toString().toUpperCase(),
                        style: const TextStyle(
                          color: AppTheme.primaryColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(distanceStr, style: const TextStyle(fontSize: 12, color: AppTheme.subtitleColor, fontWeight: FontWeight.w500)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text("₹$price", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                    if (data['hours'] != null)
                      Text(
                        "${data['hours']} hr${data['hours'] > 1 ? 's' : ''} ${data['tip'] != null && data['tip'] > 0 ? '+ ₹${data['tip']} tip' : ''}",
                        style: TextStyle(color: Colors.grey[600], fontSize: 11),
                      )
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Row 2: Customer Name (Bold Header)
            FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
              builder: (context, snapshot) {
                String userName = "Loading...";
                if (snapshot.hasData && snapshot.data!.exists) {
                  userName = (snapshot.data!.data() as Map<String, dynamic>)['name'] ?? "Unknown User";
                }
                return Text(userName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold));
              },
            ),
            const SizedBox(height: 4),

            // Row 3: Profession / Title (Subtitle)
            Text(title, style: const TextStyle(fontSize: 16, color: AppTheme.primaryColor, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),

            // Row 4: Service Type
            Row(
              children: [
                const Icon(Icons.home_work_outlined, color: AppTheme.subtitleColor, size: 16),
                const SizedBox(width: 4),
                Text(data['serviceType'] ?? "Home Service", style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 4),

            // Row 5: Location
            Row(
              children: [
                const Icon(Icons.location_on_outlined, color: AppTheme.subtitleColor, size: 16),
                const SizedBox(width: 4),
                Expanded(child: Text(address, style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 13))),
              ],
            ),
            const SizedBox(height: 4),

            // Row 5: Time
            Row(
              children: [
                const Icon(Icons.access_time, color: AppTheme.subtitleColor, size: 16),
                const SizedBox(width: 4),
                Text(timeDisplay, style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 13)),
              ],
            ),

            if (isDisabled && disabledReason != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  "⚠ $disabledReason",
                  style: const TextStyle(color: AppTheme.unselectedColor, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),

            const SizedBox(height: 16),
            
            if (!isAccepted)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isDisabled ? null : () => _rejectJob(doc.id),
                      child: const Text("Reject"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isDisabled ? null : () => _acceptJob(doc.id, data),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text("Accept"),
                    ),
                  ),
                ],
              )
            else
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _completeJob(doc.id),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text("Mark as Completed"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        bool? confirm = await showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text("Cancel Job?"),
                            content: const Text("Are you sure you want to cancel this picked job?"),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("No")),
                              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Yes, Cancel", style: TextStyle(color: Colors.red))),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await _cancelActiveJob(doc.id);
                        }
                      },
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text("Cancel Job"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red[600],
                        side: BorderSide(color: Colors.red[600]!),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }


  Widget _buildSchedulePage() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text("Please Login"));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('jobs')
          .where('workerId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'picked')
          .snapshots()
          .asyncMap((event) async {
            await Future.delayed(const Duration(milliseconds: 1500));
            return event;
          }),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const PremiumLoadingScreen();
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Active Schedule", 
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppTheme.textColor)
              ),
              const SizedBox(height: 8),
              const Text(
                "These are your currently accepted and pending jobs.", 
                style: TextStyle(color: AppTheme.subtitleColor, fontSize: 15, fontWeight: FontWeight.w500)
              ),
              const SizedBox(height: 32),
              _buildTimelineContent(snapshot),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTimelineContent(AsyncSnapshot<QuerySnapshot> snapshot) {
    if (snapshot.hasError) return _buildEmptyState("Error loading schedule");
    
    final docs = snapshot.data?.docs ?? [];
    if (docs.isEmpty) return _buildEmptyState("Your timeline is empty");

    final sortedDocs = docs.toList()..sort((a, b) {
      final t1 = (a.data() as Map<String, dynamic>)['acceptedAt'] as Timestamp?;
      final t2 = (b.data() as Map<String, dynamic>)['acceptedAt'] as Timestamp?;
      return (t2 ?? Timestamp.now()).compareTo(t1 ?? Timestamp.now());
    });

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sortedDocs.length,
      itemBuilder: (context, index) => _buildJobCard(sortedDocs[index], isAccepted: true),
    );
  }
}

class IncomingJobDialog extends StatefulWidget {
  final DocumentSnapshot requestDoc;
  final bool isOnline;

  const IncomingJobDialog({super.key, required this.requestDoc, required this.isOnline});

  @override
  State<IncomingJobDialog> createState() => _IncomingJobDialogState();
}

class _IncomingJobDialogState extends State<IncomingJobDialog> {
  int _secondsLeft = 300;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 0) {
        timer.cancel();
        if (mounted) Navigator.pop(context);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _accept() async {
    if (!widget.isOnline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You must be ONLINE to accept jobs! 🔴"), backgroundColor: Colors.redAccent),
        );
        Navigator.pop(context);
      }
      return;
    }
    final req = widget.requestDoc;
    final jobId = req['jobId'];
    final workerId = req['workerId'];

    try {
      // 1. Update job as picked
      await FirebaseFirestore.instance.collection('jobs').doc(jobId).update({
        'status': 'picked',
        'workerId': workerId,
        'acceptedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 2. Mark worker as busy
      await FirebaseFirestore.instance.collection('users').doc(workerId).update({
        'isBusy': true,
      });

      // 3. Update request status
      await req.reference.update({'status': 'picked'});

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Job Accepted! 🚀"), backgroundColor: Colors.green));
      }
    } catch (e) {
       debugPrint("Error accepting: $e");
    }
  }



  Future<void> _reject() async {
    await widget.requestDoc.reference.update({'status': 'rejected'});
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    String minutes = (_secondsLeft ~/ 60).toString();
    String seconds = (_secondsLeft % 60).toString().padLeft(2, '0');

    final reqData = widget.requestDoc.data() as Map<String, dynamic>? ?? {};
    final price = reqData['amount'] ?? 0;
    final hours = reqData['hours'];
    final tip = reqData['tip'];

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Row(
        children: [
          Icon(Icons.bolt, color: Colors.orange),
          SizedBox(width: 8),
          Text("Live Job Request", style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Service Needed:", style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          Text(widget.requestDoc['service'] ?? 'Live Help', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blue)),
          const SizedBox(height: 12),
          Text(
            "₹$price", 
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green)
          ),
          if (hours != null)
            Text(
              "$hours hr${hours > 1 ? 's' : ''} ${tip != null && tip > 0 ? '+ ₹$tip tip' : ''}",
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                const Text("Response Window", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                Text("$minutes:$seconds", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.red)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text("Accepting will make you busy.", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
        ],
      ),
      actions: [
        TextButton(onPressed: _reject, child: const Text("Pass", style: TextStyle(color: Colors.grey))),
        ElevatedButton(
          onPressed: _accept,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[800], 
            foregroundColor: Colors.white, 
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
          ),
          child: const Text("Accept Job"),
        ),
      ],
    );
  }
}
