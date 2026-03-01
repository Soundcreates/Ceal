import { fetchStats } from '../api/client';
import { usePolling } from '../hooks/usePolling';
import type { DashboardStats, SosEvent, DisasterReport } from '../api/types';
import { Link } from 'react-router-dom';

function StatusBadge({ status }: { status: string }) {
  return <span className={`nb-badge nb-badge--${status}`}>{status}</span>;
}

function formatTime(ts: number | string) {
  const d = typeof ts === 'number' ? new Date(ts * 1000) : new Date(ts);
  return d.toLocaleString('en-IN', {
    day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit',
  });
}

function MiniBarChart({ data }: { data: { day: string; count: number }[] }) {
  const max = Math.max(...data.map((d) => d.count), 1);
  return (
    <div>
      <div className="mini-chart">
        {data.map((d) => (
          <div key={d.day} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'stretch' }}>
            <div
              className="mini-chart__bar"
              style={{ height: `${(d.count / max) * 100}%` }}
              title={`${d.day}: ${d.count} events`}
            />
          </div>
        ))}
      </div>
      <div style={{ display: 'flex', gap: 6, marginTop: 6 }}>
        {data.map((d) => (
          <div key={d.day} className="mini-chart__label" style={{ flex: 1 }}>
            {new Date(d.day).toLocaleDateString('en-IN', { weekday: 'short' })}
          </div>
        ))}
      </div>
    </div>
  );
}

function RecentRow({ ev }: { ev: SosEvent }) {
  return (
    <tr>
      <td>
        <Link to={`/admin/events/${ev.id}`} className="mono" style={{ fontWeight: 700 }}>
          {ev.id.slice(0, 12)}…
        </Link>
      </td>
      <td>{ev.sosType}</td>
      <td><StatusBadge status={ev.status} /></td>
      <td className="mono">{ev.bleUid.slice(0, 8)}…</td>
      <td className="mono">{formatTime(ev.timestamp)}</td>
    </tr>
  );
}

function RecentDisasterRow({ r }: { r: DisasterReport }) {
  return (
    <tr>
      <td>
        <Link to={`/admin/disaster-reports/${r.id}`} className="mono" style={{ fontWeight: 700 }}>
          {r.id.slice(0, 12)}…
        </Link>
      </td>
      <td><span className={`nb-badge nb-badge--cat-${r.category}`}>{r.category}</span></td>
      <td>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <div style={{ width: 50, height: 8, background: '#e5e7eb', border: '2px solid var(--nb-ink)' }}>
            <div style={{
              width: `${(r.severityScore / 5) * 100}%`,
              height: '100%',
              background: r.severityScore >= 4 ? 'var(--nb-error)' : r.severityScore >= 3 ? 'var(--nb-warn)' : 'var(--nb-ok)',
            }} />
          </div>
          <span style={{ fontFamily: 'var(--font-mono)', fontSize: '0.75rem', fontWeight: 700 }}>{r.severityScore}/5</span>
        </div>
      </td>
      <td><StatusBadge status={r.verificationStatus} /></td>
      <td><span className={`nb-badge nb-badge--authority-${r.authorityStatus}`}>{r.authorityStatus}</span></td>
      <td className="mono">{formatTime(r.createdAt)}</td>
    </tr>
  );
}

