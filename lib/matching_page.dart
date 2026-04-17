import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'tracking_page.dart';
import 'theme.dart';

class MatchingPage extends StatefulWidget {
  final String jobId;
  final String service;
  final double userLat;
  final double userLng;

  const MatchingPage({
    super.key,
    required this.jobId,
    required this.service,
    required this.userLat,
    required this.userLng,
  });

  @override
  State<MatchingPage> createState() => _MatchingPageState();
}

class _MatchingPageState extends State<MatchingPage> {
  String _statusText = "Analyzing your location...";
  bool _issearching = true;
  StreamSubscription? _jobSubscription;

  Timer? _timeoutTimer;
  final DateTime _startTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _startMatchingProcess();
    _listenToJobStatus();
    _startTimeoutTimer();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _jobSubscription?.cancel();
    super.dispose();
  }

  void _startTimeoutTimer() {
    _timeoutTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (DateTime.now().difference(_startTime).inMinutes >= 30) {
        timer.cancel();
        await FirebaseFirestore.instance.collection('jobs').doc(widget.jobId).update({
          'status': 'closed',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  void _listenToJobStatus() {
    _jobSubscription = FirebaseFirestore.instance
        .collection('jobs')
        .doc(widget.jobId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) return;
      final data = snapshot.data()!;
      final status = data['status'];
      
      if (status == 'picked') {
        _jobSubscription?.cancel();
        _timeoutTimer?.cancel();
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => TrackingPage(
                jobId: widget.jobId,
                workerId: data['workerId'],
                userLat: widget.userLat,
                userLng: widget.userLng,
              ),
            ),
          );
        }
      } else if (status == 'cancelled') {
        _jobSubscription?.cancel();
        _timeoutTimer?.cancel();
        if (mounted) Navigator.pop(context);
      } else if (status == 'closed') {
        _jobSubscription?.cancel();
        _timeoutTimer?.cancel();
        if (mounted) {
          setState(() {
            _statusText = "No workers found in 30 minutes. Request closed.";
            _issearching = false;
          });
        }
      } else if (status == 'completed') {
        _jobSubscription?.cancel();
        _timeoutTimer?.cancel();
        if (mounted) {
          // Typically wouldn't happen during matching, but just in case
          Navigator.pop(context);
        }
      }
    });
  }

  Future<void> _startMatchingProcess() async {
    setState(() => _statusText = "Finding nearest ${widget.service}s...");

    try {
      // Fetch job price to include in requests for history
      final jobDoc = await FirebaseFirestore.instance.collection('jobs').doc(widget.jobId).get();
      final jobData = jobDoc.data() ?? {};
      final amount = jobData['amount'] ?? jobData['price'] ?? 0;
      final hours = jobData['hours'];
      final tip = jobData['tip'];

      final workersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'worker')
          .where('profession', isEqualTo: widget.service)
          .where('isOnline', isEqualTo: true)
          .where('isBusy', isEqualTo: false)
          .get();

      if (workersSnapshot.docs.isEmpty) {
        setState(() {
          _statusText = "No ${widget.service}s available right now. Please try again later.";
          _issearching = false;
        });
        return;
      }

      List<QueryDocumentSnapshot> workers = workersSnapshot.docs;
      workers.sort((a, b) {
        final d1 = _calculateDistance(widget.userLat, widget.userLng, (a.data() as Map)['latitude'], (a.data() as Map)['longitude']);
        final d2 = _calculateDistance(widget.userLat, widget.userLng, (b.data() as Map)['latitude'], (b.data() as Map)['longitude']);
        return d1.compareTo(d2);
      });

      tryWorkersSequentially(workers, 0, amount, hours, tip);

    } catch (e) {
      debugPrint("Error matching: $e");
      setState(() => _statusText = "Error matching workers: $e");
    }
  }

  Future<void> tryWorkersSequentially(List<QueryDocumentSnapshot> workers, int index, dynamic amount, dynamic hours, dynamic tip) async {
    if (index >= workers.length) {
      if (mounted) {
        setState(() {
          _statusText = "No more workers available. Retrying shortly...";
          _issearching = false;
        });
      }
      return;
    }

    final worker = workers[index];
    final workerId = worker.id;
    final workerRef = FirebaseFirestore.instance.collection('users').doc(workerId);
    final workerDoc = await workerRef.get();
    final workerData = workerDoc.data() as Map<String, dynamic>?;

    if (workerData == null || workerData['isOnline'] != true || workerData['isBusy'] == true) {
      // Skip this worker and try next
      tryWorkersSequentially(workers, index + 1, amount, hours, tip);
      return;
    }

    if (mounted) {
      setState(() => _statusText = "Requesting ${workerData['name'] ?? 'nearest worker'}...");
    }

    // 1. Create a request doc with expiry
    final reqRef = await FirebaseFirestore.instance.collection('job_requests').add({
      'jobId': widget.jobId,
      'workerId': workerId,
      'status': 'pending',
      'amount': amount,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 5))),
      'customerName': FirebaseAuth.instance.currentUser?.displayName ?? 'Customer',
      'service': widget.service,
      'hours': hours,
      'tip': tip,
    });

    // 2. Track in main job doc
    await FirebaseFirestore.instance.collection('jobs').doc(widget.jobId).update({
      'requestedWorkers': FieldValue.arrayUnion([workerId]),
    });

    // 3. ✨ LISTEN for early rejection or timeout
    final completer = Completer<void>();
    StreamSubscription? sub;

    sub = reqRef.snapshots().listen((snapshot) {
      if (!snapshot.exists) return;
      final status = snapshot.data()?['status'];
      if (status == 'picked' || status == 'rejected' || status == 'timeout') {
        if (!completer.isCompleted) completer.complete();
      }
    });

    // ⏳ WAIT for either: worker response OR 5 MIN timeout
    await Future.any([
      completer.future,
      Future.delayed(const Duration(minutes: 5))
    ]);

    await sub.cancel();

    if (!mounted) return;

    final jobDoc = await FirebaseFirestore.instance.collection('jobs').doc(widget.jobId).get();
    if (jobDoc.data()?['status'] == 'picked' || jobDoc.data()?['status'] == 'cancelled' || jobDoc.data()?['status'] == 'closed') return;

    // 4. Mark request as timeout if it was still pending
    final currentReq = await reqRef.get();
    if (currentReq['status'] == 'pending') {
      await reqRef.update({'status': 'timeout'});
    }

    // 5. Try next worker
    tryWorkersSequentially(workers, index + 1, amount, hours, tip);
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371; // km
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  double _toRadians(double degree) => degree * pi / 180;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.bgGlowingEffect),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(40.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_issearching)
                  const SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(strokeWidth: 6, color: AppTheme.primaryColor),
                  ),
                if (!_issearching)
                  const Icon(Icons.search_off_rounded, size: 90, color: AppTheme.unselectedColor),
                const SizedBox(height: 48),
                Text(
                  _issearching ? "Seeking Experts..." : "Search Suspended",
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppTheme.textColor),
                ),
                const SizedBox(height: 16),
                Text(
                  _statusText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, color: AppTheme.subtitleColor, fontWeight: FontWeight.w600, height: 1.5),
                ),
                const SizedBox(height: 56),
                if (!_issearching)
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor, 
                      minimumSize: const Size(240, 68), 
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      elevation: 12,
                      shadowColor: AppTheme.primaryColor.withAlpha(120),
                    ),
                    child: const Text("Return home", style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                  ),
                if (_issearching)
                  TextButton(
                    onPressed: () async {
                      try {
                        await FirebaseFirestore.instance.collection('jobs').doc(widget.jobId).update({
                          'status': 'cancelled',
                          'updatedAt': FieldValue.serverTimestamp(),
                        });
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        debugPrint("Cancel fail: $e");
                        if (context.mounted) Navigator.pop(context);
                      }
                    },
                    child: const Text("Cancel Request", style: TextStyle(color: AppTheme.unselectedColor, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
