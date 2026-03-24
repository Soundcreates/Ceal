import { useState } from 'react';
import { Navigate, useNavigate } from 'react-router-dom';
import { getStoredToken, isTokenExpired, setStoredToken } from '../auth';

export default function Login() {
  const navigate = useNavigate();
  const existingToken = getStoredToken();
  const [token, setToken] = useState(existingToken ?? '');
  const [error, setError] = useState<string | null>(null);

  if (existingToken) {
    return <Navigate to="/admin/dashboard" replace />;
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
      </form>
    </div>
  );
}
