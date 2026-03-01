import { useState, useEffect, useRef, useCallback } from 'react';

/* ================================================================== */
/*  Protocol Visualizer — Interactive V2 Packet Dissector               */
/*  Hover/click bytes, animated packet construction, relay pipeline     */
/* ================================================================== */

interface ByteDef {
  offset: string;
  name: string;
  color: string;
  hex: string;
  bits: string;
  desc: string;
  detail: string;
}

const BYTES: ByteDef[] = [
  {
    offset: '0', name: 'version', color: '#3B82F6', hex: '02', bits: '00000010',
    desc: 'Protocol Version',
    detail: 'Fixed at 0x02 for V2 protocol. V1 packets (0x01) are rejected by all V2 nodes. Future versions will increment.',
  },
  {
    offset: '1', name: 'flags', color: '#EF4444', hex: '41', bits: '01000001',
    desc: 'SOS Flags',
    detail: 'Bit 0: SOS active. Bits 1-5: emergency type (General=0, Fire=1, Crime=2, Kidnap=3, Medical=4, Disaster=5). Bits 6-7: reserved.',
  },
  {
    offset: '2', name: 'bleUid[0]', color: '#10B981', hex: 'A7', bits: '10100111',
    desc: 'BLE UID Byte 1',
    detail: '6-byte pseudonymous UID, randomly generated per install. Not derived from any PII. Stored in flutter_secure_storage.',
  },
  {
    offset: '3', name: 'bleUid[1]', color: '#10B981', hex: '3F', bits: '00111111',
    desc: 'BLE UID Byte 2',
    detail: 'Part of the 6-byte block. Combined with bytes 2-7 to form the unique device identifier for dedup and victim resolution.',
  },
  {
    offset: '4', name: 'bleUid[2]', color: '#10B981', hex: 'C2', bits: '11000010',
    desc: 'BLE UID Byte 3',
    detail: 'Random byte from cryptographically secure PRNG. Never changes after initial generation.',
  },
  {
    offset: '5', name: 'bleUid[3]', color: '#10B981', hex: '8E', bits: '10001110',
    desc: 'BLE UID Byte 4',
    detail: '48 bits total = ~281 trillion unique identifiers. Collision probability negligible for mesh-scale deployments.',
  },
  {
    offset: '6', name: 'bleUid[4]', color: '#10B981', hex: '19', bits: '00011001',
    desc: 'BLE UID Byte 5',
    detail: 'Backend resolves victim identity by matching this UID against the users.ble_uid column in PostgreSQL.',
  },
  {
    offset: '7', name: 'bleUid[5]', color: '#10B981', hex: 'D4', bits: '11010100',
    desc: 'BLE UID Byte 6',
    detail: 'Last byte of the UID block. Dedup key = bleUid + sequence number. Cache TTL: 5 minutes.',
  },
  {
    offset: '8', name: 'sequence', color: '#F59E0B', hex: '07', bits: '00000111',
    desc: 'Sequence Counter',
    detail: 'Increments 0-255 per SOS burst (10 packets per burst). Used for dedup: key is bleUid:sequence. Wraps at 255.',
  },
  {
    offset: '9', name: 'crc8', color: '#8B5CF6', hex: 'B3', bits: '10110011',
    desc: 'CRC8 Checksum',
    detail: 'Computed over bytes 0-8. Receivers validate integrity before processing. Corrupt packets silently dropped.',
  },
];

