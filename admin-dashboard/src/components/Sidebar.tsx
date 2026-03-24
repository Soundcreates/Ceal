import { NavLink, useNavigate } from 'react-router-dom';
import { clearStoredToken } from '../auth';

const NAV = [
  { to: '/admin/dashboard',         icon: '◉', label: 'Dashboard' },
  { to: '/admin/events',            icon: '!', label: 'SOS Events' },
  { to: '/admin/disaster-reports',  icon: '⚠', label: 'Disaster Reports' },
  { to: '/admin/users',             icon: '◈', label: 'Users' },
  { to: '/admin/settings',          icon: '*', label: 'Settings' },
];

export default function Sidebar() {
  const navigate = useNavigate();

  return (
    <aside className="layout__sidebar">
      <div className="sidebar__brand">
        <h1>CEAL</h1>
        <span>Admin Console</span>
      </div>

      <nav className="sidebar__nav">
        {NAV.map(({ to, icon, label }) => (
          <NavLink
            key={to}
            to={to}
            className={({ isActive }) =>
              `sidebar__link${isActive ? ' sidebar__link--active' : ''}`
            }
          >
            <span style={{ fontSize: '1.1rem' }}>{icon}</span>
            {label}
          </NavLink>
        ))}
      </nav>

      <div className="sidebar__footer">
        <button
          className="nb-btn nb-btn--ghost nb-btn--sm"
          type="button"
          onClick={() => {
            clearStoredToken();
            navigate('/login', { replace: true });
          }}
        >
          Logout
        </button>
        <div style={{ marginTop: 12 }}>CEAL v1.0 &middot; BLE Mesh SOS</div>
      </div>
    </aside>
  );
}
