import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'location_choice_page.dart';
import 'login_page.dart';
import 'customer_profile_setup_page.dart';

class CustomerPage extends StatefulWidget {
  const CustomerPage({super.key});

  @override
  State<CustomerPage> createState() => _CustomerPageState();
}

class _CustomerPageState extends State<CustomerPage> {
  int _currentIndex = 0;

  final List<String> _professions = [
    'Painter', 'Plumber', 'Electrician', 'Carpenter', 'Mason', 'Mechanic',
    'Gardener', 'Cleaner', 'Driver', 'Tailor', 'Other',
  ];

  final Map<String, IconData> _professionIcons = {
    'Painter': Icons.format_paint_rounded,
    'Plumber': Icons.plumbing_rounded,
    'Electrician': Icons.electric_bolt_rounded,
    'Carpenter': Icons.handyman_rounded,
    'Mason': Icons.foundation_rounded,
    'Mechanic': Icons.build_rounded,
    'Gardener': Icons.park_rounded,
    'Cleaner': Icons.cleaning_services_rounded,
    'Driver': Icons.directions_car_rounded,
    'Tailor': Icons.content_cut_rounded,
    'Other': Icons.more_horiz_rounded,
  };

  final Map<String, Color> _professionColors = {
    'Painter': Colors.amber,
    'Plumber': Colors.blue,
    'Electrician': Colors.yellow.shade700,
    'Carpenter': Colors.brown,
    'Mason': Colors.blueGrey,
    'Mechanic': Colors.orange,
    'Gardener': Colors.green,
    'Cleaner': Colors.cyan,
    'Driver': Colors.indigo,
    'Tailor': Colors.pink,
    'Other': Colors.grey,
  };

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
    final position = await _getUserLocation();
    if (position == null) return [];

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
  }

  Future<List<QueryDocumentSnapshot>> _getRecommendedWorkers() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'worker')
        .where('isOnline', isEqualTo: true)
        .orderBy('rating', descending: true)
        .limit(5)
        .get();

    return snapshot.docs;
  }

  void _showJobTypeSelection(String service) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Text("Book $service", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text("When do you need a worker?", style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _buildChoiceCard(
                      title: "Hire Now",
                      subtitle: "Urgent/Live",
                      icon: Icons.bolt,
                      color: Colors.redAccent,
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
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildChoiceCard(
                      title: "Schedule",
                      subtitle: "Plan ahead",
                      icon: Icons.calendar_today,
                      color: Colors.orange,
                      onTap: () {
                        Navigator.pop(context);
                        _showSchedulePicker(service);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
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
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withAlpha(50), width: 1.5),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 40),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
            Text(subtitle, style: TextStyle(color: color.withAlpha(150), fontSize: 12)),
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
        'price': 500,
        'startTime': Timestamp.fromDate(start),
        'endTime': Timestamp.fromDate(end),
        'createdAt': FieldValue.serverTimestamp(),
      });

      _showSuccess("Job scheduled for ${TimeOfDay.fromDateTime(start).format(context)} 📅");
    } catch (e) {
      _showError("Error: $e");
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }

  @override
  Widget build(BuildContext context) {
    if (FirebaseAuth.instance.currentUser == null) {
      return const LoginPage();
    }
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_getPageTitle(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none, color: Colors.black, size: 28)),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildCurrentPage(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: Colors.blue[800],
        unselectedItemColor: Colors.grey,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.category_rounded), label: "Services"),
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
      case 2: return "Order History";
      case 3: return "My Profile";
      default: return "";
    }
  }

  Widget _buildCurrentPage() {
    switch (_currentIndex) {
      case 0: return _buildDashboard();
      case 1: return _buildServicesPage();
      case 2: return const Center(child: Text("History Page Content"));
      case 3: return _buildProfilePage();
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
                      Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerProfileSetupPage(initialData: data, isEditing: true)));
                    },
                    icon: const Icon(Icons.edit_rounded, size: 20),
                    label: const Text("Edit Profile"),
                    style: TextButton.styleFrom(foregroundColor: Colors.blue[800]),
                  ),
                ],
              ),
              Center(
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.blue.withAlpha(50), width: 4),
                      ),
                      child: CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.blue[50],
                        backgroundImage: data['photoUrl'] != null 
                          ? NetworkImage(data['photoUrl']) 
                          : null,
                        child: data['photoUrl'] == null 
                          ? const Icon(Icons.person, size: 60, color: Colors.blue) 
                          : null,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                        child: const Icon(Icons.verified, color: Colors.white, size: 24),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                data['name'] ?? 'User Name',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              Text(
                data['email'] ?? 'Email Not Found',
                style: TextStyle(color: Colors.grey[600], fontSize: 16),
              ),
              const SizedBox(height: 32),
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
                  label: const Text("Logout from Application"),
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
            decoration: BoxDecoration(color: Colors.blue.withAlpha(20), shape: BoxShape.circle),
            child: Icon(icon, color: Colors.blue[800], size: 24),
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

  Widget _buildDashboard() {
    final user = FirebaseAuth.instance.currentUser;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Text("Hi ${user?.displayName?.split(' ').first ?? 'Friend'}, 👋", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text("What service do you need today?", style: TextStyle(color: Colors.grey[600], fontSize: 16)),
          const SizedBox(height: 24),
          _buildQuickCategoryGrid(),
          const SizedBox(height: 30),
          _buildSectionHeader("Recommended Workers"),
          const SizedBox(height: 16),
          FutureBuilder<List<QueryDocumentSnapshot>>(
            future: _getRecommendedWorkers(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
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
            future: _getNearestWorkers(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              if (!snapshot.hasData || snapshot.data!.isEmpty) return _buildEmptyState("Looking for nearby online workers...");
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(16)),
            child: const TextField(decoration: InputDecoration(hintText: "Search for a service...", border: InputBorder.none, icon: Icon(Icons.search, color: Colors.grey))),
          ),
          const SizedBox(height: 24),
          const Text("Popular Categories", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 20, childAspectRatio: 0.8),
            itemCount: _professions.length,
            itemBuilder: (context, index) {
              final profession = _professions[index];
              final icon = _professionIcons[profession] ?? Icons.category_rounded;
              final color = _professionColors[profession] ?? Colors.blue;
              return GestureDetector(
                onTap: () => _showJobTypeSelection(profession),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: color.withAlpha(25), shape: BoxShape.circle, border: Border.all(color: color.withAlpha(40), width: 1), boxShadow: [BoxShadow(color: color.withAlpha(10), blurRadius: 10, offset: const Offset(0, 4))]),
                      child: Icon(icon, color: color, size: 32),
                    ),
                    const SizedBox(height: 8),
                    Text(profession, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 30),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.blue[900]!, Colors.blue[600]!], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Need urgent help?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 4),
                const Text("Book a live worker in 2 minutes!", style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: () {}, style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.blue[900]), child: const Text("Request Live Now"))
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildQuickCategoryGrid() {
    final categories = [
      {'name': 'Cleaning', 'icon': Icons.cleaning_services_rounded, 'color': Colors.blue},
      {'name': 'Repairing', 'icon': Icons.settings_rounded, 'color': Colors.orange},
      {'name': 'Laundry', 'icon': Icons.local_laundry_service_rounded, 'color': Colors.pink},
      {'name': 'Gardening', 'icon': Icons.park_rounded, 'color': Colors.green},
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 1.5),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final cat = categories[index];
        final color = cat['color'] as Color;
        return GestureDetector(
          onTap: () => _showJobTypeSelection(cat['name'] as String),
          child: Container(
            decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withAlpha(30))),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(cat['icon'] as IconData, color: color, size: 36),
                const SizedBox(height: 10),
                Text(cat['name'] as String, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color.withAlpha(240))),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold));
  }

  Widget _buildEmptyState(String msg) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Center(child: Text(msg, style: TextStyle(color: Colors.grey[500], fontStyle: FontStyle.italic))));
  }

  Widget _buildWorkerCard({required String name, required String profession, required String rating, required String info, String? photoUrl, String? addressType, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 15, offset: const Offset(0, 5))]),
        child: Row(
          children: [
            CircleAvatar(radius: 35, backgroundColor: Colors.blue[50], backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null, child: photoUrl == null ? Icon(Icons.person, color: Colors.blue[300], size: 30) : null),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      Text(profession, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                      if (addressType != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.blue.withAlpha(20), borderRadius: BorderRadius.circular(4)),
                          child: Text(addressType.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blue[800])),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(children: [const Icon(Icons.star, color: Colors.amber, size: 18), Text(" $rating ", style: const TextStyle(fontWeight: FontWeight.bold)), Text("• $info", style: TextStyle(color: Colors.grey[600], fontSize: 13))]),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
