import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'widgets/loading_screen.dart';
import 'theme.dart';

class WorkerHistoryPage extends StatefulWidget {
  const WorkerHistoryPage({super.key});

  @override
  State<WorkerHistoryPage> createState() => _WorkerHistoryPageState();
}

class _WorkerHistoryPageState extends State<WorkerHistoryPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text("Please Login")));

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text("Job History", style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textColor)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textColor),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: AppTheme.subtitleColor,
          indicatorColor: AppTheme.primaryColor,
          dividerColor: Colors.transparent,
          isScrollable: true,
          tabs: const [
            Tab(text: "Completed"),
            Tab(text: "Picked"),
            Tab(text: "Cancelled"), 
            Tab(text: "Rejected"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildHistoryList(user.uid, ['completed'], collection: 'jobs'),
          _buildHistoryList(user.uid, ['picked'], collection: 'jobs'),
          _buildHistoryList(user.uid, ['cancelled', 'closed'], collection: 'jobs'),
          _buildHistoryList(user.uid, ['rejected', 'timeout'], collection: 'job_requests'),
        ],
      ),
    );
  }

  Widget _buildHistoryList(String uid, List<String> statuses, {required String collection}) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(collection)
          .where('workerId', isEqualTo: uid)
          .where('status', whereIn: statuses)
          .snapshots()
          .asyncMap((event) async {
            await Future.delayed(const Duration(milliseconds: 1500));
            return event;
          }),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const PremiumLoadingScreen();
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history_outlined, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text("No history found in this category", style: TextStyle(color: Colors.grey[500])),
              ],
            ),
          );
        }

        final docs = snapshot.data!.docs.toList();
        // Sort by updatedAt descending
        docs.sort((a, b) {
          final dataA = a.data() as Map<String, dynamic>;
          final dataB = b.data() as Map<String, dynamic>;
          final t1 = (dataA['updatedAt'] as Timestamp?) ?? (dataA['createdAt'] as Timestamp?) ?? Timestamp.now();
          final t2 = (dataB['updatedAt'] as Timestamp?) ?? (dataB['createdAt'] as Timestamp?) ?? Timestamp.now();
          return t2.compareTo(t1);
        });

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) => _buildHistoryCard(docs[index]),
        );
      },
    );
  }

  Widget _buildHistoryCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final status = data['status'] ?? 'N/A';
    final amount = data['amount'] ?? data['price'] ?? 0;
    final title = data['title'] ?? data['profession'] ?? data['service'] ?? "Job Request";
    final Timestamp? ts = data['updatedAt'] as Timestamp? ?? data['createdAt'] as Timestamp?;
    final timestamp = ts?.toDate() ?? DateTime.now();

    Color statusColor = AppTheme.subtitleColor;
    if (status == 'completed') statusColor = AppTheme.primaryColor;
    if (status == 'picked') statusColor = AppTheme.accentColor;
    if (status == 'cancelled' || status == 'closed') statusColor = AppTheme.unselectedColor;
    if (status == 'rejected') statusColor = AppTheme.unselectedColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppTheme.primaryColor.withAlpha(10), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: statusColor.withAlpha(30), borderRadius: BorderRadius.circular(8)),
                child: Text(
                  status.toString().toUpperCase(),
                  style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                DateFormat('dd MMM, hh:mm a').format(timestamp),
                style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textColor)),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.subtitleColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  data['location'] ?? "Location N/A",
                  style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                data['type'] == 'live' ? "Hire Now" : "Scheduled",
                style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w600, fontSize: 13),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "₹$amount",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                  ),
                  if (data['hours'] != null)
                    Text(
                      "${data['hours']} hr${data['hours'] > 1 ? 's' : ''} ${data['tip'] != null && data['tip'] > 0 ? '+ ₹${data['tip']} tip' : ''}",
                      style: TextStyle(color: Colors.grey[600], fontSize: 11),
                    )
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
