import { useState, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { fetchEvents } from '../api/client';
import { usePolling } from '../hooks/usePolling';
import type { PaginatedEvents, SosStatus } from '../api/types';

const STATUS_OPTIONS: (SosStatus | '')[] = ['', 'active', 'relayed', 'acknowledged', 'resolved', 'cancelled'];

function StatusBadge({ status }: { status: string }) {
  return <span className={`nb-badge nb-badge--${status}`}>{status}</span>;
}

function formatTime(ts: number) {
  return new Date(ts * 1000).toLocaleString('en-IN', {
    day: '2-digit', month: 'short', year: 'numeric',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  });
}

export default function Events() {
  const [page, setPage] = useState(1);
  const [statusFilter, setStatusFilter] = useState<SosStatus | ''>('');

  const fetcher = useCallback(
    () => fetchEvents(page, 50, statusFilter || undefined),
    [page, statusFilter],
  );

  const { data, loading, error, refresh } = usePolling<PaginatedEvents>(
    fetcher,
    10000,
    [page, statusFilter],
  );

  return (
    <>
      <div className="page-header">
        <h2>SOS Events</h2>
        <button className="nb-btn nb-btn--sm" onClick={refresh}>↻ Refresh</button>
      </div>

      {/* Filters */}
      <div className="filters-bar">
        <select
          className="nb-select"
          value={statusFilter}
          onChange={(e) => { setStatusFilter(e.target.value as SosStatus | ''); setPage(1); }}
        >
          <option value="">All Statuses</option>
          {STATUS_OPTIONS.filter(Boolean).map((s) => (
            <option key={s} value={s}>{String(s).toUpperCase()}</option>
          ))}
        </select>
        {data && (
          <span style={{ fontFamily: 'var(--font-mono)', fontSize: '0.78rem', fontWeight: 700, opacity: 0.5 }}>
            {data.total} total event{data.total !== 1 ? 's' : ''}
          </span>
        )}
      </div>

      {/* Table */}
      {loading && !data ? (
        <div className="loading-state">Loading events…</div>
      ) : error ? (
        <div className="loading-state" style={{ color: 'var(--nb-error)' }}>Error: {error}</div>
      ) : !data || data.events.length === 0 ? (
        <div className="empty-state">No events found</div>
      ) : (
        <>
          <div className="nb-table-wrap">
            <table className="nb-table">
              <thead>
                <tr>
                  <th>ID</th>
                  <th>Type</th>
                  <th>Status</th>
                  <th>BLE UID</th>
                  <th>Hops</th>
                  <th>RSSI</th>
                  <th>Location</th>
                  <th>Timestamp</th>
                </tr>
              </thead>
              <tbody>
                {data.events.map((ev) => (
                  <tr key={ev.id}>
                    <td>
                      <Link to={`/admin/events/${ev.id}`} className="mono" style={{ fontWeight: 700 }}>
                        {ev.id.length > 16 ? `${ev.id.slice(0, 16)}…` : ev.id}
                      </Link>
                    </td>
                    <td>{ev.sosType}</td>
                    <td><StatusBadge status={ev.status} /></td>
                    <td className="mono">{ev.bleUid.slice(0, 8)}…</td>
                    <td style={{ textAlign: 'center' }}>{ev.relayHops}</td>
                    <td className="mono">{ev.rssi ?? '—'}</td>
                    <td className="mono">
                      {ev.receiverLat != null && ev.receiverLon != null
                        ? `${ev.receiverLat.toFixed(4)}, ${ev.receiverLon.toFixed(4)}`
                        : '—'}
                    </td>
                    <td className="mono">{formatTime(ev.timestamp)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Pagination */}
          {data.pages > 1 && (
            <div className="pagination">
              <button
                className="nb-btn nb-btn--sm"
                disabled={page <= 1}
                onClick={() => setPage((p) => Math.max(1, p - 1))}
              >
                ← Prev
              </button>
              <span className="pagination__info">
                Page {data.page} of {data.pages}
              </span>
              <button
                className="nb-btn nb-btn--sm"
                disabled={page >= data.pages}
                onClick={() => setPage((p) => p + 1)}
              >
                Next →
              </button>
            </div>
          )}
        </>
      )}
    </>
  );
}
