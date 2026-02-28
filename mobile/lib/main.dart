import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Volume Trigger Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  static const EventChannel _volumeEventChannel = EventChannel(
    'volume_trigger/events',
  );

  StreamSubscription<dynamic>? _volumeSubscription;
  int _doublePressCount = 0;

  @override
  void initState() {
    super.initState();

    if (Platform.isAndroid) {
      _volumeSubscription = _volumeEventChannel.receiveBroadcastStream().listen(
        _onVolumeEvent,
        onError: _onVolumeError,
      );
    }
  }

  void _onVolumeEvent(dynamic event) {
    if (!mounted) return;

    if (event == 'double_volume_up') {
      setState(() {
        _doublePressCount++;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Volume Up pressed twice'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _onVolumeError(dynamic error) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Volume trigger error: $error')));
  }

  @override
  void dispose() {
    _volumeSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Volume Trigger Demo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Double press the volume-up hardware button to trigger a UI notification.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Make sure Accessibility Service is enabled for this app in Android settings.',
            ),
            const SizedBox(height: 24),
            Text('Detected double presses: $_doublePressCount'),
          ],
        ),
      ),
    );
  }
}
