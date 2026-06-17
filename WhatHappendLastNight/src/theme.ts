/**
 * Appearance preference for the React prototype.
 *
 * Mirrors the macOS-native ThemeManager: defaults to following the OS
 * (`prefers-color-scheme`) and lets the user override via the ThemeToggle.
 * Stored in localStorage so it survives reloads. No telemetry — value is local.
 */

export type AppearancePreference = 'system' | 'light' | 'dark';

const KEY = 'appearancePreference';

export function readPreference(): AppearancePreference {
  if (typeof window === 'undefined') return 'system';
  const raw = window.localStorage.getItem(KEY);
  if (raw === 'light' || raw === 'dark' || raw === 'system') return raw;
  return 'system';
}

export function writePreference(pref: AppearancePreference): void {
  if (typeof window === 'undefined') return;
  window.localStorage.setItem(KEY, pref);
  applyPreference(pref);
}

/**
 * Apply the preference to the document root by setting (or removing)
 * `data-theme` on <html>. With `system`, the attribute is removed so the CSS
 * media query in index.css decides.
 */
export function applyPreference(pref: AppearancePreference): void {
  if (typeof document === 'undefined') return;
  const root = document.documentElement;
  if (pref === 'system') {
    root.removeAttribute('data-theme');
  } else {
    root.setAttribute('data-theme', pref);
  }
}

/** Returns the effective scheme right now (resolves `system` against the OS). */
export function resolveEffective(pref: AppearancePreference): 'light' | 'dark' {
  if (pref !== 'system') return pref;
  if (typeof window === 'undefined' || !window.matchMedia) return 'light';
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}
