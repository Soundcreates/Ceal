import { useState } from 'react';
import { Navigate, useNavigate } from 'react-router-dom';
import { getStoredToken, isTokenExpired, setStoredToken } from '../auth';

export default function Login() {
  const navigate = useNavigate();
  const existingToken = getStoredToken();
  const [token, setToken] = useState(existingToken ?? '');
  const [error, setError] = useState<string | null>(null);
  const [serverSecret, setServerSecret] = useState('');
  const [minting, setMinting] = useState(false);
  const API_BASE = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000/v1';

  if (existingToken) {
    return <Navigate to="/admin/dashboard" replace />;
  }

  async function handleMintAdminToken() {
    const trimmed = serverSecret.trim();
    if (!trimmed) {
      setError('Server secret is required to generate a token.');
      return;
    }

    try {
      setMinting(true);
      setError(null);
      const res = await fetch(`${API_BASE}/auth/token`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Server-Secret': trimmed,
        },
        body: JSON.stringify({ sub: 'admin', role: 'admin' }),
      });

      const body = (await res.json().catch(() => null)) as unknown;
      if (!res.ok) {
        const message =
          body && typeof body === 'object' && body !== null && 'error' in body && typeof body.error === 'string'
            ? body.error
            : `Request failed: ${res.status}`;
        throw new Error(message);
      }

      if (!body || typeof body !== 'object' || !('token' in body) || typeof body.token !== 'string') {
        throw new Error('Backend returned an invalid token response.');
      }

      setToken(body.token);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setMinting(false);
    }
  }

  function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const trimmed = token.trim();
    if (!trimmed) {
      setError('JWT token is required.');
      return;
    }
    if (isTokenExpired(trimmed)) {
      setError('This token is expired.');
      return;
    }

    setStoredToken(trimmed);
    navigate('/admin/dashboard', { replace: true });
  }

  return (
    <div
      style={{
        minHeight: '100vh',
        display: 'grid',
        placeItems: 'center',
        padding: '24px',
        background: 'var(--nb-bg)',
      }}
    >
      <form className="nb-card" style={{ width: 'min(720px, 100%)' }} onSubmit={handleSubmit}>
        <h1 style={{ marginBottom: 12 }}>Admin Login</h1>
        <p style={{ opacity: 0.75, marginBottom: 20 }}>
          Paste a valid CEAL admin JWT to enter the dashboard.
        </p>
        <label htmlFor="jwt" style={{ display: 'block', fontWeight: 700, marginBottom: 8 }}>
          JWT
        </label>
        <textarea
          id="jwt"
          value={token}
          onChange={(event) => {
            setToken(event.target.value);
            if (error) setError(null);
          }}
          rows={8}
          style={{
            width: '100%',
            padding: 12,
            border: 'var(--nb-border)',
            fontFamily: 'var(--font-mono)',
            resize: 'vertical',
            marginBottom: 12,
          }}
        />
        {error ? (
          <div style={{ color: 'var(--nb-error)', fontWeight: 700, marginBottom: 12 }}>{error}</div>
        ) : null}
        <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}>
          <button type="submit" className="nb-btn nb-btn--primary">
            Enter Dashboard
          </button>
          <button
            type="button"
            className="nb-btn nb-btn--ghost"
            onClick={() => navigate('/', { replace: true })}
          >
            Back
          </button>
        </div>

        {import.meta.env.DEV ? (
          <div style={{ marginTop: 18, paddingTop: 14, borderTop: 'var(--nb-border)' }}>
            <div style={{ fontWeight: 800, marginBottom: 6 }}>Dev helper</div>
            <div style={{ opacity: 0.75, marginBottom: 10 }}>
              Generates an admin JWT by calling <span style={{ fontFamily: 'var(--font-mono)' }}>{`${API_BASE}/auth/token`}</span>{' '}
              with your backend <span style={{ fontFamily: 'var(--font-mono)' }}>SERVER_SECRET</span>. Don&apos;t use this flow in production.
            </div>
            <label htmlFor="serverSecret" style={{ display: 'block', fontWeight: 700, marginBottom: 8 }}>
              SERVER_SECRET
            </label>
            <input
              id="serverSecret"
              value={serverSecret}
              onChange={(event) => setServerSecret(event.target.value)}
              placeholder="Paste backend SERVER_SECRET"
              style={{
                width: '100%',
                padding: 12,
                border: 'var(--nb-border)',
                fontFamily: 'var(--font-mono)',
                marginBottom: 12,
              }}
            />
            <button
              type="button"
              className="nb-btn nb-btn--ghost"
              onClick={handleMintAdminToken}
              disabled={minting}
            >
              {minting ? 'Generating…' : 'Generate Admin JWT'}
            </button>
          </div>
        ) : null}
      </form>
    </div>
  );
}
