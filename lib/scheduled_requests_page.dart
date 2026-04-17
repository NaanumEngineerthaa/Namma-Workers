import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'widgets/loading_screen.dart';
import 'theme.dart';

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
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text("All Scheduled Requests", style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textColor)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('jobs')
            .where('type', isEqualTo: 'scheduled')
            .where('status', whereIn: ['active', 'pending'])
            .snapshots()
            .asyncMap((event) async {
              await Future.delayed(const Duration(milliseconds: 1500));
              return event;
            }),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const PremiumLoadingScreen();
          if (!snapshot.hasData) return const PremiumLoadingScreen();
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return _buildEmptyState("No scheduled jobs found.");

          final now = DateTime.now();
          List<DocumentSnapshot> validDocs = [];

          for (var pendingDoc in docs) {
            final pData = pendingDoc.data() as Map<String, dynamic>;
            final title = (pData['title'] ?? '').toString().toLowerCase();
            final prof = widget.profession.toLowerCase();
            final isMatch = title.contains(prof) || prof.contains(title);
            if (!isMatch) continue;

            final isExpired = pData['isExpired'] ?? false;
            if (isExpired) continue;

            final expiresAtField = (pData['expiresAt'] as Timestamp?)?.toDate();
            final createdAt = (pData['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
            final startFallback = (pData['startTime'] as Timestamp?)?.toDate() ?? createdAt;
            final effectiveExpiresAt = expiresAtField ?? startFallback.add(Duration(hours: pData['hours'] ?? 1)).add(const Duration(hours: 24)); 

            if (now.isAfter(effectiveExpiresAt)) {
              pendingDoc.reference.update({'isExpired': true});
              continue;
            }

            final pStart = (pData['startTime'] as Timestamp?)?.toDate();
            final pEnd = (pData['endTime'] as Timestamp?)?.toDate();
            if (pStart == null || pEnd == null) continue;

            validDocs.add(pendingDoc);
          }

          final filteredDocs = validDocs;

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
    final amount = data['amount']?.toString() ?? data['price']?.toString() ?? 'TBD';
    final hours = data['hours'];
    final tip = data['tip'];
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
                      decoration: BoxDecoration(color: AppTheme.primaryColor.withAlpha(20), borderRadius: BorderRadius.circular(8)),
                      child: Text("SCHEDULED", style: TextStyle(color: AppTheme.primaryColor, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    Text(distanceStr, style: TextStyle(fontSize: 12, color: AppTheme.subtitleColor, fontWeight: FontWeight.w500)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text("₹$amount", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                    if (hours != null)
                      Text(
                        "$hours hr${hours > 1 ? 's' : ''} ${tip != null && tip > 0 ? '+ ₹$tip tip' : ''}",
                        style: TextStyle(color: AppTheme.subtitleColor, fontSize: 11),
                      )
                  ],
                ),
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
                return Text(userName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textColor));
              },
            ),
            const SizedBox(height: 4),
            Text(title, style: TextStyle(fontSize: 16, color: AppTheme.primaryColor, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),

            // Row 4: Service Type
            Row(
              children: [
                Icon(Icons.home_work_outlined, color: AppTheme.subtitleColor, size: 16),
                const SizedBox(width: 4),
                Text(data['serviceType'] ?? "Home Service", style: TextStyle(color: AppTheme.subtitleColor, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 4),

            // Row 5: Location
            Row(
              children: [
                Icon(Icons.location_on_outlined, color: AppTheme.subtitleColor, size: 16),
                const SizedBox(width: 4),
                Expanded(child: Text(address, style: TextStyle(color: AppTheme.subtitleColor, fontSize: 13))),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.access_time, color: AppTheme.subtitleColor, size: 16),
                const SizedBox(width: 4),
                Text(timeDisplay, style: TextStyle(color: AppTheme.subtitleColor, fontSize: 13)),
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
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
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
      'status': 'picked',
      'acceptedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
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
