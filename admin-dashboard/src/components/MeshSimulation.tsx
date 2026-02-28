import { useEffect, useRef, useState, useCallback } from 'react';

/* ================================================================== */
/*  BLE Mesh SOS Simulation                                            */
/*  Animated canvas showing SOS packets hopping through a mesh network */
/* ================================================================== */

interface Device {
  id: number;
  x: number;
  y: number;
  role: 'victim' | 'relay' | 'gateway';
  label: string;
  pulsePhase: number;
  reached: boolean;
  reachedAt: number;
  ringRadius: number;
}

interface Packet {
  id: number;
  fromId: number;
  toId: number;
  progress: number; // 0→1
  born: number;
}

interface Ripple {
  x: number;
  y: number;
  radius: number;
  maxRadius: number;
  opacity: number;
  color: string;
}

/* ----- constants ----- */
const COLORS = {
  bg: '#000000',
  victim: '#EF4444',
  relay: '#3B82F6',
  relayReached: '#10B981',
  gateway: '#8B5CF6',
  packet: '#F59E0B',
  link: 'rgba(255,255,255,0.06)',
  linkActive: 'rgba(245,158,11,0.35)',
  text: 'rgba(254,252,232,0.7)',
  textDim: 'rgba(254,252,232,0.3)',
  gridDot: 'rgba(254,252,232,0.04)',
  sms: '#10B981',
};

const PACKET_SPEED = 0.012;
const RELAY_DELAY_MS = 600;

