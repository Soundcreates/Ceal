/// Responder profile model.
library;

/// The role of a registered user within the AfterMath network.
enum UserRole {
  /// Regular civilian user.
  civilian,

  /// Verified first-responder (medical, fire, campus security, etc.).
  responder,

  /// System administrator / dispatcher.
  admin,
}

/// An emergency contact entry.
class EmergencyContact {
  const EmergencyContact({required this.name, required this.phone});

  final String name;
  final String phone;

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone};

  factory EmergencyContact.fromJson(Map<String, dynamic> json) =>
      EmergencyContact(
        name: json['name'] as String,
        phone: json['phone'] as String,
      );

  @override
  String toString() => 'EmergencyContact($name, $phone)';
}

/// Represents a user registered in the AfterMath system.
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.displayName,
    required this.role,
    this.emergencyContacts = const [],
    this.phoneNumber,
  });

  final String uid;
  final String displayName;
  final UserRole role;
  final List<EmergencyContact> emergencyContacts;
  final String? phoneNumber;

  bool get isResponder => role == UserRole.responder || role == UserRole.admin;

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'displayName': displayName,
        'role': role.name,
        'emergencyContacts': emergencyContacts.map((c) => c.toJson()).toList(),
        if (phoneNumber != null) 'phoneNumber': phoneNumber,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        uid: json['uid'] as String,
        displayName: json['displayName'] as String,
        role: UserRole.values.byName(json['role'] as String),
        emergencyContacts: (json['emergencyContacts'] as List?)
                ?.map((e) =>
                    EmergencyContact.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        phoneNumber: json['phoneNumber'] as String?,
      );

  @override
  String toString() => 'UserProfile($uid, $displayName, $role)';
}
