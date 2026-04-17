import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'widgets/loading_screen.dart';
import 'theme.dart';

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
      color: AppTheme.backgroundColor,
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
                            ? [AppTheme.primaryColor, AppTheme.accentColor] 
                            : [AppTheme.unselectedColor, AppTheme.unselectedColor.withAlpha(200)],
                        ),
                        borderRadius: BorderRadius.circular(40),
                        boxShadow: AppTheme.glowingShadow,
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
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withAlpha(10),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Current Status", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppTheme.textColor)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: (isOnline ? AppTheme.primaryColor : AppTheme.unselectedColor).withAlpha(15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isOnline ? "ONLINE" : "OFFLINE",
                              style: TextStyle(
                                color: isOnline ? AppTheme.primaryColor : AppTheme.unselectedColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Divider(height: 1, color: Color(0xFFEEEEEE)),
                      const SizedBox(height: 20),
                      StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(user?.uid)
                            .snapshots()
                            .asyncMap((event) async {
                              await Future.delayed(const Duration(milliseconds: 1500));
                              return event;
                            }),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                             return const Padding(
                               padding: EdgeInsets.symmetric(vertical: 4),
                               child: PremiumLoadingScreen(isFullPage: false),
                             );
                          }
                          final data = snapshot.data?.data() as Map<String, dynamic>?;
                          final lastActive = data?['lastActive'] ?? data?['lastSeen'];
                          
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Last Activity", style: TextStyle(color: AppTheme.subtitleColor)),
                              Text(
                                _formatTimestamp(lastActive),
                                style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textColor),
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
