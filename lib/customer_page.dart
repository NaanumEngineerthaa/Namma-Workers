import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'location_choice_page.dart';
import 'login_page.dart';
import 'customer_profile_setup_page.dart';
import 'job_tracking_page.dart';
import 'package:intl/intl.dart';
import 'theme.dart';
import 'widgets/loading_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CustomerPage extends StatefulWidget {
  final int initialIndex;
  const CustomerPage({super.key, this.initialIndex = 0});

  @override
  State<CustomerPage> createState() => _CustomerPageState();
}

class _CustomerPageState extends State<CustomerPage> {
  late int _currentIndex;
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  // --- DYNAMIC PRICING SYSTEM ---
  Stream<List<Map<String, dynamic>>> _getCategories() {
    return FirebaseFirestore.instance
        .collection('pricing')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          final docs = snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
          // Sort in memory to avoid index requirements
          docs.sort((a, b) => (a['order'] ?? 0).compareTo(b['order'] ?? 0));
          return docs;
        });
  }

  // --- LOGIC ---

  Future<Position?> _getUserLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return null;

    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  Future<List<Map<String, dynamic>>> _getNearestWorkers() async {
    try {
      final position = await _getUserLocation();
      if (position == null) {
        debugPrint("Location not available for nearest workers check");
        return [];
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'worker')
          .where('isOnline', isEqualTo: true)
          .get();

      List<Map<String, dynamic>> workers = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['latitude'] == null || data['longitude'] == null) continue;

        final distance = _calculateDistance(
          position.latitude, position.longitude,
          (data['latitude'] as num).toDouble(), (data['longitude'] as num).toDouble(),
        );

        workers.add({...data, 'uid': doc.id, 'distance': distance});
      }

      workers.sort((a, b) => a['distance'].compareTo(b['distance']));
      return workers.take(3).toList();
    } catch (e) {
      debugPrint("Error in _getNearestWorkers: $e");
      return [];
    }
  }

  Future<List<QueryDocumentSnapshot>> _getRecommendedWorkers() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'worker')
          .where('isOnline', isEqualTo: true)
          .get();

      final docs = snapshot.docs.toList();
      docs.sort((a, b) {
        final r1 = ((a.data() as Map<String, dynamic>)['rating'] ?? 5.0).toDouble();
        final r2 = ((b.data() as Map<String, dynamic>)['rating'] ?? 5.0).toDouble();
        return r2.compareTo(r1);
      });
      return docs.take(5).toList();
    } catch (e) {
      debugPrint("Error fetching recommended: $e");
      return [];
    }
  }

  void _showJobTypeSelection(String service) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            gradient: AppTheme.bgGlowingEffect,
            borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 50, 
                height: 5, 
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withAlpha(50), 
                  borderRadius: BorderRadius.circular(10)
                )
              ),
              const SizedBox(height: 32),
              Text(
                "Book $service", 
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppTheme.textColor)
              ),
              const SizedBox(height: 8),
              const Text(
                "When do you need a worker?", 
                style: TextStyle(color: AppTheme.subtitleColor, fontSize: 16, fontWeight: FontWeight.w500)
              ),
              const SizedBox(height: 36),
              Row(
                children: [
                  Expanded(
                    child: _buildChoiceCard(
                      title: "Hire Now",
                      subtitle: "Urgent / Live",
                      icon: Icons.bolt_rounded,
                      color: AppTheme.primaryColor,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => LocationChoicePage(service: service),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: _buildChoiceCard(
                      title: "Schedule",
                      subtitle: "Plan Ahead",
                      icon: Icons.calendar_month_rounded,
                      color: AppTheme.accentColor,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context, 
                          MaterialPageRoute(
                            builder: (context) => LocationChoicePage(
                              service: service, 
                              isScheduled: true
                            )
                          )
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChoiceCard({required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: color.withAlpha(40), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withAlpha(20),
              blurRadius: 15,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 36),
            ),
            const SizedBox(height: 18),
            Text(
              title, 
              style: TextStyle(color: AppTheme.textColor, fontWeight: FontWeight.w900, fontSize: 18)
            ),
            const SizedBox(height: 4),
            Text(
              subtitle, 
              style: TextStyle(color: AppTheme.subtitleColor, fontSize: 13, fontWeight: FontWeight.w500)
            ),
          ],
        ),
      ),
    );
  }

  void _showSchedulePicker(String service) async {
    final now = DateTime.now();
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());

    if (time == null) return;

    final startTime = DateTime(now.year, now.month, now.day, time.hour, time.minute);

    if (startTime.isBefore(DateTime.now())) {
      _showError("Cannot schedule a job in the past!");
      return;
    }

    final endTime = startTime.add(const Duration(hours: 2));
    _createScheduledJob(service, startTime, endTime);
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
        if (area.isNotEmpty && district.isNotEmpty) return "$area, $district";
        return area.isNotEmpty ? area : district.isNotEmpty ? district : "Current Location";
      }
    } catch (e) {
      debugPrint("Geocoding failed: $e");
    }
    return "Home Service";
  }

  Future<void> _createScheduledJob(String service, DateTime start, DateTime end) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final position = await _getUserLocation();
      if (position == null) {
        _showError("Could not access location.");
        return;
      }

      final String readableAddress = await _getAddress(position.latitude, position.longitude);

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      String sType = "Home Service";
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        if (userData['addressType']?.toString().toLowerCase() == 'office') {
          sType = 'Office Service';
        }
      }

      double pricePerHour = 0.0;
      try {
        final pricingDoc = await FirebaseFirestore.instance.collection('pricing').doc(service).get();
        if (pricingDoc.exists) {
          pricePerHour = (pricingDoc.data()?['pricePerHour'] ?? 0).toDouble();
        }
      } catch (_) {}

      final duration = end.difference(start).inHours;
      final hours = duration > 0 ? duration : 1;

      await FirebaseFirestore.instance.collection('jobs').add({
        'title': service,
        'type': 'scheduled',
        'status': 'pending',
        'customerId': user.uid,
        'workerId': null,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'location': readableAddress,
        'serviceType': sType,
        'hours': hours,
        'tip': 0.0,
        'pricePerHour': pricePerHour,
        'baseAmount': pricePerHour * hours,
        'amount': pricePerHour * hours,
        'startTime': Timestamp.fromDate(start),
        'endTime': Timestamp.fromDate(end),
        'createdAt': FieldValue.serverTimestamp(),
      });

      _showSuccess("Job scheduled for ${TimeOfDay.fromDateTime(start).format(context)} 📅");
    } catch (e) {
      _showError("Error: $e");
    }
  }

  Future<void> _cancelJob(String jobId) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cancel Job?"),
        content: const Text("Are you sure you want to cancel this job?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Keep Job")),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            style: TextButton.styleFrom(foregroundColor: AppTheme.unselectedColor),
            child: const Text("Yes, Cancel"),
          ),
        ],
      )
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance.collection('jobs').doc(jobId).update({
          'status': 'cancelled',
          'cancelledAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _showSuccess("Job cancelled successfully 🔴");
      } catch (e) {
        _showError("Failed to cancel job: $e");
      }
    }
  }

  Future<void> _submitRating(String jobId, String workerId, int rating) async {
    try {
      // 1. Update Job Document
      await FirebaseFirestore.instance.collection('jobs').doc(jobId).update({
        'rating': rating,
        'ratedAt': FieldValue.serverTimestamp(),
      });

      // 2. Update Worker Average Rating
      final workerRef = FirebaseFirestore.instance.collection('users').doc(workerId);
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final workerDoc = await transaction.get(workerRef);
        if (!workerDoc.exists) return;

        final data = workerDoc.data() as Map<String, dynamic>;
        double currentRating = (data['rating'] ?? 5.0).toDouble();
        int totalJobs = (data['totalJobs'] ?? 0).toInt();

        // Increment total jobs if not already accounted for in some other way, 
        // but here we usually increment it when job is completed.
        // If we only count RATED jobs for the average, we can do that too.
        // Let's assume every completed job increments totalJobs, but we use it for average.
        
        // New Average = ((Old Avg * totalJobs) + New Rating) / (totalJobs + 1)
        // Wait, if totalJobs already includes this job, we should use totalJobs as denominator.
        // Let's assume totalJobs is updated when job is COMPLETED (which it is in worker_page).
        
        double newRating = ((currentRating * (totalJobs - 1)) + rating) / totalJobs;
        if (totalJobs <= 0) newRating = rating.toDouble();

        transaction.update(workerRef, {
          'rating': double.parse(newRating.toStringAsFixed(1)),
        });
      });

      _showSuccess("Thank you for your feedback! ⭐");
    } catch (e) {
      _showError("Failed to submit rating: $e");
    }
  }

  Widget _buildRatingWidget(String jobId, String workerId, dynamic currentRating) {
    int ratedValue = 0;
    if (currentRating != null && currentRating is num) {
      ratedValue = currentRating.toInt();
    }

    if (ratedValue > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const Text("Your Rating: ", style: TextStyle(fontSize: 13, color: AppTheme.subtitleColor, fontWeight: FontWeight.w500)),
            Row(
              children: List.generate(5, (index) => Icon(
                index < ratedValue ? Icons.star_rounded : Icons.star_outline_rounded,
                color: AppTheme.primaryColor,
                size: 20,
              )),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withAlpha(10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primaryColor.withAlpha(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("How was the service?", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryColor)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (index) => GestureDetector(
              onTap: () => _submitRating(jobId, workerId, index + 1),
              child: const Icon(Icons.star_outline_rounded, color: AppTheme.primaryColor, size: 36),
            )),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppTheme.unselectedColor));
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppTheme.primaryColor));
  }

  @override
  Widget build(BuildContext context) {
    if (FirebaseAuth.instance.currentUser == null) {
      return const LoginPage();
    }
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(_getPageTitle(), style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textColor)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            onPressed: () {}, 
            icon: const Icon(Icons.notifications_none_rounded, size: 28, color: AppTheme.textColor)
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.bgGlowingEffect),
        child: _buildCurrentPage(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: AppTheme.primaryColor,
        unselectedItemColor: AppTheme.unselectedColor,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.category_rounded), label: "Services"),
          BottomNavigationBarItem(icon: Icon(Icons.work_rounded), label: "My Jobs"),
          BottomNavigationBarItem(icon: Icon(Icons.history_rounded), label: "History"),
          BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: "Profile"),
        ],
      ),
    );
  }

  String _getPageTitle() {
    switch (_currentIndex) {
      case 0: return "Namma Workers";
      case 1: return "All Services";
      case 2: return "My Jobs";
      case 3: return "Work History";
      case 4: return "My Profile";
      default: return "";
    }
  }

  Widget _buildCurrentPage() {
    switch (_currentIndex) {
      case 0: return _buildDashboard();
      case 1: return _buildServicesPage();
      case 2: return _buildMyJobsPage();
      case 3: return _buildHistoryPage();
      case 4: return _buildProfilePage();
      default: return _buildDashboard();
    }
  }

  Widget _buildMyJobsPage() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text("Please login"));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('jobs')
          .where('customerId', isEqualTo: user.uid)
          .where('status', whereIn: ['picked', 'active', 'pending', 'searching', 'scheduled'])
          .snapshots()
          .asyncMap((snap) async {
            await Future.delayed(const Duration(milliseconds: 1500));
            return snap;
          }),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text("Error: ${snapshot.error}", style: const TextStyle(color: AppTheme.unselectedColor)),
          ));
        }
        if (!snapshot.hasData) return const PremiumLoadingScreen();

        final now = DateTime.now();
        List<DocumentSnapshot> validDocs = [];

        for (var doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final isExpired = data['isExpired'] ?? false;
          final status = data['status'];
          
          if (isExpired) continue;

          final expiresAtField = (data['expiresAt'] as Timestamp?)?.toDate();
          final type = data['type'];
          
          DateTime effectiveExpiresAt;
          if (expiresAtField != null) {
             effectiveExpiresAt = expiresAtField;
          } else {
             final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
             effectiveExpiresAt = type == 'scheduled' 
                 ? ((data['startTime'] as Timestamp?)?.toDate() ?? createdAt).add(Duration(hours: data['hours'] ?? 1))
                 : createdAt.add(const Duration(minutes: 30)); 
          }
          
          if (now.isAfter(effectiveExpiresAt)) {
             // If live job not picked/active, or scheduled job passed end time, mark as expired in DB
              if (status != 'picked' && status != 'active' && status != 'completed' && status != 'cancelled' && status != 'rejected') {
                doc.reference.update({
                  'isExpired': true,
                  'status': 'closed', 
                  'updatedAt': FieldValue.serverTimestamp()
                });
                continue;
              }
          }
          
          validDocs.add(doc);
        }

        final sortedDocs = validDocs.toList();
        sortedDocs.sort((a, b) {
          final t1 = ((a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
          final t2 = ((b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
          return t2.compareTo(t1);
        });

        if (sortedDocs.isEmpty) {
          return const Center(child: Text("No active jobs", style: TextStyle(fontSize: 16, color: Colors.grey)));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: sortedDocs.length,
          itemBuilder: (context, index) {
            final doc = sortedDocs[index];
            final data = doc.data() as Map<String, dynamic>;
            final status = data['status'];
            final isPicked = status == 'picked';
            final isLive = data['type'] == 'live';

            return Container(
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: AppTheme.glowingShadow,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    if (isPicked) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => JobTrackingPage(jobId: doc.id),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Waiting for a worker to accept this job.")),
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(28),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "${data['title'] ?? data['profession'] ?? 'Service'}",
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppTheme.textColor),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withAlpha(20),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.primaryColor.withAlpha(40)),
                              ),
                              child: Text(
                                (data['type'] ?? 'live').toString().toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 10, 
                                  fontWeight: FontWeight.w900, 
                                  color: AppTheme.primaryColor,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "₹${(data['amount'] ?? 0).toString()}",
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppTheme.primaryColor),
                        ),
                        const SizedBox(height: 20),
                        _buildJobDetailRow(Icons.location_on_rounded, data['location'] ?? 'Location not available'),
                        const SizedBox(height: 12),
                        _buildJobDetailRow(
                          Icons.access_time_filled_rounded, 
                          isLive 
                            ? "Requested: ${DateFormat('hh:mm a, dd MMM').format((data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now())}"
                            : "Scheduled: ${DateFormat('hh:mm a').format((data['startTime'] as Timestamp?)?.toDate() ?? DateTime.now())} - ${DateFormat('hh:mm a').format((data['endTime'] as Timestamp?)?.toDate() ?? DateTime.now())}"
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withAlpha(20),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(isPicked ? Icons.check_circle_rounded : Icons.hourglass_empty_rounded, size: 18, color: AppTheme.primaryColor),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isPicked ? "Worker Assigned" : "Finding Worker...",
                              style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w800, fontSize: 13),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Divider(height: 1, color: Color(0xFFF5F5F5)),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            GestureDetector(
                              onTap: () => _cancelJob(doc.id),
                              child: Row(
                                children: [
                                  const Icon(Icons.cancel_outlined, size: 20, color: AppTheme.unselectedColor),
                                  const SizedBox(width: 8),
                                  const Text(
                                    "Cancel order",
                                    style: TextStyle(color: AppTheme.unselectedColor, fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                ],
                              ),
                            ),
                            if (isPicked)
                              Container(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [AppTheme.primaryColor, Color(0xFF8A1BC6)]),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [BoxShadow(color: AppTheme.primaryColor.withAlpha(60), blurRadius: 10, offset: const Offset(0, 4))],
                                ),
                                child: ElevatedButton.icon(
                                  onPressed: () => Navigator.push(
                                    context, 
                                    MaterialPageRoute(builder: (_) => JobTrackingPage(jobId: doc.id))
                                  ),
                                  icon: const Icon(Icons.map_rounded, size: 18, color: Colors.white),
                                  label: const Text("Track", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                     backgroundColor: Colors.transparent,
                                     shadowColor: Colors.transparent,
                                     padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildJobDetailRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primaryColor.withAlpha(200)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: AppTheme.textColor, fontSize: 14, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryPage() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text("Please login"));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('jobs')
          .where('customerId', isEqualTo: user.uid)
          .where('status', whereIn: ['completed', 'cancelled', 'closed', 'timeout', 'rejected'])
          .snapshots()
          .asyncMap((snap) async {
            await Future.delayed(const Duration(milliseconds: 1500));
            return snap;
          }),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text("Error: ${snapshot.error}"));
        }
        if (!snapshot.hasData) return const PremiumLoadingScreen();

        final sortedDocs = snapshot.data!.docs.toList();
        // Sort in memory (Newest first)
        sortedDocs.sort((a, b) {
          final t1 = ((a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
          final t2 = ((b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
          return t2.compareTo(t1);
        });

        if (sortedDocs.isEmpty) {
          return const Center(child: Text("No history available", style: TextStyle(fontSize: 16, color: Colors.grey)));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: sortedDocs.length,
          itemBuilder: (context, index) {
            final data = sortedDocs[index].data() as Map<String, dynamic>;
            final status = data['status'] ?? 'unknown';
            final workerId = data['workerId'];

            Color statusColor;
            String statusLabel;
            
            switch(status.toLowerCase()) {
              case 'completed': 
                statusColor = AppTheme.primaryColor; 
                statusLabel = "COMPLETED";
                break;
              case 'cancelled': 
                statusColor = AppTheme.subtitleColor; 
                statusLabel = "CANCELLED";
                break;
              case 'closed': 
                statusColor = AppTheme.unselectedColor; 
                statusLabel = "CLOSED";
                break;
              default: 
                statusColor = AppTheme.primaryColor;
                statusLabel = status.toUpperCase();
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: AppTheme.glowingShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          "${data['title'] ?? data['profession'] ?? 'Service'}",
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.textColor),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withAlpha(20),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: statusColor.withAlpha(50)),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: statusColor, letterSpacing: 0.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "₹${(data['amount'] ?? 0).toString()}",
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.textColor),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(height: 1, color: Color(0xFFF5F5F5)),
                  ),
                  
                  _buildJobDetailRow(Icons.calendar_month_rounded, DateFormat('dd MMM yyyy, hh:mm a').format((data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now())),
                  const SizedBox(height: 8),
                  _buildJobDetailRow(Icons.location_on_rounded, data['location'] ?? 'Location N/A'),
                  
                  // Worker Detail
                  if (workerId != null) ...[
                    const SizedBox(height: 16),
                    FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance.collection('users').doc(workerId).get(),
                      builder: (context, workerSnapshot) {
                        if (!workerSnapshot.hasData) return const SizedBox.shrink();
                        final workerData = workerSnapshot.data!.data() as Map<String, dynamic>?;
                        if (workerData == null) return const SizedBox.shrink();

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withAlpha(10),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.primaryColor.withAlpha(20)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppTheme.primaryColor.withAlpha(50), width: 1.5),
                                ),
                                child: CircleAvatar(
                                  radius: 20,
                                  backgroundColor: AppTheme.primaryColor.withAlpha(20),
                                  backgroundImage: workerData['photoUrl'] != null ? NetworkImage(workerData['photoUrl']) : null,
                                  child: workerData['photoUrl'] == null ? const Icon(Icons.person, size: 20, color: AppTheme.primaryColor) : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(workerData['name'] ?? 'Worker', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textColor)),
                                    Text(workerData['profession'] ?? 'Service Provider', style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                  
                  // ⭐ Rating Section for Completed Jobs
                  if (status.toLowerCase() == 'completed' && workerId != null) ...[
                    const SizedBox(height: 16),
                    _buildRatingWidget(sortedDocs[index].id, workerId, data['rating']),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildProfilePage() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text("Please login"));

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .asyncMap((snap) async {
            await Future.delayed(const Duration(milliseconds: 1500));
            return snap;
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
                      Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerProfileSetupPage(initialData: data, isEditing: true)));
                    },
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text("Edit Profile", style: TextStyle(fontWeight: FontWeight.bold)),
                    style: TextButton.styleFrom(foregroundColor: AppTheme.primaryColor),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.primaryColor.withAlpha(50), width: 2),
                      ),
                      child: CircleAvatar(
                        radius: 65,
                        backgroundColor: AppTheme.primaryColor.withAlpha(10),
                        backgroundImage: data['photoUrl'] != null 
                          ? NetworkImage(data['photoUrl']) 
                          : null,
                        child: data['photoUrl'] == null 
                          ? const Icon(Icons.person, size: 65, color: AppTheme.primaryColor) 
                          : null,
                      ),
                    ),
                    Positioned(
                      bottom: 5,
                      right: 5,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.verified_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                data['name'] ?? 'User Name',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppTheme.textColor),
              ),
              const SizedBox(height: 4),
              Text(
                data['email'] ?? 'No email associated',
                style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 15, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 36),
              _buildProfileTile(Icons.phone_iphone_rounded, "Phone", data['phone'] ?? 'N/A'),
              _buildProfileTile(Icons.location_on_rounded, "Primary Address", data['address'] ?? 'N/A'),
              _buildProfileTile(Icons.home_work_rounded, "Address Type", (data['addressType'] as String?)?.toUpperCase() ?? 'N/A'),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text("Logout from Namma Workers", style: TextStyle(fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.unselectedColor,
                    side: BorderSide(color: AppTheme.unselectedColor.withAlpha(50)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProfileTile(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppTheme.glowingShadow,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withAlpha(15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: AppTheme.primaryColor, size: 28),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.textColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    final user = FirebaseAuth.instance.currentUser;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          //const SizedBox(height: 10),
          //Text("Hi ${user?.displayName?.split(' ').first ?? 'Friend'}, 👋", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text("What service do you need today?", style: TextStyle(color: Colors.grey[600], fontSize: 16)),
          const SizedBox(height: 24),
          _buildQuickCategoryGrid(),
          const SizedBox(height: 30),
          _buildSectionHeader("Recommended Workers"),
          const SizedBox(height: 16),
          FutureBuilder<List<QueryDocumentSnapshot>>(
            future: Future.wait([
              _getRecommendedWorkers(),
              Future.delayed(const Duration(milliseconds: 1500)),
            ]).then((values) => values[0] as List<QueryDocumentSnapshot>),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const PremiumLoadingScreen(isFullPage: false);
              if (snapshot.hasError) return _buildEmptyState("Error loading workers: ${snapshot.error}");
              if (!snapshot.hasData || snapshot.data!.isEmpty) return _buildEmptyState("No top-rated workers available online");
              return Column(
                children: snapshot.data!.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return _buildWorkerCard(
                    name: data['name'] ?? 'Worker',
                    profession: data['profession'] ?? 'Pro',
                    rating: (data['rating'] ?? 5.0).toString(),
                    info: "${data['totalJobs'] ?? 0} jobs done",
                    photoUrl: data['photoUrl'],
                    onTap: () => _showJobTypeSelection(data['profession'] ?? "Service"),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 30),
          _buildSectionHeader("Nearby Workers"),
          const SizedBox(height: 16),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: Future.wait([
              _getNearestWorkers(),
              Future.delayed(const Duration(milliseconds: 1500)),
            ]).then((values) => values[0] as List<Map<String, dynamic>>),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const PremiumLoadingScreen(isFullPage: false);
              if (snapshot.hasError) return _buildEmptyState("Error: ${snapshot.error}");
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                 return _buildEmptyState("No nearby workers found.\n(Make sure GPS is on and workers are Online)");
              }
              return Column(
                children: snapshot.data!.map((worker) {
                  final dist = (worker['distance'] / 1000).toStringAsFixed(1);
                  return _buildWorkerCard(
                    name: worker['name'] ?? 'Worker',
                    profession: worker['profession'] ?? 'Pro',
                    rating: (worker['rating'] ?? 5.0).toString(),
                    info: "${dist}km away",
                    photoUrl: worker['photoUrl'],
                    onTap: () => _showJobTypeSelection(worker['profession'] ?? "Service"),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildServicesPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white, 
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.primaryColor.withAlpha(20)),
              boxShadow: [BoxShadow(color: AppTheme.primaryColor.withAlpha(5), blurRadius: 10, offset: const Offset(0, 4))]
            ),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: const InputDecoration(
                hintText: "Search for a service...", 
                border: InputBorder.none, 
                prefixIcon: Icon(Icons.search_rounded, color: AppTheme.unselectedColor),
                hintStyle: TextStyle(color: AppTheme.subtitleColor),
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text("Popular Categories", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textColor)),
          const SizedBox(height: 16),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _getCategories(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
              }
              if (snapshot.hasError) {
                return _buildEmptyState("Error: ${snapshot.error}");
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return _buildEmptyState("No services available right now.");
              }

              final filteredProfessions = snapshot.data!
                  .where((p) => p['name'].toString().toLowerCase().contains(_searchQuery.toLowerCase()))
                  .toList();

              if (filteredProfessions.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(
                    child: Column(
                      children: [
                         Icon(Icons.search_off_rounded, size: 64, color: AppTheme.unselectedColor.withAlpha(100)),
                         const SizedBox(height: 16),
                         Text("No services found for '$_searchQuery'", style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 16)),
                      ],
                    ),
                  ),
                );
              }

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, 
                  crossAxisSpacing: 12, 
                  mainAxisSpacing: 20, 
                  childAspectRatio: 0.8
                ),
                itemCount: filteredProfessions.length,
                itemBuilder: (context, index) {
                  final category = filteredProfessions[index];
                  final name = category['name'] ?? 'Service';
                  final iconUrl = category['iconUrl'] as String?;
                  const color = AppTheme.primaryColor;

                  return GestureDetector(
                    onTap: () => _showJobTypeSelection(name),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: color.withAlpha(15), 
                            shape: BoxShape.circle, 
                            border: Border.all(color: color.withAlpha(30), width: 1), 
                            boxShadow: [BoxShadow(color: color.withAlpha(5), blurRadius: 8, offset: const Offset(0, 4))]
                          ),
                          child: (iconUrl != null && iconUrl.isNotEmpty)
                              ? CachedNetworkImage(
                                  imageUrl: iconUrl,
                                  width: 32,
                                  height: 32,
                                  color: color,
                                  colorBlendMode: BlendMode.srcIn,
                                  placeholder: (context, url) => const Icon(Icons.miscellaneous_services, color: color, size: 32),
                                  errorWidget: (context, url, error) => const Icon(Icons.miscellaneous_services, color: color, size: 32),
                                )
                              : const Icon(Icons.miscellaneous_services, color: color, size: 32),
                        ),
                        const SizedBox(height: 8),
                        Text(name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textColor)),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 32),
          // Urgent Help Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF8A1BC6), AppTheme.primaryColor], 
                begin: Alignment.topLeft, 
                end: Alignment.bottomRight
              ), 
              borderRadius: BorderRadius.circular(28),
              boxShadow: [BoxShadow(color: AppTheme.primaryColor.withAlpha(50), blurRadius: 20, offset: const Offset(0, 10))]
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text("Need urgent help?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                const SizedBox(height: 6),
                Text("Book a live worker in 2 minutes!", style: TextStyle(color: Colors.white.withAlpha(200))),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {}, 
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white, 
                    foregroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ), 
                  child: const Text("Click Hire Now")
                )
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildQuickCategoryGrid() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _getCategories(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
        
        final categories = snapshot.data!.take(4).toList();
        
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, 
            crossAxisSpacing: 16, 
            mainAxisSpacing: 16, 
            childAspectRatio: 1.6
          ),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final cat = categories[index];
            final name = cat['name'] ?? 'Service';
            final iconUrl = cat['iconUrl'] as String?;
            const color = AppTheme.primaryColor;
            
            return GestureDetector(
              onTap: () => _showJobTypeSelection(name),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white, 
                  borderRadius: BorderRadius.circular(28), 
                  border: Border.all(color: color.withAlpha(20)),
                  boxShadow: [
                    BoxShadow(color: color.withAlpha(8), blurRadius: 15, offset: const Offset(0, 8))
                  ]
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: color.withAlpha(20), shape: BoxShape.circle),
                      child: (iconUrl != null && iconUrl.isNotEmpty)
                          ? CachedNetworkImage(
                              imageUrl: iconUrl,
                              width: 20,
                              height: 20,
                              color: color,
                              colorBlendMode: BlendMode.srcIn,
                              placeholder: (context, url) => const Icon(Icons.miscellaneous_services, color: color, size: 20),
                              errorWidget: (context, url, error) => const Icon(Icons.miscellaneous_services, color: color, size: 20),
                            )
                          : const Icon(Icons.miscellaneous_services, color: color, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppTheme.textColor)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.textColor)),
        TextButton(onPressed: () {}, child: Text("See All", style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold))),
      ],
    );
  }

  Widget _buildEmptyState(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withAlpha(10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.primaryColor.withAlpha(10), style: BorderStyle.solid),
      ),
      child: Center(
        child: Text(msg, textAlign: TextAlign.center, style: TextStyle(color: AppTheme.subtitleColor, fontWeight: FontWeight.w500, height: 1.5)),
      ),
    );
  }

  Widget _buildWorkerCard({required String name, required String profession, required String rating, required String info, String? photoUrl, String? addressType, VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(30), 
        boxShadow: AppTheme.glowingShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.primaryColor.withAlpha(50), width: 1.5),
                  ),
                  child: CircleAvatar(
                    radius: 35, 
                    backgroundColor: AppTheme.primaryColor.withAlpha(20), 
                    backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null, 
                    child: photoUrl == null ? const Icon(Icons.person, color: AppTheme.primaryColor, size: 30) : null
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.textColor)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(profession, style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 14, fontWeight: FontWeight.w500)),
                          if (addressType != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(color: AppTheme.primaryColor.withAlpha(20), borderRadius: BorderRadius.circular(8)),
                              child: Text(addressType.toUpperCase(), style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: AppTheme.primaryColor)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, color: AppTheme.primaryColor, size: 20),
                          Text(" $rating ", style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textColor)),
                          Text("• $info", style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.unselectedColor, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
