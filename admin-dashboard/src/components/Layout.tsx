import { Outlet } from 'react-router-dom';
import Sidebar from './Sidebar';
import SosAlertPopup from './SosAlertPopup';
import { useSosAlerts } from '../hooks/useSosAlerts';

export default function Layout() {
  const { alerts, dismiss, dismissAll } = useSosAlerts();

  return (
    <div className="layout">
      <Sidebar />
      <main className="layout__main">
        <Outlet />
      </main>
      <SosAlertPopup alerts={alerts} onDismiss={dismiss} onDismissAll={dismissAll} />
    </div>
  );
}
