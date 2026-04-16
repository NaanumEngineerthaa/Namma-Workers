import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class WorkerLivePage extends StatelessWidget {
  final bool isOnline;
  final VoidCallback onToggle;

  const WorkerLivePage({
    super.key,
    required this.isOnline,
    required this.onToggle,
  });

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    if (timestamp is Timestamp) {
      DateTime date = timestamp.toDate();
      return DateFormat('hh:mm a, dd MMM').format(date);
    }
    return timestamp.toString();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 🔘 BIG TOGGLE BUTTON
                Center(
                  child: GestureDetector(
                    onTap: onToggle,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 280,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isOnline 
                            ? [Colors.green[600]!, Colors.green[400]!] 
                            : [Colors.red[600]!, Colors.red[400]!],
                        ),
                        borderRadius: BorderRadius.circular(40),
                        boxShadow: [
                          BoxShadow(
                            color: (isOnline ? Colors.green : Colors.red).withAlpha(100),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isOnline ? Icons.power_settings_new : Icons.power_off,
                            color: Colors.white,
                            size: 30,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            isOnline ? "GO OFFLINE" : "GO ONLINE",
                            style: const TextStyle(
                              fontSize: 22, 
                              fontWeight: FontWeight.bold, 
                              color: Colors.white,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // 📊 STATUS CARD
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(10),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Current Status", style: TextStyle(fontSize: 16)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: (isOnline ? Colors.green : Colors.red).withAlpha(30),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isOnline ? "ONLINE" : "OFFLINE",
                              style: TextStyle(
                                color: isOnline ? Colors.green[700] : Colors.red[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(user?.uid)
                            .snapshots(),
                        builder: (context, snapshot) {
                          final data = snapshot.data?.data() as Map<String, dynamic>?;
                          final lastActive = data?['lastActive'] ?? data?['lastSeen'];
                          
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Last Activity", style: TextStyle(color: Colors.grey)),
                              Text(
                                _formatTimestamp(lastActive),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // BOTTOM SECTION
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Text(
              "Stay online to receive instant hire requests from nearby customers.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
