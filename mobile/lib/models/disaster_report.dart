/// Disaster Report — data model for community-sourced disaster reports.
library;

/// Verification status assigned by Gemini LLM.
enum VerificationStatus { verified, rejected, flagged, pending }

/// Authority response status.
enum AuthorityStatus { none, dispatched, investigating, resolved }

/// Disaster category.
enum DisasterCategory { fire, flood, accident, infrastructure, medical, other }

class DisasterReport {
  const DisasterReport({
    required this.id,
    required this.userId,
    required this.lat,
    required this.lon,
    required this.imageUrl,
    required this.category,
    required this.severityScore,
    required this.llmConfidence,
    required this.verificationStatus,
    this.rejectionReason,
    this.description,
    this.authorityStatus = AuthorityStatus.none,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final double lat;
  final double lon;
  final String imageUrl;
  final DisasterCategory category;
  final int severityScore;
  final double llmConfidence;
  final VerificationStatus verificationStatus;
  final String? rejectionReason;
  final String? description;
  final AuthorityStatus authorityStatus;
  final DateTime createdAt;

  factory DisasterReport.fromJson(Map<String, dynamic> json) {
    return DisasterReport(
      id: json['id'] as String,
      userId: json['userId'] as String? ?? '',
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      imageUrl: json['imageUrl'] as String,
      category: _parseCategory(json['category'] as String?),
      severityScore: json['severityScore'] as int? ?? 3,
      llmConfidence: (json['llmConfidence'] as num?)?.toDouble() ?? 0,
      verificationStatus: _parseVerification(json['verificationStatus'] as String?),
      rejectionReason: json['rejectionReason'] as String?,
      description: json['description'] as String?,
      authorityStatus: _parseAuthority(json['authorityStatus'] as String?),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String get categoryLabel => switch (category) {
    DisasterCategory.fire => 'Fire',
    DisasterCategory.flood => 'Flood',
    DisasterCategory.accident => 'Accident',
    DisasterCategory.infrastructure => 'Infrastructure',
    DisasterCategory.medical => 'Medical',
    DisasterCategory.other => 'Other',
  };

  String get severityLabel => switch (severityScore) {
    1 => 'Minor',
    2 => 'Moderate',
    3 => 'Significant',
    4 => 'Severe',
    5 => 'Critical',
    _ => 'Unknown',
  };

  String get statusLabel => switch (verificationStatus) {
    VerificationStatus.verified => 'Verified',
    VerificationStatus.rejected => 'Rejected',
    VerificationStatus.flagged => 'Flagged',
    VerificationStatus.pending => 'Pending',
  };

  String get authorityLabel => switch (authorityStatus) {
    AuthorityStatus.none => 'None',
    AuthorityStatus.dispatched => 'Dispatched',
    AuthorityStatus.investigating => 'Investigating',
    AuthorityStatus.resolved => 'Resolved',
  };

  static DisasterCategory _parseCategory(String? v) => switch (v) {
    'fire' => DisasterCategory.fire,
    'flood' => DisasterCategory.flood,
    'accident' => DisasterCategory.accident,
    'infrastructure' => DisasterCategory.infrastructure,
    'medical' => DisasterCategory.medical,
    _ => DisasterCategory.other,
  };

  static VerificationStatus _parseVerification(String? v) => switch (v) {
    'verified' => VerificationStatus.verified,
    'rejected' => VerificationStatus.rejected,
    'flagged' => VerificationStatus.flagged,
    _ => VerificationStatus.pending,
  };

  static AuthorityStatus _parseAuthority(String? v) => switch (v) {
    'dispatched' => AuthorityStatus.dispatched,
    'investigating' => AuthorityStatus.investigating,
    'resolved' => AuthorityStatus.resolved,
    _ => AuthorityStatus.none,
  };
}

/// Aggregated disaster stats from GET /disaster/stats.
class DisasterStats {
  const DisasterStats({
    required this.totalReports,
    required this.verified,
    required this.pending,
    required this.rejected,
    required this.flagged,
  });

  final int totalReports;
  final int verified;
  final int pending;
  final int rejected;
  final int flagged;

  factory DisasterStats.fromJson(Map<String, dynamic> json) {
    return DisasterStats(
      totalReports: json['totalReports'] as int? ?? 0,
      verified: json['verified'] as int? ?? 0,
      pending: json['pending'] as int? ?? 0,
      rejected: json['rejected'] as int? ?? 0,
      flagged: json['flagged'] as int? ?? 0,
    );
  }
}