const SOS_TYPES = [
  { bit: 0, code: '0x00', name: 'General SOS', icon: 'SOS', color: '#EF4444', desc: 'Default emergency — any danger not categorized below' },
  { bit: 1, code: '0x01', name: 'Fire Emergency', icon: 'FIR', color: '#EA580C', desc: 'Building fire, wildfire, electrical fire' },
  { bit: 2, code: '0x02', name: 'Crime Alert', icon: 'CRM', color: '#8B5CF6', desc: 'Assault, robbery, active threat' },
  { bit: 3, code: '0x03', name: 'Kidnap Alert', icon: 'KID', color: '#B91C1C', desc: 'Abduction, forced captivity, trafficking' },
  { bit: 4, code: '0x04', name: 'Medical Emergency', icon: 'MED', color: '#3B82F6', desc: 'Heart attack, seizure, severe injury' },
  { bit: 5, code: '0x05', name: 'Natural Disaster', icon: 'NAT', color: '#0D9488', desc: 'Earthquake, flood, tsunami, cyclone' },
];

const RELAY_STEPS = [
  { label: 'BLE Scan', detail: 'Detect manufacturer ID 0x1234 on UUID 0xBEEF', icon: 'BLE', color: '#3B82F6' },
  { label: 'CRC8 Check', detail: 'Validate integrity checksum over bytes 0-8', icon: 'CRC', color: '#10B981' },
  { label: 'Dedup Filter', detail: 'Check cache: key = bleUid:seq, TTL = 5 min', icon: 'DDP', color: '#F59E0B' },
  { label: 'Self-Loop', detail: 'Reject if bleUid matches own device UID', icon: 'SLP', color: '#8B5CF6' },
  { label: 'GPS Attach', detail: 'Attach receiver lat/lon + RSSI strength', icon: 'GPS', color: '#EF4444' },
  { label: 'Re-broadcast', detail: 'Jitter 100-400ms, then BLE advertise again', icon: 'TX', color: '#3B82F6' },
  { label: 'Queue Upload', detail: 'POST to backend or persist in SQLite queue', icon: 'UP', color: '#10B981' },
];

