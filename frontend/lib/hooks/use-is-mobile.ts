'use client';

import { useCallback, useSyncExternalStore } from 'react';

export const MOBILE_MAX_PX = 768;
export const BELOW_DESKTOP_MAX_PX = 1023;

const getServerSnapshot = () => false;

/**
 * A phone turned sideways is wider than 768px (iPhone 17: 874x402) but still a phone, so short
 * touch screens count as mobile too. Tablets are far taller than 500px in either orientation.
 */
export const MOBILE_MEDIA_QUERY = `(max-width: ${MOBILE_MAX_PX}px), (pointer: coarse) and (max-height: 500px)`;

/**
 * Tracks a media query. A client-side mount reads matchMedia on its first render (no
 * desktop-first flash); hydration starts from the prerendered desktop value, then switches.
 */
function useMediaQuery(query: string): boolean {
  const subscribe = useCallback((onChange: () => void) => {
    const mq = window.matchMedia?.(query);
    if (!mq) return () => {};
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
  }, [query]);
  const getSnapshot = useCallback(() => !!window.matchMedia?.(query)?.matches, [query]);
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}

/** True when the viewport width is ≤768px, or on a phone in landscape. */
export const useIsMobile = (): boolean => useMediaQuery(MOBILE_MEDIA_QUERY);

/** True when the viewport width is ≤1023px (phones and tablets). */
export const useIsBelowDesktop = (): boolean => useMediaQuery(`(max-width: ${BELOW_DESKTOP_MAX_PX}px)`);
