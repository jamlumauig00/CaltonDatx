import 'package:flutter/material.dart';

class LoadingTextAnimation extends StatefulWidget {
  const LoadingTextAnimation({super.key});

  @override
  State<LoadingTextAnimation> createState() => _LoadingTextAnimationState();
}

class _LoadingTextAnimationState extends State<LoadingTextAnimation> {
  String _dots = '';
  int _dotCount = 0;

  @override
  void initState() {
    super.initState();
    _startAnimation();
  }

  void _startAnimation() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 500));

      // Only update the state if the widget is still mounted
      if (mounted) {
        setState(() {
          _dotCount = (_dotCount + 1) % 4;
          _dots = '.' * _dotCount;
        });
      }
      return mounted; // Check if the widget is still in the tree
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      'Loading$_dots',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.2,
      ),
    );
  }
}
