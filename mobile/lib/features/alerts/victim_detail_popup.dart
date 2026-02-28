/// Full-screen victim detail dialog — shown when the relayer taps an SOS
/// notification. Displays the victim's complete profile, RSSI-based distance
/// estimate, and action buttons for calling emergency services / opening maps.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:aftermath/models/sos_type.dart';
import 'package:aftermath/core/app_theme.dart';
import 'package:aftermath/core/nb_components.dart';

/// Data bag passed from the notification tap into the popup.
class VictimDetailData {
  const VictimDetailData({
    this.eventId,
    this.victimName,
    this.victimPhone,
    this.bloodGroup,
    this.allergies,
    this.conditions,
    this.contacts,
    this.lat,
    this.lon,
    this.rssi,
    this.timestamp,
    this.uid,
    this.sosType,
  });

  final String? eventId;
  final String? victimName;
  final String? victimPhone;
  final String? bloodGroup;
  final String? allergies;
  final String? conditions;

  /// List of `{"name": "...", "phone": "..."}` maps.
  final List<Map<String, String>>? contacts;
  final double? lat;
  final double? lon;
  final int? rssi;
  final String? timestamp;
  final String? uid;
  final SosType? sosType;

  /// Convert RSSI to an approximate human-readable distance string.
  ///
  /// Uses the log-distance path-loss model:
  ///   `d = 10 ^ ((txPower - rssi) / (10 * n))`
  ///
  /// txPower = measured RSSI at 1 metre (typically –59 dBm for BLE).
  /// n       = path-loss exponent (2 = free-space, 2.7–3.5 indoors).
  String get estimatedDistance {
    if (rssi == null) return 'Unknown';
    const txPower = -59; // dBm at 1m (BLE default)
    const n = 2.7; // indoor path-loss exponent
    final d = pow(10, (txPower - rssi!) / (10 * n));
    if (d < 1) return '< 1 m';
    if (d < 10) return '~${d.toStringAsFixed(1)} m';
    if (d < 1000) return '~${d.round()} m';
    return '~${(d / 1000).toStringAsFixed(1)} km';
  }

  /// Human label for RSSI signal strength.
  String get signalLabel {
    if (rssi == null) return 'Unknown';
    if (rssi! >= -50) return 'Very Strong';
    if (rssi! >= -65) return 'Strong';
    if (rssi! >= -80) return 'Moderate';
    if (rssi! >= -90) return 'Weak';
    return 'Very Weak';
  }

  factory VictimDetailData.fromJsonMap(Map<String, dynamic> json) {
    final contactsRaw = json['contacts'] as List<dynamic>?;
    final contactsList = contactsRaw?.map((c) {
      final m = c as Map<String, dynamic>;
      return {
        'name': m['name']?.toString() ?? '',
        'phone': m['phone']?.toString() ?? '',
      };
    }).toList();

    return VictimDetailData(
      eventId: json['eventId'] as String?,
      victimName: json['victimName'] as String?,
      victimPhone: json['victimPhone'] as String?,
      bloodGroup: json['bloodGroup'] as String?,
      allergies: json['allergies'] as String?,
      conditions: json['conditions'] as String?,
      contacts: contactsList,
      lat: (json['lat'] as num?)?.toDouble(),
      lon: (json['lon'] as num?)?.toDouble(),
      rssi: json['rssi'] as int?,
      timestamp: json['timestamp'] as String?,
      uid: json['uid'] as String?,
      sosType: json['sosType'] != null
          ? SosType.values.firstWhere(
              (t) => t.name == json['sosType'],
              orElse: () => SosType.general,
            )
          : null,
    );
  }
}

/// Show the victim detail popup as a modal bottom sheet / dialog.
Future<void> showVictimDetailPopup(
  BuildContext context,
  VictimDetailData data,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _VictimDetailSheet(data: data),
  );
}

// ---------------------------------------------------------------------------
// UI
// ---------------------------------------------------------------------------

