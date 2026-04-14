import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

class ScheduledRequestsPage extends StatefulWidget {
  final String profession;
  final Position? currentPosition;
  final List<DocumentSnapshot> activeJobs;

  const ScheduledRequestsPage({
    super.key,
    required this.profession,
    this.currentPosition,
    required this.activeJobs,
  });

  @override
  State<ScheduledRequestsPage> createState() => _ScheduledRequestsPageState();
}

class _ScheduledRequestsPageState extends State<ScheduledRequestsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("All Scheduled Requests", style: TextStyle(fontWeight: FontWeight.bold)),
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
            .where('type', isEqualTo: 'scheduled')
            .where('status', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return _buildEmptyState("No scheduled jobs found.");

          final filteredDocs = docs.where((pendingDoc) {
            final pData = pendingDoc.data() as Map<String, dynamic>;
            final title = (pData['title'] ?? '').toString().toLowerCase();
            final prof = widget.profession.toLowerCase();
            final isMatch = title.contains(prof) || prof.contains(title);
            if (!isMatch) return false;

            final pStart = (pData['startTime'] as Timestamp?)?.toDate();
            final pEnd = (pData['endTime'] as Timestamp?)?.toDate();
            if (pStart == null || pEnd == null) return false;

            for (var activeDoc in widget.activeJobs) {
              final aData = activeDoc.data() as Map<String, dynamic>;
              final aStart = (aData['startTime'] as Timestamp?)?.toDate();
              final aEnd = (aData['endTime'] as Timestamp?)?.toDate();
              if (aStart != null && aEnd != null) {
                if (pStart.isBefore(aEnd) && pEnd.isAfter(aStart)) return false; 
              }
            }
            return true;
          }).toList();

          if (filteredDocs.isEmpty) return _buildEmptyState("No requests matching your profession or schedule.");

          // Sort by startTime Ascending (Soonest first) 
          filteredDocs.sort((a, b) {
            final t1 = (a['startTime'] as Timestamp?)?.toDate() ?? DateTime.now();
            final t2 = (b['startTime'] as Timestamp?)?.toDate() ?? DateTime.now();
            return t1.compareTo(t2);
          });

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: filteredDocs.length,
            itemBuilder: (context, index) => _buildJobCard(filteredDocs[index]),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(msg, style: TextStyle(color: Colors.grey[500], fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildJobCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final title = data['title'] ?? 'Job';
    final address = data['location'] ?? 'Address N/A';
    final price = data['price']?.toString() ?? 'TBD';
    final userId = data['customerId'] ?? data['userId'] ?? '';
    
    String timeDisplay = "TBD";
    final start = (data['startTime'] as Timestamp?)?.toDate();
    final end = (data['endTime'] as Timestamp?)?.toDate();
    if (start != null && end != null) {
      timeDisplay = "${DateFormat('jm').format(start)} - ${DateFormat('jm').format(end)}";
    }

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

    return Container(
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
                    decoration: BoxDecoration(color: Colors.orange.withAlpha(30), borderRadius: BorderRadius.circular(8)),
                    child: Text("SCHEDULED", style: TextStyle(color: Colors.orange[800], fontSize: 10, fontWeight: FontWeight.bold)),
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

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                   onPressed: () => _rejectJob(doc.id),
                   child: const Text("Reject"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _acceptJob(doc.id, data),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], foregroundColor: Colors.white),
                  child: const Text("Accept"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _acceptJob(String jobId, Map<String, dynamic> jobData) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    await FirebaseFirestore.instance.collection('jobs').doc(jobId).update({
      'workerId': user.uid,
      'status': 'accepted',
      'acceptedAt': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Job accepted successfully! ✅")));
    }
  }

  Future<void> _rejectJob(String jobId) async {
    await FirebaseFirestore.instance.collection('jobs').doc(jobId).update({'status': 'rejected'});
  }
}
