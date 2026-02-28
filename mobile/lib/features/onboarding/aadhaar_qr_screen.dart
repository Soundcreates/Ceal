/// Aadhaar QR scan screen for onboarding.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:aftermath/core/app_theme.dart';
import 'package:aftermath/core/env.dart';
import 'package:aftermath/models/aadhaar_qr_data.dart';
import 'package:aftermath/providers.dart';

class AadhaarQrScreen extends ConsumerStatefulWidget {
  const AadhaarQrScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  ConsumerState<AadhaarQrScreen> createState() => _AadhaarQrScreenState();
}

class _AadhaarQrScreenState extends ConsumerState<AadhaarQrScreen> {
  final _scannerController = MobileScannerController();
  final _userIdController = TextEditingController(text: Env.onboardingUserId);

  bool _cameraGranted = false;
  bool _submitting = false;
  AadhaarQrData? _parsed;
  String? _error;
  bool _scanLocked = false;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _userIdController.dispose();
    super.dispose();
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    setState(() {
      _cameraGranted = status.isGranted;
      if (!status.isGranted) {
        _error = 'Camera permission is required to scan Aadhaar QR.';
      }
    });
  }

  Future<void> _handleDetect(BarcodeCapture capture) async {
    if (_scanLocked) return;
    final value = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .firstWhere((v) => v.trim().isNotEmpty, orElse: () => '');
    if (value.isEmpty) return;

    setState(() {
      _scanLocked = true;
      _error = null;
    });
    await _scannerController.stop();

    try {
      final parsed = AadhaarQrData.fromQrPayload(value);
      if (!mounted) return;
      setState(() => _parsed = parsed);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not parse Aadhaar XML from QR. Scan again.';
        _scanLocked = false;
      });
      await _scannerController.start();
    }
  }

  Future<void> _rescan() async {
    setState(() {
      _parsed = null;
      _error = null;
      _scanLocked = false;
    });
    await _scannerController.start();
  }

  Future<void> _submit() async {
    final parsed = _parsed;
    if (parsed == null) return;

    final userId = _userIdController.text.trim();
    if (userId.isEmpty) {
      setState(() => _error = 'User ID is required before submitting.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final backend = ref.read(backendServiceProvider);
    final result = await backend.submitAadhaarQr(userId: userId, data: parsed);

    if (!mounted) return;
    setState(() => _submitting = false);

    if (result.success) {
      widget.onComplete();
      return;
    }

    setState(() {
      _error = result.error ?? 'Failed to submit Aadhaar data.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(),
              Icon(Icons.qr_code_scanner, size: 72, color: AppTheme.sosColor),
              const SizedBox(height: 24),
              Text(
                'Scan Aadhaar QR',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Scan your Aadhaar QR. We parse the XML and submit your '
                'details to onboarding verification.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              _buildScannerArea(),
              const SizedBox(height: 16),
              TextField(
                controller: _userIdController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'User ID (UUID)',
                ),
              ),
              const SizedBox(height: 12),
              if (_parsed != null) _buildParsedCard(_parsed!),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: _submitting || _parsed == null ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Submit Aadhaar Data'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _submitting
                    ? null
                    : (_parsed == null ? null : _rescan),
                child: const Text('Scan Again'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _submitting ? null : widget.onComplete,
                child: const Text('Skip for now'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScannerArea() {
    if (!_cameraGranted) {
      return Container(
        width: double.infinity,
        height: 220,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: const Text('Camera permission not granted'),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: double.infinity,
        height: 220,
        child: MobileScanner(
          controller: _scannerController,
          onDetect: _handleDetect,
        ),
      ),
    );
  }

  Widget _buildParsedCard(AadhaarQrData data) {
    String valueOrDash(String? v) => v == null || v.isEmpty ? '—' : v;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Parsed Aadhaar Data',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text('Name: ${valueOrDash(data.name)}'),
          Text('Gender: ${valueOrDash(data.gender)}'),
          Text('DOB/YOB: ${valueOrDash(data.dob ?? data.yob)}'),
          Text('State: ${valueOrDash(data.state)}'),
          Text('District: ${valueOrDash(data.district)}'),
        ],
      ),
    );
  }
}