class _VictimDetailSheet extends StatelessWidget {
  const _VictimDetailSheet({required this.data});
  final VictimDetailData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      decoration: BoxDecoration(
        color: AppTheme.nbBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(0)),
        border: const Border(
          top: BorderSide(color: AppTheme.nbInk, width: 4),
          left: BorderSide(color: AppTheme.nbInk, width: 4),
          right: BorderSide(color: AppTheme.nbInk, width: 4),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.nbInk.withValues(alpha: 0.3),
              borderRadius: BorderRadius.zero,
            ),
          ),
          const SizedBox(height: 8),

          // Title bar — NB error header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.nbError,
              border: const Border(
                top: BorderSide(color: AppTheme.nbInk, width: 4),
                bottom: BorderSide(color: AppTheme.nbInk, width: 4),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.zero,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 4),
                  ),
                  child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    data.victimName != null
                        ? '${data.sosType?.label ?? 'SOS'} — ${data.victimName}'
                        : data.sosType?.label.toUpperCase() ?? 'SOS EMERGENCY',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Content
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              shrinkWrap: true,
              children: [
                // ---- Distance / RSSI card ----
                _SectionCard(
                  icon: Icons.cell_tower,
                  title: 'Proximity',
                  children: [
                    _DetailRow('Estimated distance', data.estimatedDistance),
                    _DetailRow(
                      'Signal strength',
                      '${data.signalLabel}${data.rssi != null ? " (${data.rssi} dBm)" : ""}',
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ---- Victim identity ----
                _SectionCard(
                  icon: Icons.person,
                  title: 'Victim',
                  children: [
                    if (data.victimName != null)
                      _DetailRow('Name', data.victimName!),
                    if (data.victimPhone != null)
                      _DetailRow(
                        'Phone',
                        data.victimPhone!,
                        isTappable: true,
                        onTap: () {
                          launchUrl(
                            Uri.parse('tel:${data.victimPhone}'),
                            mode: LaunchMode.externalApplication,
                          );
                        },
                      ),
                    if (data.uid != null && data.victimName == null)
                      _DetailRow('BLE UID', data.uid!),
                  ],
                ),

                // ---- Medical ----
                if (_hasMedical) ...[
                  const SizedBox(height: 12),
                  _SectionCard(
                    icon: Icons.medical_services,
                    title: 'Medical Info',
                    children: [
                      if (data.bloodGroup?.isNotEmpty ?? false)
                        _DetailRow('Blood Group', data.bloodGroup!),
                      if (data.allergies?.isNotEmpty ?? false)
                        _DetailRow('Allergies', data.allergies!),
                      if (data.conditions?.isNotEmpty ?? false)
                        _DetailRow('Conditions', data.conditions!),
                    ],
                  ),
                ],

                // ---- Emergency contacts ----
                if (data.contacts != null && data.contacts!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _SectionCard(
                    icon: Icons.contacts,
                    title: 'Emergency Contacts',
                    children: [
                      for (final c in data.contacts!)
                        _DetailRow(
                          c['name'] ?? 'Contact',
                          c['phone'] ?? '?',
                          isTappable: true,
                          onTap: () {
                            final phone = c['phone'];
                            if (phone != null && phone.isNotEmpty) {
                              launchUrl(
                                Uri.parse('tel:$phone'),
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                        ),
                    ],
                  ),
                ],

                // ---- Location ----
                const SizedBox(height: 12),
                _SectionCard(
                  icon: Icons.location_on,
                  title: 'Location',
                  children: [
                    if (data.lat != null && data.lon != null)
                      _DetailRow(
                        'Coordinates',
                        '${data.lat!.toStringAsFixed(5)}, ${data.lon!.toStringAsFixed(5)}',
                      ),
                    if (data.timestamp != null)
                      _DetailRow('Time', _formatTimestamp(data.timestamp!)),
                  ],
                ),

                const SizedBox(height: 20),

                // ---- Action buttons ----
                Row(
                  children: [
                    Expanded(
                      child: NBButton(
                        label: 'Call 112',
                        icon: Icons.call,
                        color: AppTheme.nbError,
                        textColor: Colors.white,
                        expanded: true,
                        onPressed: () {
                          launchUrl(
                            Uri.parse('tel:112'),
                            mode: LaunchMode.externalApplication,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: NBButton(
                        label: 'Open Maps',
                        icon: Icons.map,
                        color: AppTheme.nbAccent2,
                        textColor: Colors.white,
                        expanded: true,
                        onPressed: () {
                          if (data.lat != null && data.lon != null) {
                            launchUrl(
                              Uri.parse(
                                'https://maps.google.com/?q=${data.lat},${data.lon}',
                              ),
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool get _hasMedical =>
      (data.bloodGroup?.isNotEmpty ?? false) ||
      (data.allergies?.isNotEmpty ?? false) ||
      (data.conditions?.isNotEmpty ?? false);

  String _formatTimestamp(String ts) {
    try {
      final dt = DateTime.parse(ts).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      final s = dt.second.toString().padLeft(2, '0');
      return '${dt.day}/${dt.month}/${dt.year} $h:$m:$s';
    } catch (_) {
      return ts;
    }
  }
}

// ---------------------------------------------------------------------------
// Reusable helpers
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
  });
  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return NBCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              NBIconBox(
                icon: icon,
                size: 28,
                bgColor: AppTheme.nbAccent2.withValues(alpha: 0.12),
                color: AppTheme.nbAccent2,
              ),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 1.0,
                  color: AppTheme.nbInk,
                ),
              ),
            ],
          ),
          const Divider(height: 16, thickness: 1, color: Color(0x154A4A4A)),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(
    this.label,
    this.value, {
    this.isTappable = false,
    this.onTap,
  });
  final String label;
  final String value;
  final bool isTappable;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final valueWidget = Text(
      value,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: isTappable ? AppTheme.nbAccent2 : null,
        decoration: isTappable ? TextDecoration.underline : null,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.nbInk.withValues(alpha: 0.5),
              ),
            ),
          ),
          Expanded(
            child: isTappable
                ? GestureDetector(onTap: onTap, child: valueWidget)
                : valueWidget,
          ),
        ],
      ),
    );
  }
}
