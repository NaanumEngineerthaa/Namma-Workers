import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'no_internet_screen.dart';

class NoInternetWrapper extends StatefulWidget {
  final Widget child;
  const NoInternetWrapper({super.key, required this.child});

  @override
  State<NoInternetWrapper> createState() => _NoInternetWrapperState();
}

class _NoInternetWrapperState extends State<NoInternetWrapper> {
  late Stream<List<ConnectivityResult>> _connectivityStream;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _connectivityStream = Connectivity().onConnectivityChanged;
    // Initial check
    _checkInitialConnectivity();
  }

  Future<void> _checkInitialConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    _updateStatus(results);
  }

  void _updateStatus(List<ConnectivityResult> results) {
    // connectivity_plus version 6.0.0+ returns a list
    final bool offline = results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    if (offline != _isOffline) {
      setState(() {
        _isOffline = offline;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ConnectivityResult>>(
      stream: _connectivityStream,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final results = snapshot.data!;
          final bool offline = results.isEmpty || results.every((r) => r == ConnectivityResult.none);
          
          if (offline) {
            return const NoInternetScreen();
          }
        } else if (_isOffline) {
          // Fallback to initial check if stream hasn't emitted yet but we know we're offline
          return const NoInternetScreen();
        }

        return widget.child;
      },
    );
  }
}