export default function MeshSimulation() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const animRef = useRef<number>(0);
  const stateRef = useRef<{
    devices: Device[];
    packets: Packet[];
    ripples: Ripple[];
    edges: [number, number][];
    phase: 'idle' | 'broadcasting' | 'relaying' | 'uploading' | 'sms' | 'done';
    phaseStart: number;
    nextPacketId: number;
    smsParticles: { x: number; y: number; vx: number; vy: number; life: number; maxLife: number }[];
    statusText: string;
    statusColor: string;
    time: number;
  } | null>(null);
  const [canvasSize, setCanvasSize] = useState({ w: 1120, h: 560 });
  const [, setTick] = useState(0); // force re-render for overlay

  /* ----- build the mesh layout ----- */
  const buildState = useCallback((w: number, h: number) => {
    const cx = w / 2;
    const cy = h / 2;
    const r1 = Math.min(w, h) * 0.28; // inner ring
    const r2 = Math.min(w, h) * 0.44; // outer ring

    const devices: Device[] = [
      // victim at center
      { id: 0, x: cx, y: cy, role: 'victim', label: 'VICTIM', pulsePhase: 0, reached: true, reachedAt: 0, ringRadius: 0 },
      // inner ring: 5 relays
      ...Array.from({ length: 5 }, (_, i) => {
        const a = (i / 5) * Math.PI * 2 - Math.PI / 2;
        return {
          id: i + 1,
          x: cx + Math.cos(a) * r1,
          y: cy + Math.sin(a) * r1,
          role: 'relay' as const,
          label: `RELAY ${i + 1}`,
          pulsePhase: i * 0.4,
          reached: false,
          reachedAt: 0,
          ringRadius: 0,
        };
      }),
      // outer ring: 6 relays + 2 gateways
      ...Array.from({ length: 8 }, (_, i) => {
        const a = (i / 8) * Math.PI * 2 - Math.PI / 4;
        const isGateway = i === 2 || i === 6;
        return {
          id: i + 6,
          x: cx + Math.cos(a) * r2,
          y: cy + Math.sin(a) * r2,
          role: isGateway ? 'gateway' as const : 'relay' as const,
          label: isGateway ? (i === 2 ? 'GATEWAY 1' : 'GATEWAY 2') : `RELAY ${i + 6}`,
          pulsePhase: i * 0.3,
          reached: false,
          reachedAt: 0,
          ringRadius: 0,
        };
      }),
    ];

    // edges: victim → inner ring, inner ring → outer ring (with some cross connections)
    const edges: [number, number][] = [];
    // victim → all inner
    for (let i = 1; i <= 5; i++) edges.push([0, i]);
    // inner ring cross-links
    for (let i = 1; i <= 5; i++) edges.push([i, i === 5 ? 1 : i + 1]);
    // inner → outer
    edges.push([1, 6]); edges.push([1, 7]);
    edges.push([2, 7]); edges.push([2, 8]);
    edges.push([3, 8]); edges.push([3, 9]);
    edges.push([4, 9]); edges.push([4, 10]);
    edges.push([5, 10]); edges.push([5, 11]);
    edges.push([5, 6]); edges.push([1, 13]);
    // outer ring connections
    for (let i = 6; i <= 13; i++) edges.push([i, i === 13 ? 6 : i + 1]);

    return {
      devices,
      packets: [] as Packet[],
      ripples: [] as Ripple[],
      edges,
      phase: 'idle' as const,
      phaseStart: 0,
      nextPacketId: 1,
      smsParticles: [] as { x: number; y: number; vx: number; vy: number; life: number; maxLife: number }[],
      statusText: 'Tap victim to trigger SOS',
      statusColor: COLORS.textDim,
      time: 0,
    };
  }, []);

  /* ----- resize observer ----- */
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const ro = new ResizeObserver((entries) => {
      const { width } = entries[0].contentRect;
      const h = Math.max(400, Math.min(560, width * 0.5));
      setCanvasSize({ w: width, h });
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  /* ----- init state when canvas size changes ----- */
  useEffect(() => {
    stateRef.current = buildState(canvasSize.w, canvasSize.h);
  }, [canvasSize, buildState]);

  /* ----- start simulation on click ----- */
  const startSim = useCallback(() => {
    const s = stateRef.current;
    if (!s || s.phase !== 'idle') return;

    // reset all devices
    s.devices.forEach((d) => {
      d.reached = d.role === 'victim';
      d.reachedAt = 0;
      d.ringRadius = 0;
    });
    s.packets = [];
    s.ripples = [];
    s.smsParticles = [];
    s.phase = 'broadcasting';
    s.phaseStart = s.time;
    s.statusText = 'SOS TRIGGERED — Broadcasting 10-byte V2 packet...';
    s.statusColor = COLORS.victim;

    // create ripple at victim
    const v = s.devices[0];
    s.ripples.push({ x: v.x, y: v.y, radius: 0, maxRadius: 160, opacity: 1, color: COLORS.victim });

    // send packets from victim to inner ring
    for (const [from, to] of s.edges) {
      if (from === 0) {
        s.packets.push({ id: s.nextPacketId++, fromId: from, toId: to, progress: 0, born: s.time });
      }
    }
  }, []);

  /* ----- main animation loop ----- */
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    let running = true;
    let lastOverlayUpdate = 0;

    const draw = (now: number) => {
      if (!running) return;
      const s = stateRef.current;
      if (!s) { animRef.current = requestAnimationFrame(draw); return; }

      s.time = now;
      const dpr = window.devicePixelRatio || 1;
      const W = canvasSize.w;
      const H = canvasSize.h;
      canvas.width = W * dpr;
      canvas.height = H * dpr;
      canvas.style.width = `${W}px`;
      canvas.style.height = `${H}px`;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

      // background
      ctx.fillStyle = COLORS.bg;
      ctx.fillRect(0, 0, W, H);

      // subtle dot grid
      ctx.fillStyle = COLORS.gridDot;
      for (let x = 20; x < W; x += 30) for (let y = 20; y < H; y += 30) {
        ctx.beginPath(); ctx.arc(x, y, 1, 0, Math.PI * 2); ctx.fill();
      }

      /* --- EDGES --- */
      for (const [a, b] of s.edges) {
        const dA = s.devices[a];
        const dB = s.devices[b];
        if (!dA || !dB) continue;
        const active = dA.reached && dB.reached;
        ctx.beginPath();
        ctx.moveTo(dA.x, dA.y);
        ctx.lineTo(dB.x, dB.y);
        ctx.strokeStyle = active ? COLORS.linkActive : COLORS.link;
        ctx.lineWidth = active ? 1.5 : 0.8;
        if (!active) ctx.setLineDash([4, 6]);
        else ctx.setLineDash([]);
        ctx.stroke();
        ctx.setLineDash([]);
      }

      /* --- RIPPLES --- */
      s.ripples = s.ripples.filter((r) => r.opacity > 0.01);
      for (const r of s.ripples) {
        r.radius += 1.2;
        r.opacity = Math.max(0, 1 - r.radius / r.maxRadius);
        ctx.beginPath();
        ctx.arc(r.x, r.y, r.radius, 0, Math.PI * 2);
        ctx.strokeStyle = r.color;
        ctx.globalAlpha = r.opacity * 0.4;
        ctx.lineWidth = 2;
        ctx.stroke();
        ctx.globalAlpha = 1;
      }

      /* --- PACKETS (move & draw) --- */
      const newReached: number[] = [];
      s.packets = s.packets.filter((p) => {
        p.progress += PACKET_SPEED;
        if (p.progress >= 1) {
          // arrived
          const target = s.devices[p.toId];
          if (target && !target.reached) {
            target.reached = true;
            target.reachedAt = now;
            target.ringRadius = 0;
            newReached.push(p.toId);
            s.ripples.push({
              x: target.x, y: target.y,
              radius: 0, maxRadius: 100,
              opacity: 1,
              color: target.role === 'gateway' ? COLORS.gateway : COLORS.relayReached,
            });
          }
          return false;
        }
        // draw packet
        const from = s.devices[p.fromId];
        const to = s.devices[p.toId];
        if (!from || !to) return false;
        const px = from.x + (to.x - from.x) * p.progress;
        const py = from.y + (to.y - from.y) * p.progress;

        // glow
        const grd = ctx.createRadialGradient(px, py, 0, px, py, 12);
        grd.addColorStop(0, COLORS.packet);
        grd.addColorStop(1, 'transparent');
        ctx.fillStyle = grd;
        ctx.globalAlpha = 0.6;
        ctx.fillRect(px - 12, py - 12, 24, 24);
        ctx.globalAlpha = 1;

        // core
        ctx.beginPath();
        ctx.arc(px, py, 4, 0, Math.PI * 2);
        ctx.fillStyle = COLORS.packet;
        ctx.fill();
        ctx.strokeStyle = '#fff';
        ctx.lineWidth = 1;
        ctx.stroke();

        return true;
      });

      // spawn relay packets from newly reached devices
      for (const id of newReached) {
        setTimeout(() => {
          const ss = stateRef.current;
          if (!ss) return;
          for (const [from, to] of ss.edges) {
            if (from === id && !ss.devices[to]?.reached) {
              ss.packets.push({ id: ss.nextPacketId++, fromId: from, toId: to, progress: 0, born: ss.time });
            }
            if (to === id && !ss.devices[from]?.reached) {
              ss.packets.push({ id: ss.nextPacketId++, fromId: id, toId: from, progress: 0, born: ss.time });
            }
          }
        }, RELAY_DELAY_MS);
      }

      /* --- update phase status --- */
      const allReached = s.devices.every((d) => d.reached);
      const gatewaysReached = s.devices.filter((d) => d.role === 'gateway' && d.reached).length;
      if (s.phase === 'broadcasting' && s.devices.filter((d) => d.reached).length > 1) {
        s.phase = 'relaying';
        s.statusText = 'BLE mesh relaying — CRC8 validated, packets hopping...';
        s.statusColor = COLORS.relay;
      }
      if (s.phase === 'relaying' && gatewaysReached > 0) {
        s.phase = 'uploading';
        s.statusText = 'Gateway reached — uploading to backend via HTTPS...';
        s.statusColor = COLORS.gateway;
      }
      if (s.phase === 'uploading' && allReached && s.packets.length === 0) {
        s.phase = 'sms';
        s.phaseStart = now;
        s.statusText = 'Twilio SMS firing to emergency contacts...';
        s.statusColor = COLORS.sms;
        // spawn SMS particles from gateways
        for (const d of s.devices) {
          if (d.role === 'gateway') {
            for (let i = 0; i < 12; i++) {
              const angle = (i / 12) * Math.PI * 2;
              s.smsParticles.push({
                x: d.x, y: d.y,
                vx: Math.cos(angle) * (1.5 + Math.random()),
                vy: Math.sin(angle) * (1.5 + Math.random()),
                life: 120 + Math.random() * 60,
                maxLife: 180,
              });
            }
          }
        }
      }
      if (s.phase === 'sms' && now - s.phaseStart > 3000) {
        s.phase = 'done';
        s.statusText = 'Emergency contacts notified — admin dashboard updated';
        s.statusColor = COLORS.sms;
        setTimeout(() => {
          const ss = stateRef.current;
          if (!ss) return;
          ss.phase = 'idle';
          ss.statusText = 'Click victim to trigger SOS again';
          ss.statusColor = COLORS.textDim;
          ss.devices.forEach((d) => { d.reached = d.role === 'victim'; d.ringRadius = 0; });
          ss.ripples = [];
          ss.smsParticles = [];
          setTick((t) => t + 1);
        }, 2500);
      }

      /* --- SMS particles --- */
      s.smsParticles = s.smsParticles.filter((p) => p.life > 0);
      for (const p of s.smsParticles) {
        p.x += p.vx;
        p.y += p.vy;
        p.vx *= 0.985;
        p.vy *= 0.985;
        p.life--;
        const t = p.life / p.maxLife;
        ctx.beginPath();
        ctx.arc(p.x, p.y, 2.5 * t, 0, Math.PI * 2);
        ctx.fillStyle = COLORS.sms;
        ctx.globalAlpha = t * 0.7;
        ctx.fill();
        ctx.globalAlpha = 1;
      }

      /* --- DEVICES --- */
      for (const d of s.devices) {
        const isVictim = d.role === 'victim';
        const isGateway = d.role === 'gateway';

        // device reach ring  
        if (d.reached && d.ringRadius < 30) {
          d.ringRadius += 0.6;
          ctx.beginPath();
          ctx.arc(d.x, d.y, 18 + d.ringRadius, 0, Math.PI * 2);
          const col = isVictim ? COLORS.victim : isGateway ? COLORS.gateway : COLORS.relayReached;
          ctx.strokeStyle = col;
          ctx.globalAlpha = 0.15 * (1 - d.ringRadius / 30);
          ctx.lineWidth = 2;
          ctx.stroke();
          ctx.globalAlpha = 1;
        }

        // ambient pulse  
        const pulse = 1 + 0.08 * Math.sin(now * 0.003 + d.pulsePhase);
        const baseR = isVictim ? 20 : isGateway ? 16 : 12;
        const r = baseR * pulse;

        // glow
        if (d.reached) {
          const col = isVictim ? COLORS.victim : isGateway ? COLORS.gateway : COLORS.relayReached;
          const grd = ctx.createRadialGradient(d.x, d.y, 0, d.x, d.y, r * 2.5);
          grd.addColorStop(0, col);
          grd.addColorStop(1, 'transparent');
          ctx.fillStyle = grd;
          ctx.globalAlpha = 0.15;
          ctx.beginPath();
          ctx.arc(d.x, d.y, r * 2.5, 0, Math.PI * 2);
          ctx.fill();
          ctx.globalAlpha = 1;
        }

        // body
        ctx.beginPath();
        ctx.arc(d.x, d.y, r, 0, Math.PI * 2);
        let fillColor: string;
        if (isVictim) fillColor = COLORS.victim;
        else if (!d.reached) fillColor = 'rgba(254,252,232,0.08)';
        else if (isGateway) fillColor = COLORS.gateway;
        else fillColor = COLORS.relayReached;
        ctx.fillStyle = fillColor;
        ctx.fill();

        // border
        ctx.strokeStyle = d.reached ? '#fff' : 'rgba(254,252,232,0.15)';
        ctx.lineWidth = d.reached ? 2.5 : 1;
        ctx.stroke();

        // icon
        ctx.fillStyle = d.reached || isVictim ? '#fff' : 'rgba(254,252,232,0.25)';
        ctx.font = `${isVictim ? 14 : 10}px sans-serif`;
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(isVictim ? 'SOS' : isGateway ? 'GW' : 'R', d.x, d.y);

        // label
        ctx.fillStyle = d.reached ? 'rgba(254,252,232,0.8)' : 'rgba(254,252,232,0.2)';
        ctx.font = `bold 8px 'Space Mono', monospace`;
        ctx.textAlign = 'center';
        ctx.fillText(d.label, d.x, d.y + r + 14);
      }

      // overlay update throttle  
      if (now - lastOverlayUpdate > 500) {
        lastOverlayUpdate = now;
        setTick((t) => t + 1);
      }

      animRef.current = requestAnimationFrame(draw);
    };

    animRef.current = requestAnimationFrame(draw);
    return () => { running = false; cancelAnimationFrame(animRef.current); };
  }, [canvasSize]);

  const s = stateRef.current;

  return (
    <div ref={containerRef} style={{ position: 'relative', width: '100%' }}>
      {/* Status bar */}
      <div
        style={{
          position: 'absolute',
          top: 12,
          left: 16,
          right: 16,
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          zIndex: 2,
          pointerEvents: 'none',
        }}
      >
        <div
          style={{
            fontFamily: "'Space Mono', monospace",
            fontSize: '0.72rem',
            fontWeight: 700,
            color: s?.statusColor ?? COLORS.textDim,
            letterSpacing: '0.04em',
            textShadow: '0 0 20px rgba(0,0,0,0.8)',
          }}
        >
          {s?.statusText ?? ''}
        </div>
        <div
          style={{
            fontFamily: "'Space Mono', monospace",
            fontSize: '0.62rem',
            color: COLORS.textDim,
            letterSpacing: '0.08em',
            textTransform: 'uppercase',
          }}
        >
          BLE Mesh V2
        </div>
      </div>

      {/* Legend */}
      <div
        style={{
          position: 'absolute',
          bottom: 12,
          left: 16,
          display: 'flex',
          gap: 16,
          zIndex: 2,
          pointerEvents: 'none',
        }}
      >
        {[
          { color: COLORS.victim, label: 'Victim' },
          { color: COLORS.relay, label: 'Relay (idle)' },
          { color: COLORS.relayReached, label: 'Relay (active)' },
          { color: COLORS.gateway, label: 'Gateway' },
          { color: COLORS.packet, label: 'SOS Packet' },
        ].map(({ color, label }) => (
          <div key={label} style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
            <div style={{ width: 8, height: 8, borderRadius: '50%', background: color, border: '1px solid rgba(255,255,255,0.3)' }} />
            <span style={{ fontFamily: "'Space Mono', monospace", fontSize: '0.58rem', color: COLORS.textDim, letterSpacing: '0.04em' }}>
              {label}
            </span>
          </div>
        ))}
      </div>

      {/* Canvas */}
      <canvas
        ref={canvasRef}
        onClick={startSim}
        style={{
          width: '100%',
          height: canvasSize.h,
          cursor: s?.phase === 'idle' ? 'pointer' : 'default',
          border: '3px solid rgba(254,252,232,0.12)',
          display: 'block',
        }}
      />

      {/* Click prompt */}
      {(!s || s.phase === 'idle') && (
        <div
          onClick={startSim}
          style={{
            position: 'absolute',
            bottom: 12,
            right: 16,
            padding: '6px 14px',
            border: '2px solid rgba(254,252,232,0.2)',
            background: 'rgba(0,0,0,0.6)',
            cursor: 'pointer',
            fontFamily: "'Space Mono', monospace",
            fontSize: '0.65rem',
            color: COLORS.victim,
            fontWeight: 700,
            letterSpacing: '0.06em',
            textTransform: 'uppercase',
            zIndex: 2,
          }}
        >
          ▶ Click to simulate SOS
        </div>
      )}
    </div>
  );
}
