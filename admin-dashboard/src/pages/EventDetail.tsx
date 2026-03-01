import { useParams, Link, useNavigate } from 'react-router-dom';
import { useCallback, useState } from 'react';
import { fetchEvent, updateEventStatus } from '../api/client';
import { usePolling } from '../hooks/usePolling';
import type { EventDetail as EventDetailType, SosStatus } from '../api/types';

function StatusBadge({ status }: { status: string }) {
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

function formatTs(ts: number) {
  return new Date(ts * 1000).toLocaleString('en-IN', {
    weekday: 'short', day: '2-digit', month: 'short', year: 'numeric',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  });
}

const STATUS_TRANSITIONS: Record<string, SosStatus[]> = {
  active:       ['acknowledged', 'resolved', 'cancelled'],
  relayed:      ['acknowledged', 'resolved', 'cancelled'],
  acknowledged: ['resolved', 'cancelled'],
  resolved:     [],
  cancelled:    [],
};

export default function EventDetail() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [updating, setUpdating] = useState(false);

  const fetcher = useCallback(() => fetchEvent(id!), [id]);
  const { data: event, loading, error, refresh } = usePolling<EventDetailType>(fetcher, 6000, [id]);

  const handleStatusChange = async (newStatus: SosStatus) => {
    if (!event || updating) return;
    setUpdating(true);
    try {
      await updateEventStatus(event.id, newStatus);
      refresh();
    } catch (err) {
      alert(`Failed: ${(err as Error).message}`);
    } finally {
      setUpdating(false);
    }
  };

  if (loading && !event) return <div className="loading-state">Loading event…</div>;
  if (error) return <div className="loading-state" style={{ color: 'var(--nb-error)' }}>Error: {error}</div>;
  if (!event) return <div className="empty-state">Event not found</div>;

  const transitions = STATUS_TRANSITIONS[event.status] ?? [];
  const vp = event.victimProfile;

  return (
    <>
      {/* Header */}
      <div className="page-header">
        <div style={{ display: 'flex', alignItems: 'center', gap: 16, flexWrap: 'wrap' }}>
          <button className="nb-btn nb-btn--ghost nb-btn--sm" onClick={() => navigate('/admin/events')}>← Back</button>
          <h2>Event Detail</h2>
          <StatusBadge status={event.status} />
        </div>
        <button className="nb-btn nb-btn--sm" onClick={refresh}>↻ Refresh</button>
      </div>

      {/* Actions */}
      {transitions.length > 0 && (
        <div style={{ display: 'flex', gap: 10, marginBottom: 24, flexWrap: 'wrap' }}>
          {transitions.includes('acknowledged') && (
            <button
              className="nb-btn nb-btn--primary nb-btn--sm"
              disabled={updating}
              onClick={() => handleStatusChange('acknowledged')}
            >
              ✓ Acknowledge
            </button>
          )}
          {transitions.includes('resolved') && (
            <button
              className="nb-btn nb-btn--ok nb-btn--sm"
              disabled={updating}
              onClick={() => handleStatusChange('resolved')}
            >
              ✓ Resolve
            </button>
          )}
          {transitions.includes('cancelled') && (
            <button
              className="nb-btn nb-btn--error nb-btn--sm"
              disabled={updating}
              onClick={() => handleStatusChange('cancelled')}
            >
              ✕ Cancel
            </button>
          )}
        </div>
      )}

      {/* Event info */}
      <div className="detail-grid" style={{ marginBottom: 24 }}>
        <div className="nb-card nb-card--sm">
          <h3 className="section-heading" style={{ marginTop: 0 }}>Event Information</h3>
          <Field label="Event ID" value={event.id} mono />
          <Field label="SOS Type" value={event.sosType} />
          <Field label="Flags" value={`0x${(event.flags ?? 0).toString(16).toUpperCase().padStart(2, '0')}`} mono />
          <Field label="Sequence" value={event.sequence} mono />
          <Field label="Relay Hops" value={event.relayHops} />
          <Field label="RSSI" value={event.rssi != null ? `${event.rssi} dBm` : '—'} mono />
          <Field label="Timestamp" value={formatTs(event.timestamp)} />
          {event.message && <Field label="Message" value={event.message} />}
        </div>

        <div className="nb-card nb-card--sm">
          <h3 className="section-heading" style={{ marginTop: 0 }}>Transmitter</h3>
          <Field label="BLE UID" value={event.bleUid} mono />
          <Field
            label="Receiver Location"
            value={
              event.receiverLat != null && event.receiverLon != null
                ? `${event.receiverLat.toFixed(6)}, ${event.receiverLon.toFixed(6)}`
                : '—'
            }
            mono
          />
          {event.receiverLat != null && event.receiverLon != null && (
            <div style={{ marginTop: 8 }}>
              <a
                href={`https://www.google.com/maps?q=${event.receiverLat},${event.receiverLon}`}
                target="_blank"
                rel="noopener noreferrer"
                className="nb-btn nb-btn--sm"
                style={{ textDecoration: 'none' }}
              >
                ⊕ Open in Maps
              </a>
            </div>
          )}
        </div>
      </div>

      {/* Victim profile */}
      {vp && (
        <>
          <h3 className="section-heading">Victim Profile</h3>
          <div className="detail-grid" style={{ marginBottom: 24 }}>
            <div className="nb-card nb-card--sm">
              <Field label="Name" value={vp.user.name ?? 'Unknown'} />
              <Field label="Phone" value={vp.user.phone} mono />
              <Field label="User ID" value={<Link to={`/admin/users/${vp.user.id}`}>{vp.user.id.slice(0, 12)}…</Link>} mono />
              <Field label="Role" value={<span className={`nb-badge nb-badge--${vp.user.role}`}>{vp.user.role}</span>} />
              <Field label="KYC" value={<span className={`nb-badge nb-badge--${vp.user.kycStatus}`}>{vp.user.kycStatus}</span>} />
            </div>

            <div className="nb-card nb-card--sm">
              {/* Medical */}
              {vp.medical ? (
                <>
                  <Field label="Blood Group" value={vp.medical.bloodGroup ?? '—'} />
                  <Field
                    label="Allergies"
                    value={vp.medical.allergies
                      ? Array.isArray(vp.medical.allergies)
                        ? vp.medical.allergies.join(', ')
                        : String(vp.medical.allergies)
                      : 'None'}
                  />
                  <Field
                    label="Conditions"
                    value={vp.medical.conditions
                      ? Array.isArray(vp.medical.conditions)
                        ? vp.medical.conditions.join(', ')
                        : String(vp.medical.conditions)
                      : 'None'}
                  />
                </>
              ) : (
                <p style={{ opacity: 0.4, fontWeight: 600 }}>No medical profile on file</p>
              )}

              {/* Contacts */}
              {vp.contacts.length > 0 && (
                <>
                  <h4 style={{ marginTop: 18, marginBottom: 8, fontSize: '0.8rem', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.08em' }}>
                    Emergency Contacts
                  </h4>
                  {vp.contacts.map((c) => (
                    <div key={c.id} style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 6, fontSize: '0.9rem' }}>
                      <span>{c.name}</span>
                      <span className="mono">{c.phone}</span>
                    </div>
                  ))}
                </>
              )}
            </div>
          </div>
        </>
      )}

      {!vp && (
        <div className="nb-card nb-card--sm" style={{ marginTop: 16, opacity: 0.5 }}>
          <p style={{ fontWeight: 600 }}>No victim profile linked to this event</p>
        </div>
      )}
    </>
  );
}
