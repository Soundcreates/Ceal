import { useParams, useNavigate, Link } from 'react-router-dom';
import { useCallback } from 'react';
import { fetchUser } from '../api/client';
import { usePolling } from '../hooks/usePolling';
import type { UserDetail as UserDetailType } from '../api/types';

function Badge({ status }: { status: string }) {
  return <span className={`nb-badge nb-badge--${status}`}>{status}</span>;
}

function Field({ label, value, mono }: { label: string; value: React.ReactNode; mono?: boolean }) {
  return (
    <div className="detail-field">
      <div className="detail-field__label">{label}</div>
      <div className={`detail-field__value${mono ? ' detail-field__value--mono' : ''}`}>
        {value ?? '—'}
      </div>
    </div>
  );
}

function StatusBadge({ status }: { status: string }) {
  return <span className={`nb-badge nb-badge--${status}`}>{status}</span>;
}

function formatTime(ts: number) {
  return new Date(ts * 1000).toLocaleString('en-IN', {
    day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit',
  });
}

export default function UserDetail() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();

  const fetcher = useCallback(() => fetchUser(id!), [id]);
  const { data, loading, error } = usePolling<UserDetailType>(fetcher, 0, [id]);

  if (loading && !data) return <div className="loading-state">Loading user…</div>;
  if (error) return <div className="loading-state" style={{ color: 'var(--nb-error)' }}>Error: {error}</div>;
  if (!data) return <div className="empty-state">User not found</div>;

  const { user, contacts, medical, events } = data;

  return (
    <>
      {/* Header */}
      <div className="page-header">
        <div style={{ display: 'flex', alignItems: 'center', gap: 16, flexWrap: 'wrap' }}>
          <button className="nb-btn nb-btn--ghost nb-btn--sm" onClick={() => navigate('/admin/users')}>← Back</button>
          <h2>{user.name ?? 'Unnamed User'}</h2>
          <Badge status={user.role} />
          <Badge status={user.kycStatus} />
        </div>
      </div>

      {/* Info grid */}
      <div className="detail-grid" style={{ marginBottom: 24 }}>
        <div className="nb-card nb-card--sm">
          <h3 className="section-heading" style={{ marginTop: 0 }}>Profile</h3>
          <Field label="User ID" value={user.id} mono />
          <Field label="Phone" value={user.phone} mono />
          <Field
            label="BLE UID"
            value={typeof user.bleUid === 'string' ? user.bleUid : '—'}
            mono
          />
          <Field
            label="Registered"
            value={new Date(user.createdAt).toLocaleString('en-IN', {
              weekday: 'short', day: '2-digit', month: 'short', year: 'numeric',
              hour: '2-digit', minute: '2-digit',
            })}
          />
          {user.aadhaarName && <Field label="Aadhaar Name" value={user.aadhaarName} />}
          {user.aadhaarDob && <Field label="Aadhaar DOB" value={user.aadhaarDob} />}
          {user.aadhaarGender && <Field label="Gender" value={user.aadhaarGender} />}
        </div>

        <div className="nb-card nb-card--sm">
          {/* Medical */}
          <h3 className="section-heading" style={{ marginTop: 0 }}>Medical Profile</h3>
          {medical ? (
            <>
              <Field label="Blood Group" value={medical.bloodGroup ?? '—'} />
              <Field
                label="Allergies"
                value={medical.allergies
                  ? Array.isArray(medical.allergies)
                    ? medical.allergies.join(', ')
                    : String(medical.allergies)
                  : 'None reported'}
              />
              <Field
                label="Conditions"
                value={medical.conditions
                  ? Array.isArray(medical.conditions)
                    ? medical.conditions.join(', ')
                    : String(medical.conditions)
                  : 'None reported'}
              />
            </>
          ) : (
            <p style={{ opacity: 0.4, fontWeight: 600 }}>No medical profile on file</p>
          )}

          {/* Emergency contacts */}
          <h3 className="section-heading">Emergency Contacts</h3>
          {contacts.length > 0 ? (
            contacts.map((c) => (
              <div key={c.id} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10, borderBottom: '2px solid var(--nb-ink)', paddingBottom: 8 }}>
                <div>
                  <div style={{ fontWeight: 700 }}>{c.name}</div>
                  <div className="mono" style={{ fontSize: '0.82rem', opacity: 0.7 }}>Priority #{c.priority}</div>
                </div>
                <span className="mono" style={{ fontWeight: 600 }}>{c.phone}</span>
              </div>
            ))
          ) : (
            <p style={{ opacity: 0.4, fontWeight: 600 }}>No emergency contacts</p>
          )}
        </div>
      </div>

      {/* User's SOS events */}
      <h3 className="section-heading">SOS Event History</h3>
      {events.length > 0 ? (
        <div className="nb-table-wrap">
          <table className="nb-table">
            <thead>
              <tr>
                <th>Event ID</th>
                <th>Type</th>
                <th>Status</th>
                <th>Hops</th>
                <th>RSSI</th>
                <th>Time</th>
              </tr>
            </thead>
            <tbody>
              {events.map((ev) => (
                <tr key={ev.id}>
                  <td>
                    <Link to={`/admin/events/${ev.id}`} className="mono" style={{ fontWeight: 700 }}>
                      {ev.id.slice(0, 16)}…
                    </Link>
                  </td>
                  <td>{ev.sosType}</td>
                  <td><StatusBadge status={ev.status} /></td>
                  <td style={{ textAlign: 'center' }}>{ev.relayHops}</td>
                  <td className="mono">{ev.rssi ?? '—'}</td>
                  <td className="mono">{formatTime(ev.timestamp)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : (
        <div className="nb-card nb-card--sm" style={{ opacity: 0.4 }}>
          <p style={{ fontWeight: 600, textAlign: 'center' }}>No SOS events for this user</p>
        </div>
      )}
    </>
  );
}
