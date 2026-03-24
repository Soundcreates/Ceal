const TOKEN_KEY = 'ceal_token';

interface JwtPayload {
  exp?: number;
}

function parseJwt(token: string): JwtPayload | null {
  const parts = token.split('.');
  if (parts.length !== 3) return null;

  try {
    const base64 = parts[1]!.replace(/-/g, '+').replace(/_/g, '/');
    const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, '=');
    const json = window.atob(padded);
    return JSON.parse(json) as JwtPayload;
  } catch {
    return null;
  }
}

export function getStoredToken(): string | null {
  const token = window.localStorage.getItem(TOKEN_KEY);
  if (!token) return null;
  if (isTokenExpired(token)) {
    clearStoredToken();
    return null;
  }
  return token;
}

export function setStoredToken(token: string): void {
  window.localStorage.setItem(TOKEN_KEY, token.trim());
}

export function clearStoredToken(): void {
  window.localStorage.removeItem(TOKEN_KEY);
}

export function isTokenExpired(token: string): boolean {
  const payload = parseJwt(token);
  if (!payload?.exp) return false;
  return payload.exp * 1000 <= Date.now();
}

export function redirectToLogin(): void {
  clearStoredToken();
  if (window.location.pathname !== '/login') {
    window.location.assign('/login');
  }
}
