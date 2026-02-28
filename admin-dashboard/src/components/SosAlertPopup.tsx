import { useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import type { EventDetail } from '../api/types';

/* ------------------------------------------------------------------ */
/*  Helpers                                                            */
/* ------------------------------------------------------------------ */

function formatTs(ts: number) {
  return new Date(ts * 1000).toLocaleString('en-IN', {
    weekday: 'short', day: '2-digit', month: 'short', year: 'numeric',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  });
}

function statusLabel(s: string) {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

/* ------------------------------------------------------------------ */
/*  Single alert card inside the popup                                 */
/* ------------------------------------------------------------------ */

function AlertCard({
  event,
  onDismiss,
  onNavigate,
}: {
  event: EventDetail;
  onDismiss: () => void;
  onNavigate: (path: string) => void;
}) {
  const vp = event.victimProfile;
  const hasLocation = event.receiverLat != null && event.receiverLon != null;
  const mapUrl = hasLocation
    ? `https://www.openstreetmap.org/export/embed.html?bbox=${event.receiverLon! - 0.005},${event.receiverLat! - 0.003},${event.receiverLon! + 0.005},${event.receiverLat! + 0.003}&layer=mapnik&marker=${event.receiverLat},${event.receiverLon}`
    : null;

  return (
    <div className="sos-alert-card">
      {/* Header strip */}
      <div className="sos-alert-card__header">
        <div className="sos-alert-card__siren">SOS</div>
        <div className="sos-alert-card__title">
          <span className="sos-alert-card__type">{event.sosType ?? 'SOS'}</span>
          <span className={`nb-badge nb-badge--${event.status}`}>{statusLabel(event.status)}</span>
        </div>
        <button className="sos-alert-card__close" onClick={onDismiss} title="Dismiss">✕</button>
      </div>

      <div className="sos-alert-card__body">
        {/* Left: info */}
        <div className="sos-alert-card__info">
          {/* Victim */}
          {vp ? (
            <div className="sos-alert-card__section">
              <div className="sos-alert-card__section-label">Victim</div>
              <div className="sos-alert-card__field">
                <strong>{vp.user.name ?? 'Unknown'}</strong>
              </div>
              <div className="sos-alert-card__field mono">{vp.user.phone}</div>
              <div className="sos-alert-card__field">
                <span className={`nb-badge nb-badge--${vp.user.role}`}>{vp.user.role}</span>
                {' '}
                <span className={`nb-badge nb-badge--${vp.user.kycStatus}`}>{vp.user.kycStatus}</span>
              </div>
            </div>
          ) : (
            <div className="sos-alert-card__section">
              <div className="sos-alert-card__section-label">Transmitter</div>
              <div className="sos-alert-card__field mono">{event.bleUid}</div>
            </div>
          )}

          {/* Medical */}
          {vp?.medical && (
            <div className="sos-alert-card__section">
              <div className="sos-alert-card__section-label">Medical</div>
              {vp.medical.bloodGroup && (
                <div className="sos-alert-card__field">
                  <span className="sos-alert-card__med-tag">{vp.medical.bloodGroup}</span>
                </div>
              )}
              {vp.medical.allergies && vp.medical.allergies.length > 0 && (
                <div className="sos-alert-card__field">
                  Allergies: {Array.isArray(vp.medical.allergies) ? vp.medical.allergies.join(', ') : vp.medical.allergies}
                </div>
              )}
              {vp.medical.conditions && vp.medical.conditions.length > 0 && (
                <div className="sos-alert-card__field">
                  Conditions: {Array.isArray(vp.medical.conditions) ? vp.medical.conditions.join(', ') : vp.medical.conditions}
                </div>
              )}
            </div>
          )}

          {/* Emergency Contacts */}
          {vp && vp.contacts.length > 0 && (
            <div className="sos-alert-card__section">
              <div className="sos-alert-card__section-label">Emergency Contacts</div>
              {vp.contacts.map((c) => (
                <div key={c.id} className="sos-alert-card__contact">
                  <span>{c.name}</span>
                  <span className="mono">{c.phone}</span>
                </div>
              ))}
            </div>
          )}

          {/* Event meta */}
          <div className="sos-alert-card__section">
            <div className="sos-alert-card__section-label">Event Details</div>
            <div className="sos-alert-card__field mono" style={{ fontSize: '0.72rem' }}>
              ID: {event.id}
            </div>
            <div className="sos-alert-card__field">
              Time: {formatTs(event.timestamp)}
            </div>
            <div className="sos-alert-card__field">
              Relay hops: {event.relayHops} &nbsp;|&nbsp; RSSI: {event.rssi ?? '—'} dBm
            </div>
            {event.message && (
              <div className="sos-alert-card__field">
                Msg: {event.message}
              </div>
            )}
            {hasLocation && (
              <div className="sos-alert-card__field mono" style={{ fontSize: '0.75rem' }}>
                {event.receiverLat!.toFixed(6)}, {event.receiverLon!.toFixed(6)}
              </div>
            )}
          </div>
        </div>

        {/* Right: map */}
        <div className="sos-alert-card__map-col">
          {mapUrl ? (
            <iframe
              className="sos-alert-card__map"
              src={mapUrl}
              title="SOS Location"
              loading="eager"
            />
          ) : (
            <div className="sos-alert-card__no-map">
              No location data
            </div>
          )}
          {hasLocation && (
            <a
              href={`https://www.google.com/maps?q=${event.receiverLat},${event.receiverLon}`}
              target="_blank"
              rel="noopener noreferrer"
              className="nb-btn nb-btn--sm"
              style={{ marginTop: 8, textDecoration: 'none', width: '100%', justifyContent: 'center' }}
            >
              ⊕ Open in Google Maps
            </a>
          )}
        </div>
      </div>

      {/* Footer actions */}
      <div className="sos-alert-card__actions">
        <button
          className="nb-btn nb-btn--primary nb-btn--sm"
          onClick={() => onNavigate(`/admin/events/${encodeURIComponent(event.id)}`)}
        >
          View Full Detail →
        </button>
        <button className="nb-btn nb-btn--ghost nb-btn--sm" onClick={onDismiss}>
          Dismiss
        </button>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Main popup overlay                                                 */
/* ------------------------------------------------------------------ */

export default function SosAlertPopup({
  alerts,
  onDismiss,
  onDismissAll,
}: {
  alerts: EventDetail[];
  onDismiss: (id: string) => void;
  onDismissAll: () => void;
}) {
  const navigate = useNavigate();

  // Play an alert sound when a new alert comes in
  useEffect(() => {
    if (alerts.length === 0) return;
    try {
      // Use Web Audio API for a short alarm beep
      const ctx = new AudioContext();
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.type = 'square';
      osc.frequency.setValueAtTime(880, ctx.currentTime);
      osc.frequency.setValueAtTime(660, ctx.currentTime + 0.15);
      osc.frequency.setValueAtTime(880, ctx.currentTime + 0.3);
      gain.gain.setValueAtTime(0.3, ctx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.01, ctx.currentTime + 0.5);
      osc.start(ctx.currentTime);
      osc.stop(ctx.currentTime + 0.5);
    } catch {
      /* audio not available */
    }
  }, [alerts.length]);

  if (alerts.length === 0) return null;

  const handleNavigate = (path: string) => {
    onDismissAll();
    navigate(path);
  };

  return (
    <div className="sos-overlay">
      <div className="sos-overlay__backdrop" onClick={onDismissAll} />
      <div className="sos-overlay__container">
        {/* Header */}
        <div className="sos-overlay__header">
          <div className="sos-overlay__header-left">
            <span className="live-dot" />
            <h2>SOS ALERT{alerts.length > 1 ? 'S' : ''}</h2>
            {alerts.length > 1 && (
              <span className="nb-badge nb-badge--active">{alerts.length}</span>
            )}
          </div>
          {alerts.length > 1 && (
            <button className="nb-btn nb-btn--ghost nb-btn--sm" onClick={onDismissAll}>
              Dismiss All
            </button>
          )}
        </div>

        {/* Scrollable alert list */}
        <div className="sos-overlay__list">
          {alerts.map((alert) => (
            <AlertCard
              key={alert.id}
              event={alert}
              onDismiss={() => onDismiss(alert.id)}
              onNavigate={handleNavigate}
            />
          ))}
        </div>
      </div>
    </div>
  );
}
