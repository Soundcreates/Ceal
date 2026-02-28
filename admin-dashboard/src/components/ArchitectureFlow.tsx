import { useCallback, useMemo } from 'react';
import {
  ReactFlow,
  Background,
  type Node,
  type Edge,
  type NodeTypes,
  Handle,
  Position,
  MarkerType,
  ConnectionLineType,
  type NodeProps,
} from '@xyflow/react';
import '@xyflow/react/dist/style.css';

/* ================================================================== */
/*  Architecture Diagram — React Flow                                   */
/*  NB styled interactive system overview                               */
/* ================================================================== */

/* ---------- Custom Node Component ---------- */
function ArchNode({ data }: NodeProps) {
  const d = data as {
    label: string;
    sublabel?: string;
    icon: string;
    color: string;
    items?: string[];
    wide?: boolean;
  };

  return (
    <div
      style={{
        background: '#FEFCE8',
        border: `3px solid ${d.color}`,
        boxShadow: `5px 5px 0 ${d.color}`,
        padding: d.items ? '16px 20px' : '12px 18px',
        minWidth: d.wide ? 220 : 160,
        fontFamily: "'Space Grotesk', sans-serif",
        position: 'relative',
      }}
    >
      <Handle type="target" position={Position.Top} style={{ background: d.color, width: 8, height: 8, border: '2px solid #000' }} />
      <Handle type="target" position={Position.Left} id="left" style={{ background: d.color, width: 8, height: 8, border: '2px solid #000' }} />
      <Handle type="source" position={Position.Bottom} style={{ background: d.color, width: 8, height: 8, border: '2px solid #000' }} />
      <Handle type="source" position={Position.Right} id="right" style={{ background: d.color, width: 8, height: 8, border: '2px solid #000' }} />

      {/* header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: d.items ? 10 : 0 }}>
        <span style={{ fontSize: '1.3rem' }}>{d.icon}</span>
        <div>
          <div style={{ fontWeight: 700, fontSize: '0.85rem', color: '#000', lineHeight: 1.2 }}>{d.label}</div>
          {d.sublabel && (
            <div style={{ fontFamily: "'Space Mono', monospace", fontSize: '0.58rem', color: d.color, fontWeight: 700, letterSpacing: '0.08em', textTransform: 'uppercase', marginTop: 2 }}>
              {d.sublabel}
            </div>
          )}
        </div>
      </div>

      {/* items list */}
      {d.items && (
        <div style={{ borderTop: '2px solid rgba(0,0,0,0.1)', paddingTop: 8, marginTop: 4 }}>
          {d.items.map((item: string) => (
            <div key={item} style={{ fontFamily: "'Space Mono', monospace", fontSize: '0.6rem', color: 'rgba(0,0,0,0.6)', lineHeight: 1.8, paddingLeft: 4 }}>
              ▸ {item}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

/* ---------- Node types registration ---------- */
const nodeTypes: NodeTypes = {
  arch: ArchNode,
};

/* ---------- Main Component ---------- */
export default function ArchitectureFlow() {
  const nodes: Node[] = useMemo(
    () => [
      // ---- Victim Device ----
      {
        id: 'victim',
        type: 'arch',
        position: { x: 40, y: 20 },
        data: {
          label: 'Victim Device',
          sublabel: 'Flutter App',
          icon: 'SOS',
          color: '#EF4444',
          items: ['Volume button SOS', 'BLE Broadcaster', 'Offline SQLite queue', 'Direct SMS fallback'],
        },
      },

      // ---- BLE Mesh ----
      {
        id: 'mesh',
        type: 'arch',
        position: { x: 340, y: 30 },
        data: {
          label: 'BLE Mesh Network',
          sublabel: '0xBEEF · 10-byte packets',
          icon: 'BLE',
          color: '#3B82F6',
          items: ['CRC8 integrity check', 'Dedup (5min TTL)', 'Self-loop prevention', 'Multi-hop relay'],
          wide: true,
        },
      },

      // ---- Relay Devices ----
      {
        id: 'relay',
        type: 'arch',
        position: { x: 660, y: 20 },
        data: {
          label: 'Relay Devices',
          sublabel: 'N nearby phones',
          icon: 'DEV',
          color: '#10B981',
          items: ['Always-on BLE scanner', 'GPS attachment', 'Re-broadcast + jitter', 'Connectivity worker'],
        },
      },

      // ---- Backend Server ----
      {
        id: 'backend',
        type: 'arch',
        position: { x: 400, y: 280 },
        data: {
          label: 'Backend Server',
          sublabel: 'Node.js · Express · TypeScript',
          icon: 'API',
          color: '#F59E0B',
          items: ['SOS Ingest API', 'Victim resolver', 'Aadhaar ZK verifier', 'JWT auth + rate limit'],
          wide: true,
        },
      },

      // ---- Twilio SMS ----
      {
        id: 'twilio',
        type: 'arch',
        position: { x: 100, y: 300 },
        data: {
          label: 'Twilio SMS',
          sublabel: 'Dual-path delivery',
          icon: 'SMS',
          color: '#10B981',
          items: ['Victim name + GPS', 'Google Maps link', 'SOS type label'],
        },
      },

      // ---- PostgreSQL ----
      {
        id: 'db',
        type: 'arch',
        position: { x: 730, y: 290 },
        data: {
          label: 'PostgreSQL',
          sublabel: 'Neon · SSL · 7 tables',
          icon: 'DB',
          color: '#8B5CF6',
          items: ['users', 'sos_events', 'emergency_contacts', 'medical_profiles'],
        },
      },

      // ---- Admin Dashboard ----
      {
        id: 'admin',
        type: 'arch',
        position: { x: 430, y: 500 },
        data: {
          label: 'Admin Dashboard',
          sublabel: 'React · Vite · Live Polling',
          icon: 'ADM',
          color: '#8B5CF6',
          items: ['Real-time events', 'User management', 'KYC oversight', 'Status workflows'],
          wide: true,
        },
      },

      // ---- Emergency Contacts ----
      {
        id: 'contacts',
        type: 'arch',
        position: { x: 60, y: 500 },
        data: {
          label: 'Emergency Contacts',
          sublabel: 'Up to 10 per user',
          icon: 'CON',
          color: '#EF4444',
        },
      },
    ],
    []
  );

  const edges: Edge[] = useMemo(
    () => [
      // Victim → BLE Mesh
      {
        id: 'e-victim-mesh',
        source: 'victim',
        target: 'mesh',
        sourceHandle: 'right',
        targetHandle: 'left',
        label: 'BLE broadcast',
        animated: true,
        style: { stroke: '#EF4444', strokeWidth: 2.5 },
        labelStyle: { fontFamily: "'Space Mono', monospace", fontSize: 9, fontWeight: 700, fill: '#EF4444' },
        markerEnd: { type: MarkerType.ArrowClosed, color: '#EF4444' },
      },
      // BLE Mesh → Relay Devices
      {
        id: 'e-mesh-relay',
        source: 'mesh',
        target: 'relay',
        sourceHandle: 'right',
        targetHandle: 'left',
        label: 'Multi-hop relay',
        animated: true,
        style: { stroke: '#3B82F6', strokeWidth: 2.5 },
        labelStyle: { fontFamily: "'Space Mono', monospace", fontSize: 9, fontWeight: 700, fill: '#3B82F6' },
        markerEnd: { type: MarkerType.ArrowClosed, color: '#3B82F6' },
      },
      // Relay → Backend
      {
        id: 'e-relay-backend',
        source: 'relay',
        target: 'backend',
        label: 'HTTPS POST /sos/ingest',
        animated: true,
        style: { stroke: '#10B981', strokeWidth: 2 },
        labelStyle: { fontFamily: "'Space Mono', monospace", fontSize: 9, fontWeight: 700, fill: '#10B981' },
        markerEnd: { type: MarkerType.ArrowClosed, color: '#10B981' },
      },
      // Backend → Twilio
      {
        id: 'e-backend-twilio',
        source: 'backend',
        target: 'twilio',
        targetHandle: 'right',
        sourceHandle: 'left',
        label: 'Fire SMS',
        style: { stroke: '#10B981', strokeWidth: 2 },
        labelStyle: { fontFamily: "'Space Mono', monospace", fontSize: 9, fontWeight: 700, fill: '#10B981' },
        markerEnd: { type: MarkerType.ArrowClosed, color: '#10B981' },
      },
      // Twilio → Emergency Contacts
      {
        id: 'e-twilio-contacts',
        source: 'twilio',
        target: 'contacts',
        label: 'SMS alert',
        style: { stroke: '#EF4444', strokeWidth: 2 },
        labelStyle: { fontFamily: "'Space Mono', monospace", fontSize: 9, fontWeight: 700, fill: '#EF4444' },
        markerEnd: { type: MarkerType.ArrowClosed, color: '#EF4444' },
      },
      // Backend → PostgreSQL
      {
        id: 'e-backend-db',
        source: 'backend',
        target: 'db',
        sourceHandle: 'right',
        targetHandle: 'left',
        label: 'Read / Write',
        style: { stroke: '#8B5CF6', strokeWidth: 2 },
        labelStyle: { fontFamily: "'Space Mono', monospace", fontSize: 9, fontWeight: 700, fill: '#8B5CF6' },
        markerEnd: { type: MarkerType.ArrowClosed, color: '#8B5CF6' },
      },
      // Backend → Admin Dashboard
      {
        id: 'e-backend-admin',
        source: 'backend',
        target: 'admin',
        label: 'REST API + Polling',
        style: { stroke: '#F59E0B', strokeWidth: 2 },
        labelStyle: { fontFamily: "'Space Mono', monospace", fontSize: 9, fontWeight: 700, fill: '#F59E0B' },
        markerEnd: { type: MarkerType.ArrowClosed, color: '#F59E0B' },
      },
      // Victim → Twilio (direct SMS fallback)
      {
        id: 'e-victim-sms',
        source: 'victim',
        target: 'twilio',
        label: 'Direct SMS (Android)',
        style: { stroke: '#EF4444', strokeWidth: 1.5, strokeDasharray: '6 4' },
        labelStyle: { fontFamily: "'Space Mono', monospace", fontSize: 8, fontWeight: 700, fill: '#EF4444' },
        markerEnd: { type: MarkerType.ArrowClosed, color: '#EF4444' },
      },
    ],
    []
  );

  const onInit = useCallback((instance: any) => {
    // fit view after mount
    setTimeout(() => instance.fitView({ padding: 0.15 }), 100);
  }, []);

  return (
    <div
      style={{
        width: '100%',
        height: 640,
        border: '3px solid var(--nb-ink)',
        boxShadow: '6px 6px 0 var(--nb-ink)',
        background: '#FEFCE8',
        position: 'relative',
      }}
    >
      <ReactFlow
        nodes={nodes}
        edges={edges}
        nodeTypes={nodeTypes}
        onInit={onInit}
        connectionLineType={ConnectionLineType.SmoothStep}
        fitView
        fitViewOptions={{ padding: 0.15 }}
        proOptions={{ hideAttribution: true }}
        nodesDraggable={true}
        nodesConnectable={false}
        panOnDrag={true}
        zoomOnScroll={true}
        minZoom={0.4}
        maxZoom={1.5}
        defaultEdgeOptions={{ type: 'smoothstep' }}
      >
        <Background color="rgba(0,0,0,0.06)" gap={24} size={1} />
      </ReactFlow>

      {/* Corner badge */}
      <div
        style={{
          position: 'absolute',
          top: 10,
          right: 12,
          fontFamily: "'Space Mono', monospace",
          fontSize: '0.58rem',
          fontWeight: 700,
          color: 'rgba(0,0,0,0.3)',
          letterSpacing: '0.1em',
          textTransform: 'uppercase',
          pointerEvents: 'none',
        }}
      >
        Drag nodes · Scroll to zoom
      </div>
    </div>
  );
}
