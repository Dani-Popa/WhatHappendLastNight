/**
 * Three-state appearance picker: System · Light · Dark.
 *
 * Renders as a compact segmented control. Per DESIGN_GUIDE.md §5.2, the
 * preferred macOS-native placement for a permanent visible toggle is the
 * Settings sheet — surface this in the web prototype's settings/header area,
 * not in the main content flow.
 */

import { useEffect, useState } from 'react';
import { Monitor, Sun, Moon } from 'lucide-react';
import {
  AppearancePreference,
  readPreference,
  writePreference,
  applyPreference,
} from '../theme';

const OPTIONS: { value: AppearancePreference; label: string; Icon: typeof Sun }[] = [
  { value: 'light',  label: 'Light',  Icon: Sun },
  { value: 'system', label: 'System', Icon: Monitor },
  { value: 'dark',   label: 'Dark',   Icon: Moon },
];

export function ThemeToggle() {
  const [pref, setPref] = useState<AppearancePreference>(readPreference());

  // Apply on mount and whenever the user changes preference.
  useEffect(() => { applyPreference(pref); }, [pref]);

  // When preference is "system", react to OS changes live (no reload needed).
  useEffect(() => {
    if (pref !== 'system' || typeof window === 'undefined' || !window.matchMedia) return;
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    const handler = () => applyPreference('system');
    mq.addEventListener('change', handler);
    return () => mq.removeEventListener('change', handler);
  }, [pref]);

  const choose = (value: AppearancePreference) => {
    setPref(value);
    writePreference(value);
  };

  return (
    <div
      role="radiogroup"
      aria-label="Appearance"
      className="inline-flex items-center gap-1 rounded-[var(--radius-m)] p-1"
      style={{ background: 'var(--surface-sunken)', border: '1px solid var(--border)' }}
    >
      {OPTIONS.map(({ value, label, Icon }) => {
        const selected = pref === value;
        return (
          <button
            key={value}
            role="radio"
            aria-checked={selected}
            aria-label={label}
            onClick={() => choose(value)}
            className="flex items-center gap-1.5 px-2.5 py-1 rounded-[var(--radius-s)] text-[13px] font-medium transition-colors duration-150"
            style={{
              background: selected ? 'var(--accent-primary)' : 'transparent',
              color: selected ? 'var(--on-accent)' : 'var(--text-secondary)',
            }}
            title={`Appearance: ${label}`}
          >
            <Icon size={14} aria-hidden />
            <span>{label}</span>
          </button>
        );
      })}
    </div>
  );
}
