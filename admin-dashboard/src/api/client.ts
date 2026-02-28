/* ------------------------------------------------------------------ */
/*  API client for the CEAL Admin backend                         */
/* ------------------------------------------------------------------ */

import type {
  DashboardStats,
  EventDetail,
  PaginatedEvents,
  PaginatedUsers,
  SosEvent,
  SosStatus,
  UserDetail,
} from './types';

const BASE = import.meta.env.VITE_API_BASE_URL ?? '/v1';

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    headers: { 'Content-Type': 'application/json' },
    ...init,
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.error ?? `Request failed: ${res.status}`);
  }
  return res.json();
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