export default function Dashboard() {
  const { data: stats, loading, error } = usePolling<DashboardStats>(
    () => fetchStats(),
    8000,   // auto-refresh every 8 s
  );

  if (loading && !stats) return <div className="loading-state">Loading dashboard…</div>;
  if (error) return <div className="loading-state" style={{ color: 'var(--nb-error)' }}>Error: {error}</div>;
  if (!stats) return null;

  return (
    <>
      {/* ---------------------------------------------------------------- */}
      {/* Header                                                           */}
      {/* ---------------------------------------------------------------- */}
      <div className="page-header">
        <h2>Dashboard</h2>
        <span style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <span className="live-dot" />
          <span style={{ fontFamily: 'var(--font-mono)', fontSize: '0.75rem', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.1em' }}>
            Live
          </span>
        </span>
      </div>

      {/* ---------------------------------------------------------------- */}
      {/* Stat cards                                                       */}
      {/* ---------------------------------------------------------------- */}
      <div className="stat-grid" style={{ marginBottom: 28 }}>
        <div className="nb-card nb-card--sm stat-card">
          <div className="stat-card__label">Active SOS</div>
          <div className={`stat-card__value ${stats.activeEvents > 0 ? 'stat-card__value--error pulse' : ''}`}>
            {stats.activeEvents}
          </div>
        </div>
        <div className="nb-card nb-card--sm stat-card">
          <div className="stat-card__label">Events Today</div>
          <div className="stat-card__value stat-card__value--warn">{stats.eventsToday}</div>
        </div>
        <div className="nb-card nb-card--sm stat-card">
          <div className="stat-card__label">Total Events</div>
          <div className="stat-card__value">{stats.totalEvents}</div>
        </div>
        <div className="nb-card nb-card--sm stat-card">
          <div className="stat-card__label">Registered Users</div>
          <div className="stat-card__value stat-card__value--accent">{stats.totalUsers}</div>
        </div>
      </div>

      {/* ---------------------------------------------------------------- */}
      {/* Disaster report stat cards                                       */}
      {/* ---------------------------------------------------------------- */}
      {stats.disasterReports && (
        <div className="stat-grid" style={{ marginBottom: 28 }}>
          <div className="nb-card nb-card--sm stat-card" style={{ borderColor: 'var(--nb-warn)' }}>
            <div className="stat-card__label">⚠ Disaster Reports</div>
            <div className="stat-card__value">{stats.disasterReports.total}</div>
          </div>
          <div className="nb-card nb-card--sm stat-card">
            <div className="stat-card__label">⚠ Reports Today</div>
            <div className="stat-card__value stat-card__value--warn">{stats.disasterReports.today}</div>
          </div>
          <div className="nb-card nb-card--sm stat-card">
            <div className="stat-card__label">✓ Verified</div>
            <div className="stat-card__value stat-card__value--ok">{stats.disasterReports.verification.verified}</div>
          </div>
          <div className="nb-card nb-card--sm stat-card">
            <div className="stat-card__label">⚑ Flagged / Pending</div>
            <div className="stat-card__value stat-card__value--error">
              {stats.disasterReports.verification.flagged + stats.disasterReports.verification.pending}
            </div>
          </div>
        </div>
      )}

      {/* ---------------------------------------------------------------- */}
      {/* Second row: KYC + Status breakdown + SOS type                    */}
      {/* ---------------------------------------------------------------- */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr 1fr', gap: 20, marginBottom: 28 }}>
        {/* KYC Overview */}
        <div className="nb-card nb-card--sm">
          <div className="stat-card__label" style={{ marginBottom: 14 }}>KYC Status</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between' }}>
              <span>Verified</span>
              <strong style={{ color: 'var(--nb-ok)' }}>{stats.kyc.verified}</strong>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between' }}>
              <span>Pending</span>
              <strong style={{ color: 'var(--nb-warn)' }}>{stats.kyc.pending}</strong>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between' }}>
              <span>Rejected</span>
              <strong style={{ color: 'var(--nb-error)' }}>{stats.kyc.rejected}</strong>
            </div>
          </div>
        </div>

        {/* Status Breakdown */}
        <div className="nb-card nb-card--sm">
          <div className="stat-card__label" style={{ marginBottom: 14 }}>Event Status</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {Object.entries(stats.statusBreakdown).map(([status, count]) => (
              <div key={status} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <StatusBadge status={status} />
                <strong>{count}</strong>
              </div>
            ))}
            {Object.keys(stats.statusBreakdown).length === 0 && (
              <span style={{ opacity: 0.4, fontSize: '0.85rem' }}>No events yet</span>
            )}
          </div>
        </div>

        {/* SOS Type Breakdown */}
        <div className="nb-card nb-card--sm">
          <div className="stat-card__label" style={{ marginBottom: 14 }}>SOS Types</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {Object.entries(stats.typeBreakdown).map(([type, count]) => (
              <div key={type} style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ fontSize: '0.85rem' }}>{type}</span>
                <strong>{count}</strong>
              </div>
            ))}
            {Object.keys(stats.typeBreakdown).length === 0 && (
              <span style={{ opacity: 0.4, fontSize: '0.85rem' }}>No events yet</span>
            )}
          </div>
        </div>

        {/* Disaster Verification Breakdown */}
        {stats.disasterReports && (
          <div className="nb-card nb-card--sm" style={{ borderColor: 'var(--nb-warn)' }}>
            <div className="stat-card__label" style={{ marginBottom: 14 }}>⚠ Disaster Verification</div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <StatusBadge status="verified" />
                <strong>{stats.disasterReports.verification.verified}</strong>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <StatusBadge status="pending" />
                <strong>{stats.disasterReports.verification.pending}</strong>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <StatusBadge status="rejected" />
                <strong>{stats.disasterReports.verification.rejected}</strong>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <span className="nb-badge nb-badge--flagged">flagged</span>
                <strong>{stats.disasterReports.verification.flagged}</strong>
              </div>
            </div>
          </div>
        )}
      </div>

      {/* ---------------------------------------------------------------- */}
      {/* Daily Events chart                                               */}
      {/* ---------------------------------------------------------------- */}
      {stats.dailyEvents.length > 0 && (
        <div style={{ marginBottom: 28 }}>
          <div className="nb-card nb-card--sm">
            <div className="stat-card__label" style={{ marginBottom: 14 }}>Events — Last 7 Days</div>
            <MiniBarChart data={stats.dailyEvents} />
          </div>
        </div>
      )}

      {/* ---------------------------------------------------------------- */}
      {/* Recent activity                                                  */}
      {/* ---------------------------------------------------------------- */}
      <h3 className="section-heading">Recent Activity</h3>
      <div className="nb-table-wrap">
        <table className="nb-table">
          <thead>
            <tr>
              <th>Event ID</th>
              <th>Type</th>
              <th>Status</th>
              <th>BLE UID</th>
              <th>Time</th>
            </tr>
          </thead>
          <tbody>
            {stats.recentEvents.length === 0 ? (
              <tr><td colSpan={5} style={{ textAlign: 'center', opacity: 0.4 }}>No events yet</td></tr>
            ) : (
              stats.recentEvents.map((ev) => <RecentRow key={ev.id} ev={ev} />)
            )}
          </tbody>
        </table>
      </div>

      {/* ---------------------------------------------------------------- */}
      {/* Recent disaster reports                                          */}
      {/* ---------------------------------------------------------------- */}
      {stats.recentDisasterReports && stats.recentDisasterReports.length > 0 && (
        <>
          <h3 className="section-heading">Recent Disaster Reports</h3>
          <div className="nb-table-wrap">
            <table className="nb-table">
              <thead>
                <tr>
                  <th>Report ID</th>
                  <th>Category</th>
                  <th>Severity</th>
                  <th>Verification</th>
                  <th>Authority</th>
                  <th>Time</th>
                </tr>
              </thead>
              <tbody>
                {stats.recentDisasterReports.map((r) => (
                  <RecentDisasterRow key={r.id} r={r} />
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </>
  );
}
