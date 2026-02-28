import { useState, useRef, useEffect, useCallback } from 'react';

/* ================================================================== */
/*  Feature Showcase — Interactive category-based feature explorer      */
/*  Animated tabs, hover reveal, visual grid with category filtering    */
/* ================================================================== */

interface Feature {
  icon: string;
  title: string;
  desc: string;
  detail: string;   // extra detail shown on expand
  category: Category;
  color: string;
}

type Category = 'mesh' | 'safety' | 'identity' | 'infra' | 'all';

const CATS: { key: Category; label: string; color: string; icon: string }[] = [
  { key: 'all',      label: 'All Features',     color: '#FEFCE8', icon: '*' },
  { key: 'mesh',     label: 'BLE Mesh',          color: '#3B82F6', icon: 'BLE' },
  { key: 'safety',   label: 'Safety & Alerts',   color: '#EF4444', icon: 'SOS' },
  { key: 'identity', label: 'Identity & Privacy', color: '#8B5CF6', icon: 'ID' },
  { key: 'infra',    label: 'Infrastructure',     color: '#10B981', icon: 'SYS' },
];

const FEATURES: Feature[] = [
  {
    icon: 'BLE', title: 'BLE Mesh Network', category: 'mesh', color: '#3B82F6',
    desc: 'Every device is a relay node. SOS signals propagate phone-to-phone via Bluetooth LE.',
    detail: 'Service UUID 0xBEEF, Manufacturer ID 0x1234, TX Power High. No internet, WiFi, or cellular required. Range extends indefinitely with each nearby device.',
  },
  {
    icon: 'PRI', title: 'Privacy-First Protocol', category: 'identity', color: '#8B5CF6',
    desc: 'BLE packets contain NO GPS, NO PII. Only a pseudonymous 6-byte UID.',
    detail: 'Receiver attaches its own GPS location. Victim position is never broadcast. BLE UID randomly generated per install, stored in flutter_secure_storage.',
  },
  {
    icon: 'SOS', title: 'Hardware SOS Trigger', category: 'safety', color: '#EF4444',
    desc: 'Volume button combos from lock screen. 5-second cancellable countdown.',
    detail: '6 emergency categories with haptic feedback. No app unlock needed. Works even when screen is off.',
  },
  {
    icon: 'SMS', title: 'Instant SMS Alerts', category: 'safety', color: '#10B981',
    desc: 'Twilio SMS to all emergency contacts with victim name and GPS coordinates.',
    detail: 'Google Maps link included. Plus direct device SMS as Android fallback — dual-path delivery ensures contacts are reached.',
  },
  {
    icon: 'MED', title: 'Medical Profiles', category: 'safety', color: '#EF4444',
    desc: 'Blood group, allergies, and conditions stored per user.',
    detail: 'Surfaced in victim lookups, SMS alerts, rich Android notifications, and admin dashboard for first responders.',
  },
  {
    icon: 'KYC', title: 'Aadhaar KYC (3 Paths)', category: 'identity', color: '#F59E0B',
    desc: 'ZK-SNARK proof, QR code scan, or manual form. Proves identity privately.',
    detail: 'Groth16 over BN254 curve. UIDAI RSA-2048 key hash in circuit. Nullifier-based sybil prevention blocks double-registration.',
  },
  {
    icon: 'Q', title: 'Offline-First Queue', category: 'infra', color: '#3B82F6',
    desc: 'SOS events persisted to local SQLite, drained when connectivity returns.',
    detail: 'ConnectivityWorker monitors network state. 30-second periodic safety net. Events never lost even in airplane mode.',
  },
  {
    icon: 'ADM', title: 'Live Admin Dashboard', category: 'infra', color: '#8B5CF6',
    desc: 'Real-time web console with active SOS pulse and event management.',
    detail: 'User profiles, KYC oversight, status workflows, 7-day analytics. Built with React 18 + Vite 6 in Neo-Brutalist design.',
  },
  {
    icon: 'NTF', title: 'Smart Notifications', category: 'safety', color: '#10B981',
    desc: 'High-priority Android notifications with victim details.',
    detail: 'Enriched with name, phone, blood group, allergies, and medical conditions. Tap to open full victim detail.',
  },
  {
    icon: 'ESC', title: 'Auto-Escalation', category: 'safety', color: '#EF4444',
    desc: '30-second timer. If unacknowledged, triggers secondary alerts.',
    detail: 'System logs critical warning and can notify backup operators. Ensures no SOS goes unanswered.',
  },
  {
    icon: 'BG', title: 'Always-On Background', category: 'mesh', color: '#F59E0B',
    desc: 'Android foreground service keeps BLE scanning 24/7.',
    detail: 'Persistent notification. Periodic restarts every ~2 minutes prevent OS throttling. Auto-starts on device boot.',
  },
  {
    icon: 'LP', title: 'Self-Loop Prevention', category: 'mesh', color: '#8B5CF6',
    desc: 'Devices ignore self-originated packets. 5-min dedup window.',
    detail: 'Each device stores its own BLE UID. Prevents rebroadcast storms. 10-minute max packet age enforced.',
  },
];

