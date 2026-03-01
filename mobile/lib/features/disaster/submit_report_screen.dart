/// Submit Report Screen — capture a disaster photo and submit a report.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import 'package:aftermath/core/app_theme.dart';
import 'package:aftermath/core/nb_components.dart';
import 'package:aftermath/features/disaster/disaster_notifier.dart';

class SubmitReportScreen extends ConsumerStatefulWidget {
  const SubmitReportScreen({super.key});

  @override
  ConsumerState<SubmitReportScreen> createState() =>
      _SubmitReportScreenState();
}

class _SubmitReportScreenState extends ConsumerState<SubmitReportScreen> {
  final _descController = TextEditingController();
  final _picker = ImagePicker();

  Uint8List? _imageBytes;
  String? _filename;
  double? _lat;
  double? _lon;
  bool _locating = false;
  String? _locationError;

  @override
  void initState() {
    super.initState();
    _acquireLocation();
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Future<void> _acquireLocation() async {
    setState(() {
      _locating = true;
      _locationError = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locating = false;
          _locationError = 'Location services are disabled.';
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _locating = false;
          _locationError = 'Location permission denied.';
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      setState(() {
        _lat = position.latitude;
        _lon = position.longitude;
        _locating = false;
      });
    } catch (e) {
      setState(() {
        _locating = false;
        _locationError = 'Could not get location: $e';
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (file == null) return;

    final bytes = await file.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _filename = file.name;
    });
  }

  bool get _canSubmit =>
      _imageBytes != null &&
      _lat != null &&
      _lon != null &&
      !ref.read(disasterNotifierProvider).isSubmitting;

  Future<void> _submit() async {
    if (!_canSubmit) return;

    final notifier = ref.read(disasterNotifierProvider.notifier);
    final status = await notifier.submitReport(
      imageBytes: _imageBytes!,
      filename: _filename ?? 'disaster.jpg',
      lat: _lat!,
      lon: _lon!,
      description: _descController.text.trim().isEmpty
          ? null
          : _descController.text.trim(),
    );

    if (!mounted) return;

    if (status != null) {
      _showResultDialog(status);
    }
  }

  void _showResultDialog(String status) {
    final Color color;
    final IconData icon;
    final String title;
    final String body;

    switch (status) {
      case 'verified':
        color = AppTheme.nbOk;
        icon = Icons.check_circle;
        title = 'Report Verified';
        body =
            'AI has confirmed this as a real disaster. Your report is now visible in the public feed.';
      case 'rejected':
        color = AppTheme.nbError;
        icon = Icons.cancel;
        title = 'Report Rejected';
        body =
            'AI flagged this image as not showing a real disaster. If you believe this is wrong, try submitting again with a clearer photo.';
      case 'flagged':
        color = AppTheme.nbWarn;
        icon = Icons.flag;
        title = 'Under Review';
        body =
            'Your report has been flagged for manual review. It will appear in the feed once approved.';
      default:
        color = AppTheme.nbInfo;
        icon = Icons.hourglass_top;
        title = 'Pending Review';
        body =
            'Your report has been submitted and is awaiting verification. It will appear in the feed once approved.';
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 10),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(body),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(disasterNotifierProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Report Disaster')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image section
            NBSectionHeader(label: 'Photo Evidence', icon: Icons.camera_alt),
            const SizedBox(height: 10),

            if (_imageBytes != null)
              NBCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.zero,
                      child: Image.memory(
                        _imageBytes!,
                        height: 220,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: AppTheme.nbInk,
                            width: AppTheme.nbBorder,
                          ),
                        ),
                      ),
                      child: TextButton.icon(
                        onPressed: () => setState(() {
                          _imageBytes = null;
                          _filename = null;
                        }),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Remove'),
                      ),
                    ),
                  ],
                ),
              )
            else
              NBCard(
                shadow: false,
                color: AppTheme.nbInk.withValues(alpha: 0.03),
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    Icon(Icons.add_a_photo,
                        size: 48,
                        color: AppTheme.nbInk.withValues(alpha: 0.2)),
                    const SizedBox(height: 12),
                    Text(
                      'Take or select a photo',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.nbInk.withValues(alpha: 0.4),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        NBButton(
                          label: 'Camera',
                          icon: Icons.camera_alt,
                          onPressed: () => _pickImage(ImageSource.camera),
                          color: AppTheme.nbAccent,
                          textColor: AppTheme.nbCard,
                        ),
                        const SizedBox(width: 12),
                        NBButton(
                          label: 'Gallery',
                          icon: Icons.photo_library,
                          onPressed: () => _pickImage(ImageSource.gallery),
                          color: AppTheme.nbAccent2,
                          textColor: AppTheme.nbCard,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // Location section
            NBSectionHeader(label: 'Location', icon: Icons.location_on),
            const SizedBox(height: 10),
            NBCard(
              shadow: false,
              padding: const EdgeInsets.all(14),
              child: _locating
                  ? const Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('Acquiring GPS location...'),
                      ],
                    )
                  : _locationError != null
                      ? Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: AppTheme.nbError, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _locationError!,
                                style: const TextStyle(
                                    color: AppTheme.nbError, fontSize: 13),
                              ),
                            ),
                            TextButton(
                              onPressed: _acquireLocation,
                              child: const Text('Retry'),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Icon(Icons.check_circle,
                                color: AppTheme.nbOk, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              '${_lat!.toStringAsFixed(6)}, ${_lon!.toStringAsFixed(6)}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
            ),

            const SizedBox(height: 20),

            // Description section
            NBSectionHeader(
                label: 'Description (optional)', icon: Icons.notes),
            const SizedBox(height: 10),
            TextField(
              controller: _descController,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                hintText:
                    'Briefly describe the situation (e.g. "Building on fire near main road")',
              ),
            ),

            const SizedBox(height: 28),

            // Submit button
            NBButton(
              label: 'SUBMIT REPORT',
              icon: Icons.send,
              onPressed: _canSubmit ? _submit : null,
              color: AppTheme.nbError,
              textColor: AppTheme.nbCard,
              isLoading: state.isSubmitting,
              expanded: true,
            ),

            const SizedBox(height: 12),
            Text(
              'Your report will be verified by AI before appearing in the public feed.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
