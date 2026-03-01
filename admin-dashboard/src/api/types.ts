/* ------------------------------------------------------------------ */
/*  TypeScript types mirroring the CEAL backend models            */
/* ------------------------------------------------------------------ */

export type SosStatus = 'active' | 'relayed' | 'acknowledged' | 'resolved' | 'cancelled';

export interface SosEvent {
  id: string;
  bleUid: string;
  flags: number;
  sequence: number;
  timestamp: number;
  status: SosStatus;
  relayHops: number;
  receiverLat: number | null;
  receiverLon: number | null;
  rssi: number | null;
  userId: string | null;
  message: string | null;
  sosType: string;
  createdAt?: string;
  updatedAt?: string;
}

export interface User {
  id: string;
  name: string | null;
  phone: string;
  bleUid: string;
  role: 'civilian' | 'responder' | 'admin';
  kycStatus: 'pending' | 'verified' | 'rejected' | 'expired';
  createdAt: string;
}

export interface EmergencyContact {
  id: string;
  name: string;
  phone: string;
  priority: number;
}

export interface MedicalProfile {
  bloodGroup: string | null;
  allergies: string | string[] | null;
  conditions: string | string[] | null;
}

export interface VictimProfile {
  user: {
    id: string;
    name: string | null;
    phone: string;
    role: string;
    kycStatus: string;
  };
  contacts: EmergencyContact[];
  medical: MedicalProfile | null;
}

/* ---------- API Response shapes ---------- */

export interface PaginatedEvents {
  events: SosEvent[];
  total: number;
  page: number;
  limit: number;
  pages: number;
}

export interface PaginatedUsers {
  users: User[];
  total: number;
  page: number;
  limit: number;
  pages: number;
}

export interface DashboardStats {
  totalEvents: number;
  totalUsers: number;
  activeEvents: number;
  eventsToday: number;
  kyc: { verified: number; pending: number; rejected: number };
  statusBreakdown: Record<string, number>;
  typeBreakdown: Record<string, number>;
  dailyEvents: { day: string; count: number }[];
  recentEvents: SosEvent[];
}

export interface EventDetail extends SosEvent {
  victimProfile: VictimProfile | null;
}

export interface UserDetail {
  user: User & {
    aadhaarName?: string | null;
    aadhaarDob?: string | null;
    aadhaarGender?: string | null;
    nullifierHash?: string | null;
  };
  contacts: EmergencyContact[];
  medical: MedicalProfile | null;
  events: SosEvent[];
}
/* ---------- Disaster Report types ---------- */

export type DisasterCategory = 'fire' | 'flood' | 'accident' | 'infrastructure' | 'medical' | 'other';
export type VerificationStatus = 'pending' | 'verified' | 'rejected' | 'flagged';
export type AuthorityStatus = 'pending' | 'dispatched' | 'resolved' | 'ignored';

export interface DisasterReport {
  id: string;
  userId: string;
  lat: number;
  lon: number;
  imageUrl: string;
  imageHash: string;
  category: DisasterCategory;
  severityScore: number;
  llmConfidence: number;
  llmRawResponse: Record<string, unknown> | null;
  verificationStatus: VerificationStatus;
  rejectionReason: string | null;
  authorityStatus: AuthorityStatus;
  description: string | null;
  linkedSosId: string | null;
  createdAt: string;
  updatedAt: string;
  reporterName?: string | null;
}

export interface PaginatedDisasterReports {
  reports: DisasterReport[];
  total: number;
  page: number;
  limit: number;
  pages: number;
}

export interface DisasterReportDetail extends DisasterReport {
  reporter: {
    id: string;
    name: string | null;
    phone: string;
    role: string;
    kycStatus: string;
  } | null;
}

export interface DisasterDashboardStats {
  total: number;
  today: number;
  verification: {
    total: number;
    verified: number;
    pending: number;
    rejected: number;
    flagged: number;
  };
}

export interface DashboardStats {
  totalEvents: number;
  totalUsers: number;
  activeEvents: number;
  eventsToday: number;
  kyc: { verified: number; pending: number; rejected: number };
  statusBreakdown: Record<string, number>;
  typeBreakdown: Record<string, number>;
  dailyEvents: { day: string; count: number }[];
  recentEvents: SosEvent[];
  disasterReports: DisasterDashboardStats;
  recentDisasterReports: DisasterReport[];
}