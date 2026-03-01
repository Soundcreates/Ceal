import React from 'react';
import ReactDOM from 'react-dom/client';
import {
  createBrowserRouter,
  RouterProvider,
} from 'react-router-dom';
import App from './App';
import './index.css';

import Landing from './pages/Landing';
import Layout from './components/Layout';
import Dashboard from './pages/Dashboard';
import Events from './pages/Events';
import EventDetail from './pages/EventDetail';
import Users from './pages/Users';
import UserDetail from './pages/UserDetail';
import Settings from './pages/Settings';

const router = createBrowserRouter([
  {
    path: '/',
    element: <Landing />,
  },
  {
    path: '/admin',
    element: <Layout />,
    children: [
      { index: true, element: <Dashboard /> },
      { path: 'dashboard', element: <Dashboard /> },
      { path: 'events', element: <Events /> },
      { path: 'events/:id', element: <EventDetail /> },
      { path: 'users', element: <Users /> },
      { path: 'users/:id', element: <UserDetail /> },
      { path: 'settings', element: <Settings /> },
    ],
  },
]);

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <RouterProvider router={router} />
  </React.StrictMode>,
);