export default function FeatureShowcase() {
  const [activeCategory, setActiveCategory] = useState<Category>('all');
  const [expandedIdx, setExpandedIdx] = useState<number | null>(null);
  const [hoveredIdx, setHoveredIdx] = useState<number | null>(null);
  const gridRef = useRef<HTMLDivElement>(null);

  const filtered = activeCategory === 'all'
    ? FEATURES
    : FEATURES.filter((f) => f.category === activeCategory);

  const activeCat = CATS.find((c) => c.key === activeCategory)!;

  // count per category for the radar
  const counts: Record<Category, number> = {
    all: FEATURES.length,
    mesh: FEATURES.filter((f) => f.category === 'mesh').length,
    safety: FEATURES.filter((f) => f.category === 'safety').length,
    identity: FEATURES.filter((f) => f.category === 'identity').length,
    infra: FEATURES.filter((f) => f.category === 'infra').length,
  };

  return (
    <div>
      {/* ---- Category tabs ---- */}
      <div
        style={{
          display: 'flex',
          gap: 8,
          marginBottom: 32,
          flexWrap: 'wrap',
        }}
      >
        {CATS.map((cat) => {
          const active = cat.key === activeCategory;
          return (
            <button
              key={cat.key}
              onClick={() => { setActiveCategory(cat.key); setExpandedIdx(null); }}
              style={{
                padding: '8px 18px',
                border: `3px solid ${active ? cat.color : 'var(--nb-ink)'}`,
                boxShadow: active ? `4px 4px 0 ${cat.color}` : '3px 3px 0 var(--nb-ink)',
                background: active ? cat.color : 'var(--nb-card)',
                color: active ? (cat.key === 'all' ? 'var(--nb-ink)' : '#fff') : 'var(--nb-ink)',
                fontFamily: "'Space Mono', monospace",
                fontSize: '0.7rem',
                fontWeight: 700,
                letterSpacing: '0.06em',
                textTransform: 'uppercase' as const,
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                gap: 6,
                transition: 'all 0.2s',
              }}
            >
              <span>{cat.icon}</span>
              <span>{cat.label}</span>
              <span
                style={{
                  marginLeft: 4,
                  padding: '1px 6px',
                  fontSize: '0.6rem',
                  border: `2px solid ${active ? 'rgba(255,255,255,0.4)' : 'rgba(0,0,0,0.15)'}`,
                  opacity: 0.7,
                }}
              >
                {counts[cat.key]}
              </span>
            </button>
          );
        })}
      </div>

      {/* ---- Feature grid ---- */}
      <div
        ref={gridRef}
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fill, minmax(320px, 1fr))',
          gap: 16,
        }}
      >
        {filtered.map((f, i) => {
          const isExpanded = expandedIdx === i;
          const isHovered = hoveredIdx === i;
          return (
            <div
              key={f.title}
              onClick={() => setExpandedIdx(isExpanded ? null : i)}
              onMouseEnter={() => setHoveredIdx(i)}
              onMouseLeave={() => setHoveredIdx(null)}
              style={{
                background: 'var(--nb-card)',
                border: `3px solid ${isExpanded ? f.color : isHovered ? f.color : 'var(--nb-ink)'}`,
                boxShadow: isExpanded
                  ? `6px 6px 0 ${f.color}`
                  : isHovered
                    ? `5px 5px 0 var(--nb-ink)`
                    : '4px 4px 0 var(--nb-ink)',
                padding: 0,
                cursor: 'pointer',
                transition: 'all 0.2s',
                transform: isHovered && !isExpanded ? 'translate(-1px, -1px)' : 'none',
                overflow: 'hidden',
              }}
            >
              {/* Color bar at top */}
              <div
                style={{
                  height: 4,
                  background: f.color,
                  transition: 'height 0.2s',
                  ...(isExpanded && { height: 6 }),
                }}
              />

              <div style={{ padding: '16px 20px' }}>
                {/* Header row */}
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                    <div
                      style={{
                        width: 40,
                        height: 40,
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        border: `2px solid ${f.color}`,
                        background: `${f.color}15`,
                        fontSize: '1.2rem',
                        flexShrink: 0,
                      }}
                    >
                      {f.icon}
                    </div>
                    <div>
                      <div style={{ fontWeight: 700, fontSize: '0.95rem', lineHeight: 1.2 }}>{f.title}</div>
                      <div
                        style={{
                          fontFamily: "'Space Mono', monospace",
                          fontSize: '0.58rem',
                          fontWeight: 700,
                          color: f.color,
                          textTransform: 'uppercase',
                          letterSpacing: '0.1em',
                          marginTop: 2,
                        }}
                      >
                        {CATS.find((c) => c.key === f.category)?.label}
                      </div>
                    </div>
                  </div>
                  <div
                    style={{
                      fontFamily: "'Space Mono', monospace",
                      fontSize: '0.9rem',
                      fontWeight: 700,
                      color: f.color,
                      transform: isExpanded ? 'rotate(45deg)' : 'none',
                      transition: 'transform 0.2s',
                    }}
                  >
                    +
                  </div>
                </div>

                {/* Description */}
                <p style={{ fontSize: '0.84rem', opacity: 0.65, lineHeight: 1.6, margin: '12px 0 0' }}>
                  {f.desc}
                </p>

                {/* Expanded detail */}
                {isExpanded && (
                  <div
                    style={{
                      marginTop: 14,
                      paddingTop: 14,
                      borderTop: `2px dashed ${f.color}40`,
                    }}
                  >
                    <div
                      style={{
                        fontFamily: "'Space Mono', monospace",
                        fontSize: '0.62rem',
                        fontWeight: 700,
                        letterSpacing: '0.1em',
                        textTransform: 'uppercase',
                        color: f.color,
                        marginBottom: 6,
                      }}
                    >
                      Technical Detail
                    </div>
                    <p style={{ fontSize: '0.82rem', opacity: 0.75, lineHeight: 1.65, margin: 0 }}>
                      {f.detail}
                    </p>
                  </div>
                )}
              </div>
            </div>
          );
        })}
      </div>

      {/* ---- Category stats bar ---- */}
      <div
        style={{
          marginTop: 28,
          display: 'flex',
          gap: 0,
          border: '3px solid var(--nb-ink)',
          boxShadow: '4px 4px 0 var(--nb-ink)',
          overflow: 'hidden',
        }}
      >
        {CATS.filter((c) => c.key !== 'all').map((cat, i) => {
          const pct = (counts[cat.key] / FEATURES.length) * 100;
          return (
            <div
              key={cat.key}
              onClick={() => { setActiveCategory(cat.key); setExpandedIdx(null); }}
              style={{
                flex: `${counts[cat.key]} 0 0`,
                background: activeCategory === cat.key || activeCategory === 'all'
                  ? cat.color
                  : `${cat.color}30`,
                padding: '12px 14px',
                cursor: 'pointer',
                transition: 'all 0.25s',
                borderRight: i < 3 ? '2px solid var(--nb-ink)' : 'none',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: 6,
              }}
            >
              <span style={{ fontSize: '0.9rem' }}>{cat.icon}</span>
              <span
                style={{
                  fontFamily: "'Space Mono', monospace",
                  fontSize: '0.6rem',
                  fontWeight: 700,
                  color: '#fff',
                  textShadow: '0 1px 3px rgba(0,0,0,0.3)',
                  letterSpacing: '0.05em',
                }}
              >
                {counts[cat.key]}
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}
