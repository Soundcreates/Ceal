import { useState, useEffect, useRef, useCallback } from 'react';
import { fetchEvents, fetchEvent } from '../api/client';
import type { EventDetail } from '../api/types';

const POLL_INTERVAL = 5_000; // 5s
const SEEN_KEY = 'ceal_seen_sos_ids';

/**
 * How recent (in ms) an event must be to trigger a popup on the very first
 * poll.  Events older than this are silently marked as seen so they don't
 * blast the user when the dashboard first loads.
 */
const FIRST_LOAD_RECENCY_MS = 120_000; // 2 minutes

/**
 * Polls for new active/relayed SOS events. When a previously-unseen
 * event is detected, fetches its full detail (including victim profile)
 * and pushes it into the alert queue.
 */
export function useSosAlerts() {
  const [alerts, setAlerts] = useState<EventDetail[]>([]);
  const seenRef = useRef<Set<string>>(new Set());
  const initialLoadDone = useRef(false);

  // Seed the seen-set from localStorage so we don't re-alert on refresh
  useEffect(() => {
    try {
      const stored = localStorage.getItem(SEEN_KEY);
      if (stored) {
        const ids: string[] = JSON.parse(stored);
        ids.forEach((id) => seenRef.current.add(id));
      }
    } catch { /* ignore */ }
  }, []);

  const persistSeen = useCallback(() => {
    try {
      // Keep last 500 IDs to avoid unbounded growth
      const arr = [...seenRef.current].slice(-500);
      localStorage.setItem(SEEN_KEY, JSON.stringify(arr));
    } catch { /* ignore */ }
  }, []);

  const dismiss = useCallback((id: string) => {
    setAlerts((prev) => prev.filter((a) => a.id !== id));
  }, []);

  const dismissAll = useCallback(() => {
    setAlerts([]);
  }, []);

  useEffect(() => {
    let mounted = true;

    const poll = async () => {
      try {
        // Fetch the most recent active + relayed events
        const [active, relayed] = await Promise.all([
          fetchEvents(1, 20, 'active'),
          fetchEvents(1, 20, 'relayed'),
        ]);
        const allEvents = [...active.events, ...relayed.events];

        if (!initialLoadDone.current) {
          // First load: only suppress old events. Recent ones (< 2 min)
          // still get shown so the operator doesn't miss an active SOS.
          const now = Date.now();
          const recentUnseen: typeof allEvents = [];

          for (const e of allEvents) {
            const age = now - new Date(e.timestamp).getTime();
            if (age > FIRST_LOAD_RECENCY_MS || seenRef.current.has(e.id)) {
              seenRef.current.add(e.id);
            } else {
              recentUnseen.push(e);
            }
          }

          initialLoadDone.current = true;
          persistSeen();

          // Fall through so recent events get fetched & shown below
          if (recentUnseen.length === 0) return;

          // Mark recent ones as seen so subsequent polls don't duplicate
          recentUnseen.forEach((e) => seenRef.current.add(e.id));
          persistSeen();

          const details = await Promise.all(
            recentUnseen.map((e) => fetchEvent(e.id).catch(() => null)),
          );
          if (!mounted) return;
          const validDetails = details.filter(Boolean) as EventDetail[];
          if (validDetails.length > 0) {
            setAlerts((prev) => [...validDetails, ...prev]);
          }
          return;
        }

        // Find new events we haven't seen
        const newEvents = allEvents.filter((e) => !seenRef.current.has(e.id));
        if (newEvents.length === 0) return;

        // Mark as seen immediately to avoid duplicate fetches
        newEvents.forEach((e) => seenRef.current.add(e.id));
        persistSeen();

        // Fetch full detail (with victim profile) for each new event
        const details = await Promise.all(
          newEvents.map((e) => fetchEvent(e.id).catch(() => null)),
        );

        if (!mounted) return;

        const validDetails = details.filter(Boolean) as EventDetail[];
        if (validDetails.length > 0) {
          setAlerts((prev) => [...validDetails, ...prev]);
        }
      } catch (err) {
        console.error('[useSosAlerts] Poll failed:', err);
      }
    };

    poll();
    const timer = setInterval(poll, POLL_INTERVAL);

    return () => {
      mounted = false;
      clearInterval(timer);
    };
  }, [persistSeen]);

  return { alerts, dismiss, dismissAll };
}
