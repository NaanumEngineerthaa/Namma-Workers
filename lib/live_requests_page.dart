import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

class LiveRequestsPage extends StatefulWidget {
  final String profession;
  final Position? currentPosition;
  final bool alreadyHasLiveJob;

  const LiveRequestsPage({
    super.key,
    required this.profession,
    this.currentPosition,
    required this.alreadyHasLiveJob,
  });

  @override
  State<LiveRequestsPage> createState() => _LiveRequestsPageState();
}

class _LiveRequestsPageState extends State<LiveRequestsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("All Live Requests", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('jobs')
            .where('type', isEqualTo: 'live')
            .where('status', isEqualTo: 'searching')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return _buildEmptyState("No live requests currently");

          final now = DateTime.now();
          List<DocumentSnapshot> validDocs = [];

          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final title = (data['title'] ?? '').toString().toLowerCase();
            final prof = widget.profession.toLowerCase();
            
            if (title.contains(prof) || prof.contains(title)) {
              final expiresAtField = (data['expiresAt'] as Timestamp?)?.toDate();
              final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
              final effectiveExpiresAt = expiresAtField ?? createdAt.add(const Duration(minutes: 30));

              if (now.isAfter(effectiveExpiresAt)) {
                doc.reference.update({'status': 'closed', 'closedAt': FieldValue.serverTimestamp()});
              } else {
                validDocs.add(doc);
              }
            }
          }

          final filteredDocs = validDocs;

          if (filteredDocs.isEmpty) return _buildEmptyState("No requests matching your profession");

          // Sort Newer First (t2.compareTo(t1))
          filteredDocs.sort((a, b) {
            final t1 = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
            final t2 = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
            return t2.compareTo(t1);
          });

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: filteredDocs.length,
            itemBuilder: (context, index) => _buildJobCard(
              filteredDocs[index],
              isDisabled: widget.alreadyHasLiveJob,
              disabledReason: "Already has active live job",
            ),
          );
        },
      ),
    );
  }

  String _getRelativeTime(DateTime dateTime) {
    final Duration diff = DateTime.now().difference(dateTime);
    if (diff.inDays >= 7) return "${(diff.inDays / 7).floor()} weeks ago";
    if (diff.inDays >= 1) return "${diff.inDays} days ago";
    if (diff.inHours >= 1) return "${diff.inHours} hours ago";
    if (diff.inMinutes >= 1) return "${diff.inMinutes} mins ago";
    return "Just now";
  }

  Widget _buildEmptyState(String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(msg, style: TextStyle(color: Colors.grey[500], fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildJobCard(DocumentSnapshot doc, {bool isDisabled = false, String? disabledReason}) {
    final data = doc.data() as Map<String, dynamic>;
    final title = data['title'] ?? 'Job';
    final address = data['location'] ?? 'Address N/A';
    final price = data['price']?.toString() ?? 'TBD';
    final userId = data['customerId'] ?? data['userId'] ?? '';
    
    DateTime? createdAt = (data['createdAt'] as Timestamp?)?.toDate();
    String timeDisplay = createdAt != null ? _getRelativeTime(createdAt) : "Now";

    String distanceStr = "N/A";
    if (widget.currentPosition != null && data['latitude'] != null && data['longitude'] != null) {
      double dist = Geolocator.distanceBetween(
        widget.currentPosition!.latitude, 
        widget.currentPosition!.longitude, 
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.red.withAlpha(30), borderRadius: BorderRadius.circular(8)),
                      child: Text("LIVE", style: TextStyle(color: Colors.red[700], fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    Text(distanceStr, style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.w500)),
                  ],
                ),
                Text("₹$price", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
              ],
            ),
            const SizedBox(height: 12),
            
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
                child: Text("⚠ $disabledReason", style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
              ),

            const SizedBox(height: 16),
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
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red[600], foregroundColor: Colors.white),
                    child: const Text("Accept"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _acceptJob(String jobId, Map<String, dynamic> jobData) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    await FirebaseFirestore.instance.collection('jobs').doc(jobId).update({
      'workerId': user.uid,
      'status': 'picked',
      'acceptedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'isBusy': true,
    });

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Job accepted successfully! ✅")));
    }
  }

  Future<void> _rejectJob(String jobId) async {
    await FirebaseFirestore.instance.collection('jobs').doc(jobId).update({'status': 'rejected'});
    // No need to pop, just let the stream remove it
  }
}
