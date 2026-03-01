import { Link } from 'react-router-dom';
import MeshSimulation from '../components/MeshSimulation';
import ArchitectureFlow from '../components/ArchitectureFlow';
import FeatureShowcase from '../components/FeatureShowcase';
import ProtocolVisualizer from '../components/ProtocolVisualizer';

/* ================================================================== */
/*  CEAL Protocol — Landing Page                                  */
/*  Neo-Brutalist style matching the admin dashboard + mobile app      */
/* ================================================================== */

/* ---------- tiny helpers ---------- */
const S = (p: React.CSSProperties) => p;

function Section({ id, children, dark }: { id?: string; children: React.ReactNode; dark?: boolean }) {
  return (
    <section
      id={id}
      style={{
        padding: '80px 0',
        background: dark ? 'var(--nb-ink)' : 'transparent',
        color: dark ? 'var(--nb-bg)' : 'var(--nb-ink)',
      }}
    >
      <div style={{ maxWidth: 1120, margin: '0 auto', padding: '0 24px' }}>{children}</div>
    </section>
  );
}

function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <div
      style={{
        fontFamily: 'var(--font-mono)',
        fontSize: '0.72rem',
        fontWeight: 700,
        textTransform: 'uppercase' as const,
        letterSpacing: '0.18em',
        marginBottom: 10,
        opacity: 0.5,
      }}
    >
      {children}
    </div>
  );
}

function SectionTitle({ children }: { children: React.ReactNode }) {
  return (
    <h2
      style={{
        fontSize: 'clamp(1.8rem, 4vw, 2.6rem)',
        fontWeight: 700,
        letterSpacing: '-0.03em',
        lineHeight: 1.15,
        marginBottom: 24,
      }}
    >
      {children}
    </h2>
  );
}

function Card({
  children,
  accent,
  style,
}: {
  children: React.ReactNode;
  accent?: string;
  style?: React.CSSProperties;
}) {
  return (
    <div
      className="nb-card"
      style={{
        borderColor: accent ?? 'var(--nb-ink)',
        ...style,
      }}
    >
      {children}
    </div>
  );
}

function StatBox({ value, label }: { value: string; label: string }) {
  return (
    <div style={{ textAlign: 'center' }}>
      <div
        style={{
          fontSize: 'clamp(2rem, 4vw, 3rem)',
          fontWeight: 700,
          fontFamily: 'var(--font-mono)',
          lineHeight: 1,
        }}
      >
        {value}
      </div>
      <div
        style={{
          fontFamily: 'var(--font-mono)',
          fontSize: '0.7rem',
          fontWeight: 700,
          textTransform: 'uppercase' as const,
          letterSpacing: '0.12em',
          marginTop: 6,
          opacity: 0.5,
        }}
      >
        {label}
      </div>
    </div>
  );
}

function TechBadge({ children }: { children: React.ReactNode }) {
  return (
    <span
      style={{
        display: 'inline-block',
        padding: '5px 14px',
        border: '3px solid currentColor',
        boxShadow: '3px 3px 0 currentColor',
        fontFamily: 'var(--font-mono)',
        fontSize: '0.72rem',
        fontWeight: 700,
        textTransform: 'uppercase' as const,
        letterSpacing: '0.06em',
      }}
    >
      {children}
    </span>
  );
}

/* ================================================================== */
/*  Page                                                               */
/* ================================================================== */

