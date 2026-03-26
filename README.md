# Civic Emergency Access Layer (CEAL)

Offline-first civic emergency response platform with:
- a BLE mesh-enabled Flutter mobile app,
- a Node.js/TypeScript backend + PostgreSQL,
- a React admin dashboard,
- and an optional Python FastAPI QR-processing service.

This repository is a monorepo containing all components.

## Repository Layout

```text
afm-work/
├── backend/           # Node.js + Express + PostgreSQL API
├── admin-dashboard/   # React + Vite operations/admin UI
├── mobile/            # Flutter app (BLE SOS, relay, onboarding)
├── python/            # FastAPI QR decode + forward helper service
├── docker-compose.yml # Local backend + postgres stack
└── WHITEPAPER.md      # Full protocol and architecture details
```

## Core Capabilities

- BLE SOS broadcast + mesh relay (mobile app)
- Offline queue + later sync to backend
- Onboarding + KYC-related flows
- SOS ingestion/ack lifecycle APIs
- Disaster reporting with image verification pipeline
- Admin APIs + dashboard views for events/users/reports

## Tech Stack

- **Mobile:** Flutter, Riverpod, BLE plugins, SQLite
- **Backend:** Node.js 22, TypeScript, Express, PostgreSQL, Zod, Vitest
- **Dashboard:** React 18, TypeScript, Vite
- **Python service:** FastAPI, OpenCV, NumPy, Uvicorn

---

## Prerequisites

- Docker + Docker Compose
- Node.js 18+ (Node 22 recommended for backend image parity)
- npm
- Flutter SDK (for mobile)
- Python 3.12 (for optional `python/` service)

---

## Quick Start (Backend + Postgres via Docker)

From repo root:

```bash
cd backend
cp .env.example .env
```

Update at least these in `backend/.env` before starting:
- `BLE_ENCRYPTION_SECRET`
- `JWT_SECRET`
- `SERVER_SECRET` (recommended)

Then run:

```bash
cd ..
docker compose up --build
```

Services:
- Backend: `http://localhost:3000`
- Health: `http://localhost:3000/v1/health`
- Postgres: `localhost:5432`

The compose backend command runs install + migration + dev server automatically.

---

## Run Services Individually (Without Docker Compose)

### 1) Backend

```bash
cd backend
cp .env.example .env
npm ci
npm run migrate
npm run dev
```

Useful scripts:
- `npm run build`
- `npm start`
- `npm test`
- `npm run db:reset`

### 2) Admin Dashboard

```bash
cd admin-dashboard
npm install
npm run dev
```

Default dashboard URL: `http://localhost:5173`

Dashboard access now requires a JWT in the browser. Open `/login`, paste an
admin token, and the UI stores it under `ceal_token` in `localStorage`.

Dashboard API base defaults to `http://localhost:3000/v1`.
Override with:

```bash
VITE_API_BASE_URL=http://localhost:3000/v1 npm run dev

Production URLs:
- Backend: `https://ceal.onrender.com`
- Admin dashboard: `https://ceal-peach.vercel.app`
```

### 3) Mobile App (Flutter)

```bash
cd mobile
flutter pub get
flutter run
```

For local backend testing on LAN, update `mobile/.env`:

```env
API_BASE_URL=http://<YOUR_LOCAL_IP>:3000/v1
BLE_ENCRYPTION_SECRET=<same-as-backend>
PYTHON_QR_BASE_URL=https://ceal-1.onrender.com
```

Helper script:

```bash
cd mobile
./scripts/set_local_api.sh 3000 .env
```

### 4) Python QR Service (Optional)

```bash
cd python
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.app:app --host 0.0.0.0 --port 8001
```

Default service health: `http://localhost:8001/health`

Run via Docker Compose:

```bash
docker compose up --build python-qr
```

`python-qr` reads its configuration from `python/.env` (via `env_file` in `docker-compose.yml`).

Important env vars:
- `TS_BACKEND_URL` (full override, e.g. `https://ceal.onrender.com/v1/onboarding/verify-aadhaar-qr`)
- `TS_BACKEND_BASE_URL` (default: `http://backend:3000`)
- `TS_BACKEND_PATH` (default: `/v1/onboarding/verify-aadhaar-qr`)
- `TS_BACKEND_AUTH_TOKEN` (optional bearer token)
- `PYTHON_SERVICE_SECRET`
- `PYTHON_REQUEST_TIMEOUT_SEC`

---

## API Surface (High Level)

All backend routes are under `/v1`:
- `/health`
- `/auth`
- `/onboarding`
- `/sos`
- `/users`
- `/disaster`
- `/admin`

`POST /v1/auth/token` is gated by the `X-Server-Secret` header and is intended
for trusted internal/admin tooling only.

For protocol and lifecycle details, see `WHITEPAPER.md`.

---

## Testing

Backend tests:

```bash
cd backend
npm test
```

---

## Notes

- Keep production secrets out of source control.
- Ensure mobile and backend `BLE_ENCRYPTION_SECRET` values are aligned.
- The backend currently validates env at startup; invalid or missing required vars will stop boot.

---

## License

No explicit license file is currently present in this repository.
