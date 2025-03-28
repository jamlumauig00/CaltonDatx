import 'package:caltondatx/utils/permissions_helper.dart';
import 'package:flutter/material.dart';
import 'webview_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _requestPermissions();
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const WebViewScreen(),
          transitionDuration: Duration.zero, // No transition
          reverseTransitionDuration: Duration.zero, // No reverse transition
        ),
      );
    });
  }

  Future<void> _requestPermissions() async {
    await PermissionHelper.requestPermissions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/splash.png', fit: BoxFit.cover),
          ),
        ],
      ),
    );
  }
}