export default function Landing() {
  return (
    <div style={{ minHeight: '100vh' }}>
      {/* ============================================================ */}
      {/* NAV BAR                                                       */}
      {/* ============================================================ */}
      <header
        style={{
          position: 'fixed',
          top: 0,
          left: 0,
          right: 0,
          zIndex: 1000,
          background: 'var(--nb-bg)',
          borderBottom: 'var(--nb-border)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          padding: '0 32px',
          height: 64,
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <span style={{ fontSize: '1.4rem', fontWeight: 700, letterSpacing: '-0.03em' }}>
            CEAL
          </span>
          <span
            style={{
              fontFamily: 'var(--font-mono)',
              fontSize: '0.6rem',
              fontWeight: 700,
              textTransform: 'uppercase',
              letterSpacing: '0.15em',
              opacity: 0.4,
              marginTop: 2,
            }}
          >
            CEAL Protocol
          </span>
        </div>
        <nav style={{ display: 'flex', alignItems: 'center', gap: 24 }}>
          {[
            ['#how-it-works', 'How It Works'],
            ['#features', 'Features'],
            ['#protocol', 'Protocol'],
            ['#tech-stack', 'Tech Stack'],
            ['#security', 'Security'],
            ['#architecture', 'Architecture'],
          ].map(([href, label]) => (
            <a
              key={href}
              href={href}
              style={{
                color: 'var(--nb-ink)',
                fontWeight: 600,
                fontSize: '0.82rem',
                textDecoration: 'none',
                opacity: 0.7,
                transition: 'opacity 0.15s',
              }}
              onMouseEnter={(e) => (e.currentTarget.style.opacity = '1')}
              onMouseLeave={(e) => (e.currentTarget.style.opacity = '0.7')}
            >
              {label}
            </a>
          ))}
          <Link
            to="/admin"
            className="nb-btn nb-btn--primary nb-btn--sm"
            style={{ textDecoration: 'none', marginLeft: 8 }}
          >
            Admin →
          </Link>
        </nav>
      </header>

      {/* spacing for fixed nav */}
      <div style={{ height: 64 }} />

      {/* ============================================================ */}
      {/* HERO                                                          */}
      {/* ============================================================ */}
      <Section>
        <div style={{ maxWidth: 780, paddingTop: 48, paddingBottom: 16 }}>
          <div
            style={{
              display: 'inline-block',
              padding: '4px 14px',
              border: '3px solid var(--nb-ink)',
              boxShadow: '3px 3px 0 var(--nb-ink)',
              fontFamily: 'var(--font-mono)',
              fontSize: '0.68rem',
              fontWeight: 700,
              textTransform: 'uppercase',
              letterSpacing: '0.12em',
              marginBottom: 24,
            }}
          >
            Civic Emergency Access Layer
          </div>
          <h1
            style={{
              fontSize: 'clamp(2.8rem, 7vw, 5rem)',
              fontWeight: 700,
              lineHeight: 1.05,
              letterSpacing: '-0.04em',
              marginBottom: 24,
            }}
          >
            Emergency SOS
            <br />
            <span style={{ color: 'var(--nb-error)' }}>Without Internet.</span>
          </h1>
          <p
            style={{
              fontSize: 'clamp(1rem, 2vw, 1.2rem)',
              lineHeight: 1.7,
              opacity: 0.7,
              maxWidth: 580,
              marginBottom: 36,
            }}
          >
            CEAL is an offline-first BLE mesh emergency protocol. Every phone becomes a
            relay node — SOS signals hop device-to-device until they reach the internet.
            No WiFi, no cellular, no problem.
          </p>
          <div style={{ display: 'flex', gap: 16, flexWrap: 'wrap' }}>
            <a href="#how-it-works" className="nb-btn nb-btn--primary" style={{ textDecoration: 'none' }}>
              See How It Works
            </a>
            <Link to="/admin" className="nb-btn" style={{ textDecoration: 'none' }}>
              Open Admin Dashboard →
            </Link>
          </div>
        </div>

        {/* Stat strip */}
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(4, 1fr)',
            gap: 20,
            marginTop: 56,
          }}
        >
          <Card accent="var(--nb-error)">
            <StatBox value="0ms" label="Internet Required" />
          </Card>
          <Card accent="var(--nb-accent)">
            <StatBox value="10B" label="SOS Packet Size" />
          </Card>
          <Card accent="var(--nb-ok)">
            <StatBox value="6" label="Emergency Types" />
          </Card>
          <Card accent="var(--nb-accent2)">
            <StatBox value="∞" label="Mesh Hop Range" />
          </Card>
        </div>
      </Section>

      {/* ============================================================ */}
      {/* HOW IT WORKS — Interactive Simulation                         */}
      {/* ============================================================ */}
      <Section id="how-it-works" dark>
        <SectionLabel>How It Works</SectionLabel>
        <SectionTitle>Live BLE Mesh Simulation</SectionTitle>
        <p style={{ maxWidth: 620, opacity: 0.6, lineHeight: 1.7, marginBottom: 32 }}>
          Watch the SOS signal propagate through the mesh network in real-time.
          Click the victim node to trigger an emergency — packets hop device-to-device
          via BLE, reach gateway nodes, upload to backend, and fire SMS alerts.
        </p>

        <MeshSimulation />

        {/* Phase legend */}
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))',
            gap: 16,
            marginTop: 32,
          }}
        >
          {[
            { phase: '1. SOS Triggered', desc: 'Volume buttons from lock screen. 5-second cancellable countdown. 6 emergency categories.', color: '#EF4444' },
            { phase: '2. BLE Broadcast', desc: '10-byte V2 packet: version, flags, BLE UID, sequence, CRC8. No GPS. No internet.', color: '#F59E0B' },
            { phase: '3. Mesh Relay', desc: 'Nearby devices validate CRC8, attach own GPS, and re-broadcast with jitter. 5-min dedup.', color: '#3B82F6' },
            { phase: '4. Gateway Upload', desc: 'First device with connectivity POSTs to backend. Offline queue drains automatically.', color: '#8B5CF6' },
            { phase: '5. SMS Alerts', desc: 'Twilio SMS to all contacts: victim name, GPS, Maps link. Plus direct device SMS (dual-path).', color: '#10B981' },
            { phase: '6. Admin Response', desc: 'Dashboard shows live events. Acknowledge, resolve, or auto-escalate after 30 seconds.', color: '#EF4444' },
          ].map(({ phase, desc, color }) => (
            <div
              key={phase}
              style={{
                background: 'rgba(254,252,232,0.04)',
                borderLeft: `4px solid ${color}`,
                padding: '14px 16px',
              }}
            >
              <div
                style={{
                  fontFamily: 'var(--font-mono)',
                  fontSize: '0.68rem',
                  fontWeight: 700,
                  color,
                  letterSpacing: '0.06em',
                  marginBottom: 6,
                }}
              >
                {phase}
              </div>
              <div style={{ fontSize: '0.8rem', opacity: 0.5, lineHeight: 1.55 }}>{desc}</div>
            </div>
          ))}
        </div>

        {/* Dual-path highlight */}
        <div
          style={{
            marginTop: 32,
            padding: 24,
            border: '3px solid rgba(254,252,232,0.2)',
            background: 'rgba(254,252,232,0.04)',
            display: 'flex',
            gap: 20,
            alignItems: 'center',
            flexWrap: 'wrap',
          }}
        >
          <div style={{ fontSize: '2rem' }}>--</div>
          <div>
            <div style={{ fontWeight: 700, marginBottom: 4 }}>Dual-Path SMS Delivery</div>
            <div style={{ fontSize: '0.85rem', opacity: 0.6, lineHeight: 1.6 }}>
              SMS reaches emergency contacts via <strong>two independent paths</strong>: (A) Backend Twilio API
              (cloud SMS) and (B) Relayer device&apos;s native SMS modem (Android direct SMS, no backend
              needed). If either path succeeds, contacts are notified.
            </div>
          </div>
        </div>
      </Section>

      {/* ============================================================ */}
      {/* FEATURES — Interactive Showcase                                */}
      {/* ============================================================ */}
      <Section id="features">
        <SectionLabel>Features</SectionLabel>
        <SectionTitle>Built for Real Emergencies</SectionTitle>
        <p style={{ maxWidth: 560, opacity: 0.55, lineHeight: 1.7, marginBottom: 32, fontSize: '0.95rem' }}>
          12 capabilities across 4 categories. Filter by category, click any card to reveal deep technical details.
        </p>
        <FeatureShowcase />
      </Section>

      {/* ============================================================ */}
      {/* PROTOCOL SPEC — Interactive Visualizer                        */}
      {/* ============================================================ */}
      <Section id="protocol" dark>
        <SectionLabel>Protocol Specification</SectionLabel>
        <SectionTitle>BLE Mesh SOS Protocol V2</SectionTitle>
        <p style={{ maxWidth: 600, opacity: 0.5, lineHeight: 1.7, marginBottom: 32, fontSize: '0.95rem' }}>
          Click bytes to inspect bit-level detail. Animate the packet construction. Run the relay pipeline step-by-step.
        </p>
        <ProtocolVisualizer />
      </Section>

      {/* ============================================================ */}
      {/* TECH STACK                                                    */}
      {/* ============================================================ */}
      <Section id="tech-stack">
        <SectionLabel>Tech Stack</SectionLabel>
        <SectionTitle>Modern, Battle-Tested Technologies</SectionTitle>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 24 }}>
          {/* Mobile */}
          <Card accent="var(--nb-accent)">
            <div
              style={{
                fontFamily: 'var(--font-mono)',
                fontSize: '0.68rem',
                fontWeight: 700,
                textTransform: 'uppercase',
                letterSpacing: '0.12em',
                color: 'var(--nb-accent)',
                marginBottom: 14,
              }}
            >
              Mobile App
            </div>
            <h3 style={{ fontSize: '1.15rem', fontWeight: 700, marginBottom: 16 }}>Flutter / Dart</h3>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
              {[
                'Flutter SDK ^3.11',
                'Riverpod',
                'FlutterBluePlus',
                'BLE Peripheral',
                'Geolocator',
                'SQLite',
                'Foreground Task',
                'Secure Storage',
                'GoRouter',
                'Connectivity+',
                'Mobile Scanner',
              ].map((t) => (
                <TechBadge key={t}>{t}</TechBadge>
              ))}
            </div>
          </Card>

          {/* Backend */}
          <Card accent="var(--nb-ok)">
            <div
              style={{
                fontFamily: 'var(--font-mono)',
                fontSize: '0.68rem',
                fontWeight: 700,
                textTransform: 'uppercase',
                letterSpacing: '0.12em',
                color: 'var(--nb-ok)',
                marginBottom: 14,
              }}
            >
              Backend Server
            </div>
            <h3 style={{ fontSize: '1.15rem', fontWeight: 700, marginBottom: 16 }}>Node.js / TypeScript</h3>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
              {[
                'Express',
                'TypeScript 5.7',
                'PostgreSQL (Neon)',
                'Twilio SMS',
                'JWT Auth',
                'Zod Validation',
                'Helmet',
                'Winston Logger',
                'Rate Limiter',
                '@anon-aadhaar ZK',
                'WebSockets',
              ].map((t) => (
                <TechBadge key={t}>{t}</TechBadge>
              ))}
            </div>
          </Card>

          {/* Dashboard */}
          <Card accent="var(--nb-accent2)">
            <div
              style={{
                fontFamily: 'var(--font-mono)',
                fontSize: '0.68rem',
                fontWeight: 700,
                textTransform: 'uppercase',
                letterSpacing: '0.12em',
                color: 'var(--nb-accent2)',
                marginBottom: 14,
              }}
            >
              Admin Dashboard
            </div>
            <h3 style={{ fontSize: '1.15rem', fontWeight: 700, marginBottom: 16 }}>React / Vite</h3>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
              {[
                'React 18',
                'Vite 6',
                'TypeScript',
                'React Router 6',
                'Live Polling',
                'NB Design System',
              ].map((t) => (
                <TechBadge key={t}>{t}</TechBadge>
              ))}
            </div>
          </Card>
        </div>

        {/* DB Schema */}
        <div style={{ marginTop: 32 }}>
          <h3 style={{ fontWeight: 700, marginBottom: 16 }}>PostgreSQL Schema — 7 Tables</h3>
          <div className="nb-table-wrap">
            <table className="nb-table">
              <thead>
                <tr>
                  <th>Table</th>
                  <th>Purpose</th>
                  <th>Key Fields</th>
                </tr>
              </thead>
              <tbody>
                {[
                  ['users', 'Core user identity & KYC', 'id, name, phone, ble_uid, role, kyc_status, aadhaar_*'],
                  ['emergency_contacts', 'Up to 10 contacts per user', 'user_id, name, phone, priority'],
                  ['medical_profiles', 'Medical info for responders', 'user_id, blood_group, allergies, conditions'],
                  ['sos_events', 'All SOS events (V2 protocol)', 'id, ble_uid, flags, status, relay_hops, receiver_lat/lon'],
                  ['aadhaar_qr_scans', 'Raw Aadhaar QR records', 'user_id, source, image_sha256, decoded_xml'],
                  ['manual_kyc_submissions', 'Manual KYC form data', 'user_id, name, age, sex, dob, state, district'],
                ].map(([table, purpose, fields]) => (
                  <tr key={table}>
                    <td className="mono" style={{ fontWeight: 700 }}>{table}</td>
                    <td>{purpose}</td>
                    <td className="mono" style={{ fontSize: '0.75rem', opacity: 0.7 }}>{fields}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </Section>

      {/* ============================================================ */}
      {/* SECURITY                                                      */}
      {/* ============================================================ */}
      <Section id="security" dark>
        <SectionLabel>Security & Privacy</SectionLabel>
        <SectionTitle>Zero-Trust, Zero-Knowledge</SectionTitle>

        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))',
            gap: 20,
          }}
        >
          {[
            {
              icon: 'ID',
              title: 'Aadhaar Zero-Knowledge Proofs',
              desc: 'Groth16 ZK-SNARK over BN254 curve. Proves Aadhaar possession without revealing the Aadhaar number. UIDAI RSA-2048 public key hash embedded in circuit. Selective disclosure of demographics.',
            },
            {
              icon: 'SYB',
              title: 'Nullifier-Based Sybil Prevention',
              desc: 'Deterministic nullifier hash from Aadhaar number + seed prevents double-registration. Unique constraint in DB. Cross-account reuse detected and rejected.',
            },
            {
              icon: 'JWT',
              title: 'JWT Authentication',
              desc: 'HS256 tokens with configurable expiry. requireAuth middleware for protected routes, optionalAuth for SOS ingest (allows unauthenticated relays). Tokens encode userId and role.',
            },
            {
              icon: 'BLE',
              title: 'BLE Pseudonymity',
              desc: '6-byte BLE UID randomly generated per install, not derived from any PII. Stored in flutter_secure_storage. No GPS in BLE broadcasts. Receiver attaches its own location.',
            },
            {
              icon: 'TS',
              title: 'Timestamp Replay Protection',
              desc: 'ZK proofs must be recent (15-minute window, 60-second future tolerance). Stale proofs rejected. Signal binding prevents proof portability between users.',
            },
            {
              icon: 'DEF',
              title: 'Defense in Depth',
              desc: 'Helmet HTTP security headers, CORS origin control, IP-based rate limiting (100 req/60s), Zod schema validation on all inputs, CRC8 packet integrity, encrypted BLE payloads.',
            },
          ].map(({ icon, title, desc }) => (
            <div
              key={title}
              style={{
                background: 'rgba(254,252,232,0.04)',
                border: '3px solid rgba(254,252,232,0.12)',
                padding: 24,
              }}
            >
              <div style={{ fontSize: '1.6rem', marginBottom: 10 }}>{icon}</div>
              <h3 style={{ fontSize: '1rem', fontWeight: 700, marginBottom: 8 }}>{title}</h3>
              <p style={{ fontSize: '0.84rem', opacity: 0.6, lineHeight: 1.65 }}>{desc}</p>
            </div>
          ))}
        </div>
      </Section>

      {/* ============================================================ */}
      {/* ARCHITECTURE                                                  */}
      {/* ============================================================ */}
      <Section id="architecture">
        <SectionLabel>Architecture</SectionLabel>
        <SectionTitle>System Overview</SectionTitle>

        <ArchitectureFlow />

        {/* Onboarding flow */}
        <div style={{ marginTop: 32 }}>
          <h3 style={{ fontWeight: 700, marginBottom: 16 }}>User Onboarding Flow</h3>
          <div
            style={{
              display: 'flex',
              gap: 0,
              overflowX: 'auto',
            }}
          >
            {[
              { step: 'Welcome', icon: 'W' },
              { step: 'Permissions', icon: 'P' },
              { step: 'Sign Up', icon: 'S' },
              { step: 'Aadhaar KYC', icon: 'K' },
              { step: 'BLE Relay Active', icon: 'R' },
            ].map((s, i, arr) => (
              <div
                key={s.step}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: 0,
                  flexShrink: 0,
                }}
              >
                <div
                  className="nb-card nb-card--sm"
                  style={{ textAlign: 'center', minWidth: 140 }}
                >
                  <div style={{ fontSize: '1.5rem', marginBottom: 6 }}>{s.icon}</div>
                  <div style={{ fontWeight: 700, fontSize: '0.85rem' }}>{s.step}</div>
                </div>
                {i < arr.length - 1 && (
                  <div
                    style={{
                      fontFamily: 'var(--font-mono)',
                      fontSize: '1.2rem',
                      fontWeight: 700,
                      padding: '0 8px',
                    }}
                  >
                    →
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>

        {/* API endpoints */}
        <div style={{ marginTop: 32 }}>
          <h3 style={{ fontWeight: 700, marginBottom: 16 }}>API Endpoints</h3>
          <div className="nb-table-wrap">
            <table className="nb-table">
              <thead>
                <tr>
                  <th>Method</th>
                  <th>Endpoint</th>
                  <th>Purpose</th>
                </tr>
              </thead>
              <tbody>
                {[
                  ['POST', '/v1/sos/ingest', 'Receive SOS event from BLE relay'],
                  ['POST', '/v1/sos/acknowledge', 'Acknowledge active SOS'],
                  ['GET', '/v1/sos/active', 'List all active/relayed SOS events'],
                  ['GET', '/v1/sos/victim-profile/:bleUid', 'Resolve victim by BLE UID'],
                  ['POST', '/v1/onboarding/signup', 'Register new user'],
                  ['POST', '/v1/onboarding/scan-aadhaar-photo', 'Process Aadhaar QR scan'],
                  ['POST', '/v1/onboarding/manual-kyc', 'Submit manual KYC form'],
                  ['GET', '/v1/admin/stats', 'Dashboard aggregate statistics'],
                  ['GET', '/v1/admin/events', 'Paginated events (admin)'],
                  ['PATCH', '/v1/admin/events/:id/status', 'Update event status (admin)'],
                  ['GET', '/v1/admin/users', 'Paginated users (admin)'],
                  ['GET', '/v1/health', 'Backend health check'],
                ].map(([method, endpoint, purpose]) => (
                  <tr key={endpoint}>
                    <td>
                      <span
                        className="nb-badge"
                        style={{
                          background:
                            method === 'GET'
                              ? 'var(--nb-accent)'
                              : method === 'POST'
                                ? 'var(--nb-ok)'
                                : 'var(--nb-warn)',
                          color: '#fff',
                        }}
                      >
                        {method}
                      </span>
                    </td>
                    <td className="mono" style={{ fontWeight: 600 }}>{endpoint}</td>
                    <td>{purpose}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </Section>

      {/* ============================================================ */}
      {/* FOOTER                                                        */}
      {/* ============================================================ */}
      <footer
        style={{
          background: 'var(--nb-ink)',
          color: 'var(--nb-bg)',
          borderTop: 'var(--nb-border)',
          padding: '40px 0',
        }}
      >
        <div
          style={{
            maxWidth: 1120,
            margin: '0 auto',
            padding: '0 24px',
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            flexWrap: 'wrap',
            gap: 16,
          }}
        >
          <div>
            <div style={{ fontWeight: 700, fontSize: '1.1rem', marginBottom: 4 }}>CEAL</div>
            <div
              style={{
                fontFamily: 'var(--font-mono)',
                fontSize: '0.68rem',
                opacity: 0.4,
                textTransform: 'uppercase',
                letterSpacing: '0.12em',
              }}
            >
              Civic Emergency Access Layer &middot; BLE Mesh SOS Protocol V2
            </div>
          </div>
          <div style={{ display: 'flex', gap: 16, alignItems: 'center' }}>
            <Link
              to="/admin"
              className="nb-btn nb-btn--sm"
              style={{
                textDecoration: 'none',
                borderColor: 'rgba(254,252,232,0.3)',
                color: 'var(--nb-bg)',
                background: 'transparent',
                boxShadow: '3px 3px 0 rgba(254,252,232,0.15)',
              }}
            >
              Admin Dashboard →
            </Link>
          </div>
        </div>
      </footer>
    </div>
  );
}
