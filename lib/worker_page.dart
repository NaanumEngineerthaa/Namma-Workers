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
import 'login_page.dart';
import 'login_page.dart';

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

  @override
  void initState() {
    super.initState();
    _checkInitialLocation();
    _subscribeToServiceStatus();
    _listenForJobRequests();
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

  void _showJobRequestDialog(DocumentSnapshot requestDoc) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => IncomingJobDialog(requestDoc: requestDoc),
    );
  }

  @override
  void dispose() {
    _stopTracking();
    _serviceStatusStreamSubscription?.cancel();
    _jobRequestSubscription?.cancel();
    super.dispose();
  }

  Stream<double> _monthlyEarnings(String workerId) {
    final start = DateTime(DateTime.now().year, DateTime.now().month, 1);
    return FirebaseFirestore.instance
        .collection('jobs')
        .where('workerId', isEqualTo: workerId)
        .where('status', isEqualTo: 'completed')
        // Removing composite filter to avoid needing Firestore index for now
        .snapshots()
        .map((snapshot) {
          double total = 0;
          for (var doc in snapshot.docs) {
            final completedAt = (doc['completedAt'] as Timestamp?)?.toDate();
            // Filter by date in memory
            if (completedAt != null && completedAt.isAfter(start)) {
              total += (doc['price'] ?? 0).toDouble();
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
        .where('status', isEqualTo: 'accepted')
        .where('type', isEqualTo: 'live')
        .get();
    return jobs.docs.isNotEmpty;
  }

  Future<bool> _hasTimeConflict(String uid, DateTime start, DateTime end) async {
    final jobs = await FirebaseFirestore.instance
        .collection('jobs')
        .where('workerId', isEqualTo: uid)
        .where('status', isEqualTo: 'accepted')
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
      'status': 'accepted',
      'acceptedAt': FieldValue.serverTimestamp(),
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

    // 🏆 Set worker free again (AS PER Logic Rule)
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'isBusy': false,
    });

    await FirebaseFirestore.instance.collection('jobs').doc(jobId).update({
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Job marked as completed! 🏁")),
      );
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

    setState(() {
      _isOnline = false;
    });
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
            color: Colors.orange,
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
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(_getPageTitle(), style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none)),
        ],
      ),
      body: _buildCurrentPage(),
      floatingActionButton: (_currentIndex == 0 || _currentIndex == 1)
          ? FloatingActionButton.extended(
              onPressed: _toggleOnlineStatus,
              label: Text(_isOnline ? "Go Offline" : "Go Online"),
              icon: Icon(_isOnline ? Icons.power_settings_new : Icons.play_arrow),
              backgroundColor: _isOnline ? Colors.green : Colors.redAccent,
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
        selectedItemColor: Colors.orange[800],
        unselectedItemColor: Colors.grey,
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
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
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
                    style: TextButton.styleFrom(foregroundColor: Colors.orange[800]),
                  ),
                ],
              ),
              Center(
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.orange.withAlpha(50), width: 4),
                      ),
                      child: CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.orange[50],
                        backgroundImage: data['photoUrl'] != null 
                          ? NetworkImage(data['photoUrl']) 
                          : null,
                        child: data['photoUrl'] == null 
                          ? const Icon(Icons.person, size: 60, color: Colors.orange) 
                          : null,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                        child: const Icon(Icons.verified, color: Colors.white, size: 24),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                data['name'] ?? 'Worker Name',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              Text(
                data['email'] ?? 'Email Not Found',
                style: TextStyle(color: Colors.grey[600], fontSize: 16),
              ),
              const SizedBox(height: 32),
              _buildProfileTile(Icons.work_rounded, "Profession", data['profession'] ?? 'N/A'),
              _buildProfileTile(Icons.history_edu_rounded, "Experience", "${data['experience'] ?? 0} Years"),
              _buildProfileTile(Icons.star_rounded, "Rating", (data['rating'] ?? 5.0).toString()),
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
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
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
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.orange.withAlpha(20), shape: BoxShape.circle),
            child: Icon(icon, color: Colors.orange[800], size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
          .where('status', isEqualTo: 'accepted')
          .where('type', isEqualTo: 'live')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final docs = snapshot.data!.docs;
        
        // No Active Live Jobs -> Standard Passive Map
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
                      color: Colors.blue.withAlpha(200),
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
                          const Icon(Icons.directions_car, color: Colors.green, size: 40),
                        ],
                      ),
                    ),
                    // Customer Marker
                    Marker(
                      point: LatLng(customerLat, customerLng),
                      width: 80,
                      height: 80,
                      child: const Icon(Icons.person_pin_circle, color: Colors.blue, size: 45),
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
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(16)),
                          child: Text("${dist.toStringAsFixed(1)} km", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
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
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[600], foregroundColor: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FloatingActionButton.small(
                          onPressed: () {},
                          backgroundColor: Colors.green[50],
                          elevation: 0,
                          child: const Icon(Icons.call, color: Colors.green),
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
                          foregroundColor: Colors.green[700],
                          side: BorderSide(color: Colors.green[700]!, width: 2),
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
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, profileSnapshot) {
        final profileData = profileSnapshot.data?.data() as Map<String, dynamic>? ?? {};
        final int target = profileData['monthlyTarget'] ?? 15000;
        final String profession = profileData['profession'] ?? '';

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('jobs')
              .where('workerId', isEqualTo: user.uid)
              .where('status', isEqualTo: 'accepted')
              .snapshots(),
          builder: (context, acceptedSnapshot) {
            final List<DocumentSnapshot> activeJobs = acceptedSnapshot.data?.docs ?? [];
            final bool alreadyHasLiveJob = activeJobs.any((doc) => doc['type'] == 'live');

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
                          const Text("Service Status", style: TextStyle(color: Colors.grey, fontSize: 14)),
                          Text(
                            _isOnline ? "ONLINE" : "OFFLINE",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _isOnline ? Colors.green[700] : Colors.red[700],
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

                  // 🔴 1. LIVE JOBS SECTION (PENDING)
                  _buildSectionHeader("🔴 Live Requests", true),
                  const SizedBox(height: 12),
                  _buildLiveJobsStream(user.uid, alreadyHasLiveJob, profession, limit: 2),

                  const SizedBox(height: 30),

                  // 🟡 2. SCHEDULED JOBS SECTION (PENDING)
                  _buildSectionHeader("🟡 Scheduled Bookings", true),
                  const SizedBox(height: 12),
                  _buildScheduledJobsStream(user.uid, activeJobs, profession, limit: 2),

                  const SizedBox(height: 30),

                  // 📅 3. MY TIMELINE (ACCEPTED JOBS)
                  _buildSectionHeader("📅 My Timeline (Accepted)", false),
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
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        if (showBadge)
          const Text("Pending", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
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
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return _buildEmptyState("No live requests currently");

        // 🔥 Filter by profession in memory to avoid new index requirements
        final filteredDocs = docs.where((doc) {
          final title = (doc['title'] ?? '').toString().toLowerCase();
          final prof = profession.toLowerCase();
          return title.contains(prof) || prof.contains(title);
        }).toList();

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
                isDisabled: alreadyHasLiveJob,
                disabledReason: "Already has active live job",
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
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return _buildEmptyState("No scheduled jobs found");

        final filteredDocs = docs.where((pendingDoc) {
          final pData = pendingDoc.data() as Map<String, dynamic>;
          
          // 1. Filter by profession
          final title = (pData['title'] ?? '').toString().toLowerCase();
          final prof = profession.toLowerCase();
          final isMatch = title.contains(prof) || prof.contains(title);
          if (!isMatch) return false;

          // 2. Conflict check
          final pStart = (pData['startTime'] as Timestamp?)?.toDate();
          final pEnd = (pData['endTime'] as Timestamp?)?.toDate();

          if (pStart == null || pEnd == null) return false;

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
              itemBuilder: (context, index) => _buildJobCard(displayDocs[index]),
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
          .where('status', isEqualTo: 'accepted')
          // Removed orderBy to avoid requiring composite index
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _buildEmptyState("Error loading jobs");
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
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
            color: Colors.orange[50],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined, size: 16, color: Colors.orange[800]),
              const SizedBox(width: 4),
              Text(
                "₹${NumberFormat('#,###').format(earnings)}", 
                style: TextStyle(color: Colors.orange[800], fontWeight: FontWeight.bold)
              ),
            ],
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

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.orange[800]!, Colors.orange[400]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.orange.withAlpha(20),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
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
        );
      }
    );
  }

  Widget _buildProgressBar(double progress, int target) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Goal: ₹$target",
          style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
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

  Widget _buildJobCard(DocumentSnapshot doc, {bool isAccepted = false, bool isDisabled = false, String? disabledReason}) {
    final data = doc.data() as Map<String, dynamic>;
    final title = data['title'] ?? 'Job';
    final address = data['location'] ?? 'Address N/A';
    final price = data['price']?.toString() ?? 'TBD';
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
                        color: (type == 'live' ? Colors.red : Colors.orange).withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        type.toString().toUpperCase(),
                        style: TextStyle(
                          color: type == 'live' ? Colors.red[700] : Colors.orange[800],
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(distanceStr, style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.w500)),
                  ],
                ),
                Text("₹$price", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
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
            Text(title, style: TextStyle(fontSize: 16, color: Colors.blue[800], fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),

            // Row 4: Service Type
            Row(
              children: [
                const Icon(Icons.home_work_outlined, color: Colors.grey, size: 16),
                const SizedBox(width: 4),
                Text(data['serviceType'] ?? "Home Service", style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              ],
            ),
            const SizedBox(height: 4),

            // Row 5: Location
            Row(
              children: [
                const Icon(Icons.location_on_outlined, color: Colors.grey, size: 16),
                const SizedBox(width: 4),
                Expanded(child: Text(address, style: TextStyle(color: Colors.grey[600], fontSize: 13))),
              ],
            ),
            const SizedBox(height: 4),

            // Row 5: Time
            Row(
              children: [
                const Icon(Icons.access_time, color: Colors.grey, size: 16),
                const SizedBox(width: 4),
                Text(timeDisplay, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              ],
            ),

            if (isDisabled && disabledReason != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  "⚠ $disabledReason",
                  style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
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
                        backgroundColor: type == 'live' ? Colors.red[600] : Colors.orange[800],
                        foregroundColor: Colors.white,
                      ),
                      child: const Text("Accept"),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _completeJob(doc.id),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text("Mark as Completed"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsPage() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text("Not logged in"));

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(child: Text("Profile not found"));
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final name = data['name'] ?? 'Worker';
        final profession = data['profession'] ?? 'Service Provider';
        final experience = data['experience'] ?? '0';
        final photoUrl = data['photoUrl'];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              CircleAvatar(
                radius: 60,
                backgroundColor: Colors.orange[50],
                backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                child: photoUrl == null ? Icon(Icons.person, size: 60, color: Colors.orange[200]) : null,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20, color: Colors.grey),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => WorkerProfileSetupPage(
                            initialData: data,
                            isEditing: true,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  profession,
                  style: TextStyle(color: Colors.orange[800], fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 24),
              _buildSettingItem(Icons.history, "Experience", "$experience Years"),
              _buildSettingItem(Icons.payments_outlined, "Hourly Charge", "₹${data['hourlyRate'] ?? 0} / hr"),
              _buildSettingItem(Icons.star_outline, "Rating", "${data['rating'] ?? 5.0}"),
              _buildSettingItem(Icons.work_outline, "Total Jobs", "${data['totalJobs'] ?? 0}"),
              _buildSettingItem(Icons.email_outlined, "Email", user.email ?? ""),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  icon: const Icon(Icons.logout),
                  label: const Text("Logout"),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSettingItem(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey[600], size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 16)),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildSchedulePage() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text("Please Login"));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Active Schedule", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text("These are your currently accepted and pending jobs.", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          _buildAcceptedJobsTimeline(user.uid),
        ],
      ),
    );
  }
}

class IncomingJobDialog extends StatefulWidget {
  final DocumentSnapshot requestDoc;

  const IncomingJobDialog({super.key, required this.requestDoc});

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
    final req = widget.requestDoc;
    final jobId = req['jobId'];
    final workerId = req['workerId'];

    try {
      // 1. Update job as accepted
      await FirebaseFirestore.instance.collection('jobs').doc(jobId).update({
        'status': 'accepted',
        'workerId': workerId,
        'acceptedAt': FieldValue.serverTimestamp(),
      });

      // 2. Mark worker as busy
      await FirebaseFirestore.instance.collection('users').doc(workerId).update({
        'isBusy': true,
      });

      // 3. Update request status
      await req.reference.update({'status': 'accepted'});

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
