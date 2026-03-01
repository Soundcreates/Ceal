/* ------------------------------------------------------------------ */
/*  API client for the CEAL Admin backend                         */
/* ------------------------------------------------------------------ */

import type {
  DashboardStats,
  EventDetail,
  PaginatedEvents,
  PaginatedUsers,
  PaginatedDisasterReports,
  DisasterReportDetail,
  DisasterReport,
  SosEvent,
  SosStatus,
  UserDetail,
  VerificationStatus,
} from './types';

const BASE = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000/v1';

async function parseJsonBody<T>(res: Response): Promise<T> {
  const contentType = res.headers.get('content-type')?.toLowerCase() ?? '';
  if (contentType.includes('application/json')) {
    return res.json() as Promise<T>;
  }

  const text = await res.text();
  const trimmed = text.trim();

  if (trimmed.length === 0) {
    throw new Error('Empty response from server');
  }

  try {
    return JSON.parse(trimmed) as T;
  } catch {
    const looksLikeHtml = trimmed.startsWith('<!doctype') || trimmed.startsWith('<html') || trimmed.startsWith('<');
    if (looksLikeHtml) {
      throw new Error('Backend returned HTML instead of JSON. Check API base URL / rewrites.');
    }
    throw new Error('Backend returned invalid JSON response.');
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    headers: { 'Content-Type': 'application/json' },
    ...init,
  });
  if (!res.ok) {
    const body = await parseJsonBody<unknown>(res).catch(() => null);
    const errorMessage =
      body &&
      typeof body === 'object' &&
      'error' in body &&
      typeof body.error === 'string'
        ? body.error
        : `Request failed: ${res.status}`;
    throw new Error(errorMessage);
  }
  return parseJsonBody<T>(res);
}

/* ---------- Dashboard ---------- */

export const fetchStats = (): Promise<DashboardStats> =>
  request('/admin/stats');

/* ---------- Events ---------- */

export const fetchEvents = (
  page = 1,
  limit = 50,
  status?: SosStatus,
): Promise<PaginatedEvents> => {
  const params = new URLSearchParams({ page: String(page), limit: String(limit) });
  if (status) params.set('status', status);
  return request(`/admin/events?${params}`);
};

export const fetchEvent = (id: string): Promise<EventDetail> =>
  request(`/admin/events/${encodeURIComponent(id)}`);

export const updateEventStatus = (
  id: string,
  status: SosStatus,
): Promise<SosEvent> =>
  request(`/admin/events/${encodeURIComponent(id)}/status`, {
    method: 'PATCH',
    body: JSON.stringify({ status }),
  });

/* ---------- Users ---------- */

export const fetchUsers = (page = 1, limit = 50): Promise<PaginatedUsers> =>
  request(`/admin/users?page=${page}&limit=${limit}`);

export const fetchUser = (id: string): Promise<UserDetail> =>
  request(`/admin/users/${encodeURIComponent(id)}`);

/* ---------- Disaster Reports ---------- */

export const fetchDisasterReports = (
  page = 1,
  limit = 50,
  status?: VerificationStatus,
  category?: string,
): Promise<PaginatedDisasterReports> => {
  const params = new URLSearchParams({ page: String(page), limit: String(limit) });
  if (status) params.set('status', status);
  if (category) params.set('category', category);
  return request(`/admin/disaster-reports?${params}`);
};

export const fetchDisasterReport = (id: string): Promise<DisasterReportDetail> =>
  request(`/admin/disaster-reports/${encodeURIComponent(id)}`);

export const updateDisasterReportStatus = (
  id: string,
  authority_status: string,
): Promise<DisasterReport> =>
  request(`/admin/disaster-reports/${encodeURIComponent(id)}/status`, {
    method: 'PATCH',
    body: JSON.stringify({ authority_status }),
  });
