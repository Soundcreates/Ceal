import { useState, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { fetchDisasterReports } from '../api/client';
import { usePolling } from '../hooks/usePolling';
import type { PaginatedDisasterReports, VerificationStatus } from '../api/types';

const VERIFICATION_OPTIONS: (VerificationStatus | '')[] = ['', 'pending', 'verified', 'rejected', 'flagged'];
const CATEGORY_OPTIONS = ['', 'fire', 'flood', 'accident', 'infrastructure', 'medical', 'other'];

function VerificationBadge({ status }: { status: string }) {
  return <span className={`nb-badge nb-badge--${status}`}>{status}</span>;
}

function AuthorityBadge({ status }: { status: string }) {
  return <span className={`nb-badge nb-badge--authority-${status}`}>{status}</span>;
}

function SeverityBar({ score }: { score: number }) {
  const color = score >= 4 ? 'var(--nb-error)' : score >= 3 ? 'var(--nb-warn)' : 'var(--nb-ok)';
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
      <div style={{
        width: 60, height: 8,
        border: '2px solid var(--nb-ink)',
        background: `linear-gradient(to right, ${color} ${score * 20}%, transparent ${score * 20}%)`,
      }} />
      <span style={{ fontFamily: 'var(--font-mono)', fontSize: '0.75rem', fontWeight: 700 }}>{score}/5</span>
    </div>
  );
}

function formatTime(ts: string) {
  return new Date(ts).toLocaleString('en-IN', {
    day: '2-digit', month: 'short', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  });
}

export default function DisasterReports() {
  const [page, setPage] = useState(1);
  const [statusFilter, setStatusFilter] = useState<VerificationStatus | ''>('');
  const [categoryFilter, setCategoryFilter] = useState('');

  const fetcher = useCallback(
    () => fetchDisasterReports(page, 50, statusFilter || undefined, categoryFilter || undefined),
    [page, statusFilter, categoryFilter],
  );

  const { data, loading, error, refresh } = usePolling<PaginatedDisasterReports>(
    fetcher,
    10000,
    [page, statusFilter, categoryFilter],
  );

  return (
    <>
      <div className="page-header">
        <h2>Disaster Reports</h2>
        <button className="nb-btn nb-btn--sm" onClick={refresh}>↻ Refresh</button>
      </div>

      {/* Filters */}
      <div className="filters-bar">
        <select
          className="nb-select"
          value={statusFilter}
          onChange={(e) => { setStatusFilter(e.target.value as VerificationStatus | ''); setPage(1); }}
        >
          <option value="">All Verification</option>
          {VERIFICATION_OPTIONS.filter(Boolean).map((s) => (
            <option key={s} value={s}>{String(s).toUpperCase()}</option>
          ))}
        </select>

        <select
          className="nb-select"
          value={categoryFilter}
          onChange={(e) => { setCategoryFilter(e.target.value); setPage(1); }}
        >
          <option value="">All Categories</option>
          {CATEGORY_OPTIONS.filter(Boolean).map((c) => (
            <option key={c} value={c}>{String(c).charAt(0).toUpperCase() + String(c).slice(1)}</option>
          ))}
        </select>

        {data && (
          <span style={{ fontFamily: 'var(--font-mono)', fontSize: '0.78rem', fontWeight: 700, opacity: 0.5 }}>
            {data.total} report{data.total !== 1 ? 's' : ''}
          </span>
        )}
      </div>

      {/* Table */}
      {loading && !data ? (
        <div className="loading-state">Loading reports…</div>
      ) : error ? (
        <div className="loading-state" style={{ color: 'var(--nb-error)' }}>Error: {error}</div>
      ) : !data || data.reports.length === 0 ? (
        <div className="empty-state">No disaster reports found</div>
      ) : (
        <>
          <div className="nb-table-wrap">
            <table className="nb-table">
              <thead>
                <tr>
                  <th>ID</th>
                  <th>Image</th>
                  <th>Category</th>
                  <th>Severity</th>
                  <th>Verification</th>
                  <th>Authority</th>
                  <th>Reporter</th>
                  <th>Location</th>
                  <th>Time</th>
                </tr>
              </thead>
              <tbody>
                {data.reports.map((r) => (
                  <tr key={r.id}>
                    <td>
                      <Link to={`/admin/disaster-reports/${r.id}`} className="mono" style={{ fontWeight: 700 }}>
                        {r.id.slice(0, 8)}…
                      </Link>
                    </td>
                    <td>
                      <img
                        src={r.imageUrl}
                        alt="report"
                        style={{
                          width: 48, height: 48,
                          objectFit: 'cover',
                          border: '2px solid var(--nb-ink)',
                        }}
                      />
                    </td>
                    <td>
                      <span className={`nb-badge nb-badge--cat-${r.category}`}>{r.category}</span>
                    </td>
                    <td><SeverityBar score={r.severityScore} /></td>
                    <td><VerificationBadge status={r.verificationStatus} /></td>
                    <td><AuthorityBadge status={r.authorityStatus} /></td>
                    <td>{r.reporterName ?? r.userId.slice(0, 8) + '…'}</td>
                    <td className="mono" style={{ fontSize: '0.78rem' }}>
                      {r.lat.toFixed(4)}, {r.lon.toFixed(4)}
                    </td>
                    <td className="mono">{formatTime(r.createdAt)}</td>
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
