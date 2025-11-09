import { useEffect, useRef, useState } from 'react';

export const useDeltaPulse = (value: number, duration = 800) => {
  const [delta, setDelta] = useState(0);
  const previous = useRef(value);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (value === previous.current) {
      return;
    }

    const change = Number((value - previous.current).toFixed(2));
    previous.current = value;
    setDelta(change);

    if (timerRef.current) {
      clearTimeout(timerRef.current);
    }

    timerRef.current = setTimeout(() => setDelta(0), duration);

    return () => {
      if (timerRef.current) {
        clearTimeout(timerRef.current);
      }
    };
  }, [value, duration]);

  return delta;
};
