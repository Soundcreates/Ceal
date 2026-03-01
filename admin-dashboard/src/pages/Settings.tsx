import { useState } from 'react';

const API_BASE = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000/v1';

export default function Settings() {
  const [testResult, setTestResult] = useState<string | null>(null);
  const [testing, setTesting] = useState(false);

  const testConnection = async () => {
    setTesting(true);
    setTestResult(null);
    try {
      const res = await fetch(`${API_BASE}/health`);
      const contentType = res.headers.get('content-type')?.toLowerCase() ?? '';
      if (!res.ok) {
        throw new Error(`Request failed: ${res.status}`);
      }
      if (!contentType.includes('application/json')) {
        throw new Error('Backend returned non-JSON response');
      }
      const data = await res.json();
      setTestResult(`✓ Connected — DB: ${data.database ?? 'ok'}, Uptime: ${data.uptime ?? '?'}s`);
    } catch (err) {
      setTestResult(`✕ Failed: ${(err as Error).message}`);
    } finally {
      setTesting(false);
    }
  };

  return (
    <>
      <div className="page-header">
        <h2>Settings</h2>
      </div>

      {/* System Info */}
      <div className="detail-grid" style={{ marginBottom: 24 }}>
        <div className="nb-card nb-card--sm">
          <h3 className="section-heading" style={{ marginTop: 0 }}>System Configuration</h3>
          <div className="detail-field">
            <div className="detail-field__label">API Base URL</div>
            <div className="detail-field__value detail-field__value--mono">{API_BASE}</div>
          </div>
          <div className="detail-field">
            <div className="detail-field__label">Dashboard Version</div>
            <div className="detail-field__value">1.0.0</div>
          </div>
          <div className="detail-field">
            <div className="detail-field__label">Protocol</div>
            <div className="detail-field__value">CEAL BLE Mesh SOS v2</div>
          </div>
          <div className="detail-field">
            <div className="detail-field__label">Auto-Refresh</div>
            <div className="detail-field__value">
              Dashboard: 8s &middot; Events: 10s &middot; Event Detail: 6s
            </div>
          </div>
        </div>

        <div className="nb-card nb-card--sm">
          <h3 className="section-heading" style={{ marginTop: 0 }}>Backend Health</h3>
          <div style={{ marginBottom: 16 }}>
            <button
              className="nb-btn nb-btn--primary nb-btn--sm"
              disabled={testing}
              onClick={testConnection}
            >
              {testing ? 'Testing…' : 'Test Connection'}
            </button>
          </div>
          {testResult && (
            <div
              className="nb-card nb-card--sm"
              style={{
                background: testResult.startsWith('✓') ? 'rgba(16,185,129,0.1)' : 'rgba(239,68,68,0.1)',
                borderColor: testResult.startsWith('✓') ? 'var(--nb-ok)' : 'var(--nb-error)',
              }}
            >
              <span style={{ fontFamily: 'var(--font-mono)', fontSize: '0.85rem', fontWeight: 700 }}>
                {testResult}
              </span>
            </div>
          )}
        </div>
      </div>

      {/* SOS Status Reference */}
      <h3 className="section-heading">SOS Status Reference</h3>
      <div className="nb-card nb-card--sm" style={{ marginBottom: 24 }}>
        <div className="nb-table-wrap" style={{ border: 'none', boxShadow: 'none' }}>
          <table className="nb-table" style={{ fontSize: '0.85rem' }}>
            <thead>
              <tr>
                <th>Status</th>
                <th>Description</th>
                <th>Badge</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td><strong>Active</strong></td>
                <td>SOS just received, emergency in progress</td>
                <td><span className="nb-badge nb-badge--active">Active</span></td>
              </tr>
              <tr>
                <td><strong>Relayed</strong></td>
                <td>BLE mesh relayed the signal, pending internet upload</td>
                <td><span className="nb-badge nb-badge--relayed">Relayed</span></td>
              </tr>
              <tr>
                <td><strong>Acknowledged</strong></td>
                <td>An admin or responder has acknowledged the alert</td>
                <td><span className="nb-badge nb-badge--acknowledged">Acknowledged</span></td>
              </tr>
              <tr>
                <td><strong>Resolved</strong></td>
                <td>Emergency resolved, no further action needed</td>
                <td><span className="nb-badge nb-badge--resolved">Resolved</span></td>
              </tr>
              <tr>
                <td><strong>Cancelled</strong></td>
                <td>Alert was false or cancelled by user/admin</td>
                <td><span className="nb-badge nb-badge--cancelled">Cancelled</span></td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      {/* SOS Type Reference */}
      <h3 className="section-heading">SOS Type Reference</h3>
      <div className="nb-card nb-card--sm">
        <div className="nb-table-wrap" style={{ border: 'none', boxShadow: 'none' }}>
          <table className="nb-table" style={{ fontSize: '0.85rem' }}>
            <thead>
              <tr>
                <th>Flag Bit</th>
                <th>Type</th>
              </tr>
            </thead>
            <tbody>
              <tr><td className="mono">Bit 0</td><td>General SOS</td></tr>
              <tr><td className="mono">Bit 1</td><td>Fire Emergency</td></tr>
              <tr><td className="mono">Bit 2</td><td>Crime Alert</td></tr>
              <tr><td className="mono">Bit 3</td><td>Kidnap Alert</td></tr>
              <tr><td className="mono">Bit 4</td><td>Medical Emergency</td></tr>
              <tr><td className="mono">Bit 5</td><td>Natural Disaster</td></tr>
            </tbody>
          </table>
        </div>
      </div>
    </>
  );
}
