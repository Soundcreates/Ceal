import { useState, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { fetchUsers } from '../api/client';
import { usePolling } from '../hooks/usePolling';
import type { PaginatedUsers } from '../api/types';

function Badge({ status, type }: { status: string; type?: string }) {
  const cls = type ?? status;
  return <span className={`nb-badge nb-badge--${cls}`}>{status}</span>;
}

export default function Users() {
  const [page, setPage] = useState(1);

  const fetcher = useCallback(() => fetchUsers(page, 50), [page]);
  const { data, loading, error, refresh } = usePolling<PaginatedUsers>(fetcher, 15000, [page]);

  return (
    <>
      <div className="page-header">
        <h2>Users</h2>
        <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
          {data && (
            <span style={{ fontFamily: 'var(--font-mono)', fontSize: '0.78rem', fontWeight: 700, opacity: 0.5 }}>
              {data.total} user{data.total !== 1 ? 's' : ''}
            </span>
          )}
          <button className="nb-btn nb-btn--sm" onClick={refresh}>↻ Refresh</button>
        </div>
      </div>

      {loading && !data ? (
        <div className="loading-state">Loading users…</div>
      ) : error ? (
        <div className="loading-state" style={{ color: 'var(--nb-error)' }}>Error: {error}</div>
      ) : !data || data.users.length === 0 ? (
        <div className="empty-state">No users found</div>
      ) : (
        <>
          <div className="nb-table-wrap">
            <table className="nb-table">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Phone</th>
                  <th>BLE UID</th>
                  <th>Role</th>
                  <th>KYC</th>
                  <th>Registered</th>
                </tr>
              </thead>
              <tbody>
                {data.users.map((u) => (
                  <tr key={u.id}>
                    <td>
                      <Link to={`/admin/users/${u.id}`} style={{ fontWeight: 700 }}>
                        {u.name ?? 'Unnamed'}
                      </Link>
                    </td>
                    <td className="mono">{u.phone}</td>
                    <td className="mono">{u.bleUid ? `${u.bleUid.slice(0, 8)}…` : '—'}</td>
                    <td><Badge status={u.role} /></td>
                    <td><Badge status={u.kycStatus} /></td>
                    <td className="mono">
                      {new Date(u.createdAt).toLocaleDateString('en-IN', {
                        day: '2-digit', month: 'short', year: 'numeric',
                      })}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

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