export default function ProtocolVisualizer() {
  const [selectedByte, setSelectedByte] = useState<number | null>(null);
  const [hoveredByte, setHoveredByte] = useState<number | null>(null);
  const [activeSosType, setActiveSosType] = useState<number>(0);
  const [relayStep, setRelayStep] = useState<number>(-1);
  const [isAnimating, setIsAnimating] = useState(false);
  const [packetBuilt, setPacketBuilt] = useState<number[]>([]);
  const buildTimerRef = useRef<ReturnType<typeof setTimeout>[]>([]);
  const relayTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Animated packet build
  const buildPacket = useCallback(() => {
    // clear previous
    buildTimerRef.current.forEach(clearTimeout);
    buildTimerRef.current = [];
    setPacketBuilt([]);
    setSelectedByte(null);
    setIsAnimating(true);

    for (let i = 0; i < 10; i++) {
      const t = setTimeout(() => {
        setPacketBuilt((prev) => [...prev, i]);
        setSelectedByte(i);
        if (i === 9) {
          setTimeout(() => setIsAnimating(false), 400);
        }
      }, i * 200 + 100);
      buildTimerRef.current.push(t);
    }
  }, []);

  // Animated relay pipeline
  const runRelay = useCallback(() => {
    if (relayTimerRef.current) clearInterval(relayTimerRef.current);
    setRelayStep(0);
    let step = 0;
    relayTimerRef.current = setInterval(() => {
      step++;
      if (step >= RELAY_STEPS.length) {
        if (relayTimerRef.current) clearInterval(relayTimerRef.current);
        setTimeout(() => setRelayStep(-1), 2000);
      } else {
        setRelayStep(step);
      }
    }, 700);
  }, []);

  useEffect(() => {
    return () => {
      buildTimerRef.current.forEach(clearTimeout);
      if (relayTimerRef.current) clearInterval(relayTimerRef.current);
    };
  }, []);

  const activeByteDef = selectedByte !== null ? BYTES[selectedByte] : hoveredByte !== null ? BYTES[hoveredByte] : null;

  return (
    <div>
      {/* ---- Packet Dissector ---- */}
      <div
        style={{
          display: 'grid',
          gridTemplateColumns: '1fr 340px',
          gap: 24,
          marginBottom: 32,
        }}
      >
        {/* Left: byte visualization */}
        <div>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 16 }}>
            <h3 style={{ fontWeight: 700, margin: 0, fontSize: '1.05rem' }}>Core V2 Packet — 10 Bytes</h3>
            <button
              onClick={buildPacket}
              disabled={isAnimating}
              style={{
                padding: '6px 14px',
                border: '2px solid currentColor',
                boxShadow: '3px 3px 0 currentColor',
                background: 'transparent',
                color: isAnimating ? 'rgba(254,252,232,0.3)' : '#F59E0B',
                fontFamily: "'Space Mono', monospace",
                fontSize: '0.62rem',
                fontWeight: 700,
                letterSpacing: '0.06em',
                textTransform: 'uppercase' as const,
                cursor: isAnimating ? 'default' : 'pointer',
              }}
            >
              ▶ Animate Build
            </button>
          </div>

          {/* Byte grid */}
          <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginBottom: 16 }}>
            {BYTES.map((b, i) => {
              const isSelected = selectedByte === i;
              const isHovered = hoveredByte === i;
              const isBuilt = packetBuilt.length === 0 || packetBuilt.includes(i);
              return (
                <div
                  key={i}
                  onClick={() => setSelectedByte(isSelected ? null : i)}
                  onMouseEnter={() => setHoveredByte(i)}
                  onMouseLeave={() => setHoveredByte(null)}
                  style={{
                    width: 86,
                    border: `3px solid ${isSelected ? b.color : isHovered ? b.color : 'rgba(254,252,232,0.15)'}`,
                    background: isSelected ? `${b.color}20` : 'rgba(254,252,232,0.04)',
                    padding: '10px 8px',
                    cursor: 'pointer',
                    transition: 'all 0.15s',
                    opacity: isBuilt ? 1 : 0.15,
                    transform: isSelected ? 'translateY(-3px)' : 'none',
                    boxShadow: isSelected ? `0 4px 12px ${b.color}40` : 'none',
                  }}
                >
                  <div style={{ fontFamily: "'Space Mono', monospace", fontSize: '0.55rem', opacity: 0.4, marginBottom: 4 }}>
                    Byte {b.offset}
                  </div>
                  <div style={{ fontFamily: "'Space Mono', monospace", fontSize: '1.1rem', fontWeight: 700, color: b.color, marginBottom: 2 }}>
                    0x{b.hex}
                  </div>
                  <div style={{ fontFamily: "'Space Mono', monospace", fontSize: '0.55rem', opacity: 0.5, letterSpacing: '0.5px' }}>
                    {b.name.length > 9 ? b.name.slice(0, 9) : b.name}
                  </div>
                </div>
              );
            })}
          </div>

          {/* Bit-level view */}
          {activeByteDef && (
            <div
              style={{
                background: 'rgba(254,252,232,0.04)',
                border: `2px solid ${activeByteDef.color}40`,
                padding: '14px 18px',
              }}
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 10 }}>
                <span style={{ fontFamily: "'Space Mono', monospace", fontSize: '0.65rem', fontWeight: 700, color: activeByteDef.color, textTransform: 'uppercase', letterSpacing: '0.08em' }}>
                  {activeByteDef.desc}
                </span>
              </div>
              {/* Bit display */}
              <div style={{ display: 'flex', gap: 3, marginBottom: 10 }}>
                {activeByteDef.bits.split('').map((bit, bi) => (
                  <div
                    key={bi}
                    style={{
                      width: 32,
                      height: 32,
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      border: `2px solid ${bit === '1' ? activeByteDef.color : 'rgba(254,252,232,0.12)'}`,
                      background: bit === '1' ? `${activeByteDef.color}30` : 'transparent',
                      fontFamily: "'Space Mono', monospace",
                      fontSize: '0.85rem',
                      fontWeight: 700,
                      color: bit === '1' ? activeByteDef.color : 'rgba(254,252,232,0.25)',
                    }}
                  >
                    {bit}
                  </div>
                ))}
                <div style={{ fontFamily: "'Space Mono', monospace", fontSize: '0.65rem', opacity: 0.3, display: 'flex', alignItems: 'center', marginLeft: 8 }}>
                  MSB ← → LSB
                </div>
              </div>
              <p style={{ fontSize: '0.78rem', opacity: 0.6, lineHeight: 1.55, margin: 0 }}>
                {activeByteDef.detail}
              </p>
            </div>
          )}

          {!activeByteDef && (
            <div style={{ padding: '20px 0', opacity: 0.3, fontFamily: "'Space Mono', monospace", fontSize: '0.7rem' }}>
              Click or hover a byte to inspect bit-level detail →
            </div>
          )}
        </div>

        {/* Right: BLE Params */}
        <div
          style={{
            background: 'rgba(254,252,232,0.04)',
            border: '3px solid rgba(254,252,232,0.15)',
            padding: 22,
          }}
        >
          <h3 style={{ fontWeight: 700, marginBottom: 16, fontSize: '0.95rem' }}>BLE Config</h3>
          <div style={{ fontFamily: "'Space Mono', monospace", fontSize: '0.72rem', lineHeight: 2.2 }}>
            {[
              ['Service UUID', '0000BEEF-…9B34FB'],
              ['Mfr ID', '0x1234'],
              ['TX Power', 'High'],
              ['Burst', '10 × 1s'],
              ['Chunk Delay', '200ms'],
              ['Connectable', 'false'],
              ['Dedup TTL', '5 min'],
              ['Max Age', '10 min'],
            ].map(([k, v]) => (
              <div key={k} style={{ display: 'flex', justifyContent: 'space-between', borderBottom: '1px solid rgba(254,252,232,0.08)', padding: '2px 0' }}>
                <span style={{ opacity: 0.45, fontSize: '0.68rem' }}>{k}</span>
                <span style={{ color: '#3B82F6', fontWeight: 600 }}>{v}</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* ---- 6 Emergency Types ---- */}
      <div style={{ marginBottom: 32 }}>
        <h3 style={{ fontWeight: 700, marginBottom: 16, fontSize: '1.05rem' }}>6 Emergency Categories</h3>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(6, 1fr)', gap: 10 }}>
          {SOS_TYPES.map((t, i) => {
            const active = activeSosType === i;
            return (
              <div
                key={t.code}
                onClick={() => setActiveSosType(i)}
                style={{
                  background: active ? `${t.color}20` : 'rgba(254,252,232,0.04)',
                  border: `3px solid ${active ? t.color : 'rgba(254,252,232,0.12)'}`,
                  padding: '14px 10px',
                  textAlign: 'center',
                  cursor: 'pointer',
                  transition: 'all 0.15s',
                  transform: active ? 'translateY(-2px)' : 'none',
                  boxShadow: active ? `0 4px 16px ${t.color}30` : 'none',
                }}
              >
                <div style={{ fontSize: '1.8rem', marginBottom: 6 }}>{t.icon}</div>
                <div style={{ fontWeight: 700, fontSize: '0.82rem', marginBottom: 3, color: active ? t.color : 'inherit' }}>{t.name}</div>
                <div style={{ fontFamily: "'Space Mono', monospace", fontSize: '0.6rem', opacity: 0.5 }}>{t.code}</div>
              </div>
            );
          })}
        </div>
        {/* active SOS detail */}
        <div
          style={{
            marginTop: 12,
            padding: '12px 18px',
            borderLeft: `4px solid ${SOS_TYPES[activeSosType].color}`,
            background: 'rgba(254,252,232,0.04)',
            display: 'flex',
            alignItems: 'center',
            gap: 14,
          }}
        >
          <span style={{ fontSize: '1.4rem' }}>{SOS_TYPES[activeSosType].icon}</span>
          <div>
            <div style={{ fontWeight: 700, fontSize: '0.85rem', color: SOS_TYPES[activeSosType].color }}>
              {SOS_TYPES[activeSosType].name}
            </div>
            <div style={{ fontSize: '0.78rem', opacity: 0.55, marginTop: 2 }}>
              {SOS_TYPES[activeSosType].desc}
            </div>
          </div>
          <div style={{ marginLeft: 'auto', fontFamily: "'Space Mono', monospace", fontSize: '0.65rem', opacity: 0.35 }}>
            flags = 0x{((activeSosType << 1) | 1).toString(16).padStart(2, '0').toUpperCase()}
          </div>
        </div>
      </div>

      {/* ---- Relay Pipeline ---- */}
      <div>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 16 }}>
          <h3 style={{ fontWeight: 700, margin: 0, fontSize: '1.05rem' }}>Mesh Relay Pipeline</h3>
          <button
            onClick={runRelay}
            style={{
              padding: '6px 14px',
              border: '2px solid currentColor',
              boxShadow: '3px 3px 0 currentColor',
              background: 'transparent',
              color: relayStep >= 0 ? 'rgba(254,252,232,0.3)' : '#10B981',
              fontFamily: "'Space Mono', monospace",
              fontSize: '0.62rem',
              fontWeight: 700,
              letterSpacing: '0.06em',
              textTransform: 'uppercase' as const,
              cursor: relayStep >= 0 ? 'default' : 'pointer',
            }}
          >
            ▶ Run Pipeline
          </button>
        </div>

        <div style={{ display: 'flex', gap: 0, overflowX: 'auto' }}>
          {RELAY_STEPS.map((step, i) => {
            const isPast = relayStep >= i;
            const isCurrent = relayStep === i;
            return (
              <div key={i} style={{ display: 'flex', alignItems: 'stretch', flexShrink: 0 }}>
                <div
                  style={{
                    width: 130,
                    border: `3px solid ${isCurrent ? step.color : isPast ? `${step.color}80` : 'rgba(254,252,232,0.1)'}`,
                    background: isCurrent ? `${step.color}20` : isPast ? `${step.color}08` : 'rgba(254,252,232,0.02)',
                    padding: '14px 12px',
                    textAlign: 'center',
                    transition: 'all 0.3s',
                    transform: isCurrent ? 'scale(1.04)' : 'none',
                    boxShadow: isCurrent ? `0 0 20px ${step.color}30` : 'none',
                    position: 'relative',
                  }}
                >
                  {/* Progress dot */}
                  {isPast && (
                    <div
                      style={{
                        position: 'absolute',
                        top: 6,
                        right: 6,
                        width: 8,
                        height: 8,
                        borderRadius: '50%',
                        background: step.color,
                        boxShadow: isCurrent ? `0 0 8px ${step.color}` : 'none',
                      }}
                    />
                  )}
                  <div style={{ fontSize: '1.3rem', marginBottom: 6 }}>{step.icon}</div>
                  <div
                    style={{
                      fontWeight: 700,
                      fontSize: '0.75rem',
                      marginBottom: 4,
                      color: isPast ? step.color : 'rgba(254,252,232,0.4)',
                      transition: 'color 0.3s',
                    }}
                  >
                    {step.label}
                  </div>
                  <div
                    style={{
                      fontFamily: "'Space Mono', monospace",
                      fontSize: '0.55rem',
                      opacity: isPast ? 0.6 : 0.2,
                      lineHeight: 1.45,
                      transition: 'opacity 0.3s',
                    }}
                  >
                    {step.detail}
                  </div>
                </div>
                {i < RELAY_STEPS.length - 1 && (
                  <div
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      padding: '0 4px',
                      fontFamily: "'Space Mono', monospace",
                      fontSize: '1rem',
                      fontWeight: 700,
                      color: relayStep > i ? RELAY_STEPS[i + 1].color : 'rgba(254,252,232,0.1)',
                      transition: 'color 0.3s',
                    }}
                  >
                    →
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
