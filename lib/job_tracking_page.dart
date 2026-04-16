import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'tracking_page.dart';

class JobTrackingPage extends StatelessWidget {
  final String jobId;

  const JobTrackingPage({super.key, required this.jobId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Job Details", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('jobs').doc(jobId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (!snapshot.data!.exists) return const Center(child: Text("Job not found."));

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final status = data['status'];
          final type = data['type'];
          final scheduledTime = data['startTime'] as Timestamp?;
          final userLat = (data['latitude'] as num?)?.toDouble() ?? 0.0;
          final userLng = (data['longitude'] as num?)?.toDouble() ?? 0.0;
          final workerId = data['workerId'];

          final now = DateTime.now();

          // Case 3 & 1: Both go to active map tracking
          bool shouldTrack = false;
          if (status == 'picked') {
            if (type == 'live') {
              shouldTrack = true;
            } else if (type == 'scheduled' && scheduledTime != null) {
              if (now.isAfter(scheduledTime.toDate()) || now.isAtSameMomentAs(scheduledTime.toDate())) {
                shouldTrack = true;
              }
            }
          }

          if (shouldTrack && workerId != null) {
            return TrackingPage(
              jobId: jobId,
              workerId: workerId,
              userLat: userLat,
              userLng: userLng,
            );
          }

          // Case 2: Scheduled job BEFORE time (or any other state without live tracking)
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildJobCard(data),
                const SizedBox(height: 32),
                if (status == 'picked' && workerId != null)
                  _buildWorkerInfo(workerId, data)
                else if (status == 'pending' || status == 'active')
                  const Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.hourglass_top_rounded, size: 64, color: Colors.orange),
                          SizedBox(height: 16),
                          Text(
                            "Waiting for a worker to accept",
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: Center(
                      child: Text(
                        "Job Status: ${status.toString().toUpperCase()}",
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildJobCard(Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "${data['title'] ?? data['profession'] ?? 'Service'} Job",
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  (data['type'] ?? 'live').toString().toUpperCase(),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            "₹${data['amount'] ?? data['price'] ?? 0}",
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.location_on, size: 16, color: Colors.grey),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  data['location'] ?? 'Location not available',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (data['type'] == 'scheduled' && data['startTime'] != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.calendar_month, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  "Scheduled for: ${_formatTimestamp(data['startTime'])}",
                  style: TextStyle(color: Colors.grey[700], fontSize: 13),
                ),
              ],
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildWorkerInfo(String workerId, Map<String, dynamic> jobData) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(workerId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (!snapshot.data!.exists) return const SizedBox();

        final workerData = snapshot.data!.data() as Map<String, dynamic>;
        
        return Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Worker Assigned",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.orange[50],
                      backgroundImage: workerData['photoUrl'] != null ? NetworkImage(workerData['photoUrl']) : null,
                      child: workerData['photoUrl'] == null ? const Icon(Icons.person, color: Colors.orange, size: 30) : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            workerData['name'] ?? 'Worker',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            workerData['profession'] ?? jobData['profession'] ?? 'Service',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          Row(
                            children: [
                              const Icon(Icons.star, color: Colors.amber, size: 16),
                              Text(" ${workerData['rating'] ?? 5.0}", style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.query_builder_rounded, size: 64, color: Colors.blue),
                      SizedBox(height: 16),
                      Text(
                        "Waiting for scheduled time",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        "Live tracking will start automatically.",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return "N/A";
    final dt = timestamp.toDate();
    // basic format, pad manually
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour < 12 ? "AM" : "PM";
    final min = dt.minute.toString().padLeft(2, '0');
    return "$hour:$min $ampm, ${dt.day}/${dt.month}";
  }
}
