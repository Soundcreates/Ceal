import { useParams, useNavigate } from 'react-router-dom';
import { useCallback, useState } from 'react';
import { fetchDisasterReport, updateDisasterReportStatus } from '../api/client';
import { usePolling } from '../hooks/usePolling';
import type { DisasterReportDetail as DetailType, AuthorityStatus } from '../api/types';

function VerificationBadge({ status }: { status: string }) {
  return <span className={`nb-badge nb-badge--${status}`}>{status}</span>;
}

function AuthorityBadge({ status }: { status: string }) {
  return <span className={`nb-badge nb-badge--authority-${status}`}>{status}</span>;
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

function formatTs(ts: string) {
  return new Date(ts).toLocaleString('en-IN', {
    weekday: 'short', day: '2-digit', month: 'short', year: 'numeric',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  });
}

const AUTHORITY_TRANSITIONS: Record<string, AuthorityStatus[]> = {
  pending:    ['dispatched', 'ignored'],
  dispatched: ['resolved', 'ignored'],
  resolved:   [],
  ignored:    ['pending'],
};

export default function DisasterReportDetail() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [updating, setUpdating] = useState(false);

  const fetcher = useCallback(() => fetchDisasterReport(id!), [id]);
  const { data: report, loading, error, refresh } = usePolling<DetailType>(fetcher, 8000, [id]);

  const handleStatusChange = async (newStatus: AuthorityStatus) => {
    if (!report || updating) return;
    setUpdating(true);
    try {
      await updateDisasterReportStatus(report.id, newStatus);
      refresh();
    } catch (err) {
      alert(`Failed: ${(err as Error).message}`);
    } finally {
      setUpdating(false);
    }
  };

  if (loading && !report) return <div className="loading-state">Loading report…</div>;
  if (error) return <div className="loading-state" style={{ color: 'var(--nb-error)' }}>Error: {error}</div>;
  if (!report) return <div className="empty-state">Report not found</div>;

  const transitions = AUTHORITY_TRANSITIONS[report.authorityStatus] ?? [];
  const hasLocation = report.lat != null && report.lon != null;
  const mapUrl = hasLocation
    ? `https://www.openstreetmap.org/export/embed.html?bbox=${report.lon - 0.005},${report.lat - 0.003},${report.lon + 0.005},${report.lat + 0.003}&layer=mapnik&marker=${report.lat},${report.lon}`
    : null;

  const sevColor = report.severityScore >= 4 ? 'var(--nb-error)' : report.severityScore >= 3 ? 'var(--nb-warn)' : 'var(--nb-ok)';

  return (
    <>
      {/* Header */}
      <div className="page-header">
        <div style={{ display: 'flex', alignItems: 'center', gap: 16, flexWrap: 'wrap' }}>
          <button className="nb-btn nb-btn--ghost nb-btn--sm" onClick={() => navigate('/admin/disaster-reports')}>← Back</button>
          <h2>Disaster Report</h2>
          <VerificationBadge status={report.verificationStatus} />
          <AuthorityBadge status={report.authorityStatus} />
        </div>
        <button className="nb-btn nb-btn--sm" onClick={refresh}>↻ Refresh</button>
      </div>

      {/* Authority Actions */}
      {transitions.length > 0 && (
        <div style={{ display: 'flex', gap: 10, marginBottom: 24, flexWrap: 'wrap' }}>
          {transitions.includes('dispatched') && (
            <button
              className="nb-btn nb-btn--primary nb-btn--sm"
              disabled={updating}
              onClick={() => handleStatusChange('dispatched')}
            >
              🚨 Dispatch
            </button>
          )}
          {transitions.includes('resolved') && (
            <button
              className="nb-btn nb-btn--ok nb-btn--sm"
              disabled={updating}
              onClick={() => handleStatusChange('resolved')}
            >
              ✓ Mark Resolved
            </button>
          )}
          {transitions.includes('ignored') && (
            <button
              className="nb-btn nb-btn--error nb-btn--sm"
              disabled={updating}
              onClick={() => handleStatusChange('ignored')}
            >
              ✕ Ignore
            </button>
          )}
          {transitions.includes('pending') && (
            <button
              className="nb-btn nb-btn--warn nb-btn--sm"
              disabled={updating}
              onClick={() => handleStatusChange('pending')}
            >
              ↺ Reopen
            </button>
          )}
        </div>
      )}

      {/* Main content */}
      <div className="detail-grid" style={{ marginBottom: 24 }}>
        {/* Left: Image + Location */}
        <div className="nb-card nb-card--sm">
          <h3 className="section-heading" style={{ marginTop: 0 }}>Evidence</h3>
          <div style={{ marginBottom: 16 }}>
            <img
              src={report.imageUrl}
              alt="Disaster evidence"
              style={{
                width: '100%',
                maxHeight: 400,
                objectFit: 'cover',
                border: 'var(--nb-border)',
                boxShadow: 'var(--nb-shadow-sm)',
              }}
            />
          </div>

          {report.description && (
            <Field label="Description" value={report.description} />
          )}

          <Field
            label="Location"
            value={
              hasLocation
                ? `${report.lat.toFixed(6)}, ${report.lon.toFixed(6)}`
                : '—'
            }
            mono
          />

          {mapUrl && (
            <div style={{ marginTop: 8 }}>
              <iframe
                src={mapUrl}
                title="Report Location"
                style={{
                  width: '100%',
                  height: 200,
                  border: '3px solid var(--nb-ink)',
                  boxShadow: 'var(--nb-shadow-sm)',
                }}
                loading="lazy"
              />
              <a
                href={`https://www.google.com/maps?q=${report.lat},${report.lon}`}
                target="_blank"
                rel="noopener noreferrer"
                className="nb-btn nb-btn--sm"
                style={{ marginTop: 8, textDecoration: 'none', width: '100%', justifyContent: 'center', display: 'inline-flex' }}
              >
                ⊕ Open in Google Maps
              </a>
            </div>
          )}
        </div>

        {/* Right: Details */}
        <div className="nb-card nb-card--sm">
          <h3 className="section-heading" style={{ marginTop: 0 }}>Report Details</h3>
          <Field label="Report ID" value={report.id} mono />
          <Field label="Category" value={
            <span className={`nb-badge nb-badge--cat-${report.category}`}>{report.category}</span>
          } />
          <Field label="Severity" value={
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <div style={{
                width: 80, height: 12,
                border: '2px solid var(--nb-ink)',
                background: `linear-gradient(to right, ${sevColor} ${report.severityScore * 20}%, transparent ${report.severityScore * 20}%)`,
              }} />
              <strong style={{ color: sevColor, fontSize: '1.1rem' }}>{report.severityScore}/5</strong>
            </div>
          } />
          <Field label="AI Confidence" value={`${(report.llmConfidence * 100).toFixed(0)}%`} mono />
          <Field label="Verification" value={<VerificationBadge status={report.verificationStatus} />} />
          <Field label="Authority Status" value={<AuthorityBadge status={report.authorityStatus} />} />
          {report.rejectionReason && (
            <Field label="Rejection Reason" value={report.rejectionReason} />
          )}
          <Field label="Submitted" value={formatTs(report.createdAt)} />
          <Field label="Updated" value={formatTs(report.updatedAt)} />
          {report.linkedSosId && (
            <Field label="Linked SOS Event" value={report.linkedSosId} mono />
          )}
        </div>
      </div>

      {/* Reporter info */}
      <h3 className="section-heading">Reporter</h3>
      <div className="nb-card nb-card--sm" style={{ marginBottom: 24 }}>
        {report.reporter ? (
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
            <Field label="Name" value={report.reporter.name ?? 'Unknown'} />
            <Field label="Phone" value={report.reporter.phone} mono />
            <Field label="Role" value={<span className={`nb-badge nb-badge--${report.reporter.role}`}>{report.reporter.role}</span>} />
            <Field label="KYC" value={<span className={`nb-badge nb-badge--${report.reporter.kycStatus}`}>{report.reporter.kycStatus}</span>} />
          </div>
        ) : (
          <p style={{ opacity: 0.4, fontWeight: 600 }}>Reporter profile not found</p>
        )}
      </div>

      {/* Raw LLM Response */}
      {report.llmRawResponse && (
        <>
          <h3 className="section-heading">AI Analysis (Raw)</h3>
          <div className="nb-card nb-card--sm">
            <pre style={{
              fontFamily: 'var(--font-mono)',
              fontSize: '0.78rem',
              whiteSpace: 'pre-wrap',
              wordBreak: 'break-word',
              margin: 0,
            }}>
              {JSON.stringify(report.llmRawResponse, null, 2)}
            </pre>
          </div>
        </>
      )}
    </>
  );
}
