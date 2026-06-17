import {StrictMode} from 'react';
import {createRoot} from 'react-dom/client';
import App from './App.tsx';
import './index.css';
import { applyPreference, readPreference } from './theme';

// Apply persisted appearance before React mounts so the first paint is correct
// (no flash of light/dark theme on reload).
applyPreference(readPreference());

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
