library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:aftermath/core/app_theme.dart';
import 'package:aftermath/providers.dart';

class ManualKycFormScreen extends ConsumerStatefulWidget {
  const ManualKycFormScreen({
    super.key,
    required this.onComplete,
    required this.onBackToScan,
  });

  final VoidCallback onComplete;
  final VoidCallback onBackToScan;

  @override
  ConsumerState<ManualKycFormScreen> createState() =>
      _ManualKycFormScreenState();
}

class _ManualKycFormScreenState extends ConsumerState<ManualKycFormScreen> {
  static const _storage = FlutterSecureStorage();

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _dobController = TextEditingController();
  final _yobController = TextEditingController();
  final _stateController = TextEditingController();
  final _districtController = TextEditingController();
  final _pincodeController = TextEditingController();

  String? _sex;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _dobController.dispose();
    _yobController.dispose();
    _stateController.dispose();
    _districtController.dispose();
    _pincodeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    final userId = await _storage.read(key: 'aftermath_user_id') ?? '';
    if (userId.trim().isEmpty) {
      setState(() {
        _submitting = false;
        _error = 'User ID not found. Please restart signup.';
      });
      return;
    }

    final age = int.parse(_ageController.text.trim());

    final backend = ref.read(backendServiceProvider);
    final result = await backend.submitManualKyc(
      userId: userId,
      name: _nameController.text.trim(),
      age: age,
      sex: _sex!,
      dob: _dobController.text.trim(),
      yob: _yobController.text.trim(),
      state: _stateController.text.trim(),
      district: _districtController.text.trim(),
      pincode: _pincodeController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (result.success) {
      widget.onComplete();
      return;
    }

    setState(() {
      _error = result.error ?? 'Failed to save manual KYC details';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: widget.onBackToScan,
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Manual KYC Details',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Aadhaar scan was skipped. Fill the details manually to continue.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 24),
                _textField(
                  controller: _nameController,
                  label: 'Full Name',
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _textField(
                  controller: _ageController,
                  label: 'Age',
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final age = int.tryParse((v ?? '').trim());
                    if (age == null || age <= 0 || age > 120) {
                      return 'Enter valid age';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _sex,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Sex',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'M', child: Text('Male')),
                    DropdownMenuItem(value: 'F', child: Text('Female')),
                    DropdownMenuItem(
                      value: 'T',
                      child: Text('Transgender/Other'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _sex = value),
                  validator: (v) => v == null ? 'Select sex' : null,
                ),
                const SizedBox(height: 12),
                _textField(
                  controller: _dobController,
                  label: 'DOB (DD/MM/YYYY) - optional',
                ),
                const SizedBox(height: 12),
                _textField(
                  controller: _yobController,
                  label: 'Year of Birth (YYYY) - optional',
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(t)) {
                      return 'Enter 4-digit year';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _textField(
                  controller: _stateController,
                  label: 'State',
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'State is required'
                      : null,
                ),
                const SizedBox(height: 12),
                _textField(
                  controller: _districtController,
                  label: 'District',
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'District is required'
                      : null,
                ),
                const SizedBox(height: 12),
                _textField(
                  controller: _pincodeController,
                  label: 'Pincode',
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (!RegExp(r'^\d{6}$').hasMatch(t)) {
                      return 'Enter 6-digit pincode';
                    }
                    return null;
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.sosColor,
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Submit Manual Details'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
      ),
      validator: validator,
    );
  }
}
