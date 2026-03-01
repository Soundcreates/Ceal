import { NavLink } from 'react-router-dom';

const NAV = [
  { to: '/admin/dashboard',         icon: '◉', label: 'Dashboard' },
  { to: '/admin/events',            icon: '!', label: 'SOS Events' },
  { to: '/admin/disaster-reports',  icon: '⚠', label: 'Disaster Reports' },
  { to: '/admin/users',             icon: '◈', label: 'Users' },
  { to: '/admin/settings',          icon: '*', label: 'Settings' },
];

export default function Sidebar() {
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
        CEAL v1.0 &middot; BLE Mesh SOS
      </div>
    </aside>
  );
}
