import { useState, useEffect, useCallback, useRef } from 'react';

/**
 * Generic async-data hook with auto-refresh.
 */
export function usePolling<T>(
  fetcher: () => Promise<T>,
  intervalMs: number = 0,
  deps: unknown[] = [],
) {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const mountedRef = useRef(true);

  const load = useCallback(async () => {
    try {
      const result = await fetcher();
      if (mountedRef.current) {
        setData(result);
        setError(null);
      }
    } catch (err) {
      if (mountedRef.current) {
        setError((err as Error).message);
      }
    } finally {
      if (mountedRef.current) setLoading(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  useEffect(() => {
    mountedRef.current = true;
    setLoading(true);
    load();
    let timer: ReturnType<typeof setInterval> | null = null;
    if (intervalMs > 0) {
      timer = setInterval(load, intervalMs);
    }
    return () => {
      mountedRef.current = false;
      if (timer) clearInterval(timer);
    };
  }, [load, intervalMs]);

  const refresh = useCallback(() => {
    setLoading(true);
    load();
  }, [load]);

  return { data, loading, error, refresh };
}
