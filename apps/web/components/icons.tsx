/* Togi icons — clean 1.6px line set (Lucide-ish). Ported from the prototype. */
import * as React from "react";

type P = { size?: number; sw?: number; className?: string; style?: React.CSSProperties };

const Svg = ({ children, size = 18, sw = 1.6, ...rest }: P & { children: React.ReactNode }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor"
    strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round" {...rest}>{children}</svg>
);

export const IcToday = (p: P) => <Svg {...p}><rect x="3" y="4.5" width="18" height="16" rx="2.5" /><path d="M3 9h18M8 2.5v4M16 2.5v4" /><circle cx="12" cy="14.5" r="2.2" fill="currentColor" stroke="none" /></Svg>;
export const IcPlan = (p: P) => <Svg {...p}><path d="M5 4h14a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1Z" /><path d="M8 9h8M8 13h8M8 17h5" /></Svg>;
export const IcActual = (p: P) => <Svg {...p}><path d="M12 8v4l2.5 1.5" /><circle cx="12" cy="12" r="8.5" /><path d="M3.5 12a8.5 8.5 0 0 1 .6-3" /></Svg>;
export const IcInsights = (p: P) => <Svg {...p}><path d="M4 19V10M9.5 19V5M15 19v-6M20.5 19V8" /></Svg>;
export const IcSettings = (p: P) => <Svg {...p}><circle cx="12" cy="12" r="3" /><path d="M19.4 13.5a1.7 1.7 0 0 0 .3 1.9l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-2.9 1.2v.2a2 2 0 1 1-4 0v-.1A1.7 1.7 0 0 0 7 18.4a1.7 1.7 0 0 0-1.9.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0-1.2-2.9H1a2 2 0 1 1 0-4h.1A1.7 1.7 0 0 0 2.4 7a1.7 1.7 0 0 0-.3-1.9l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1A1.7 1.7 0 0 0 7 2.6h.1A1.7 1.7 0 0 0 8.5 1V.9a2 2 0 1 1 4 0V1a1.7 1.7 0 0 0 1.9 1.2 1.7 1.7 0 0 0 1.9-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.9V7a1.7 1.7 0 0 0 1.6 1.4h.2a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1Z" transform="translate(1.5 1.5) scale(0.86)" /></Svg>;
export const IcMic = (p: P) => <Svg {...p}><rect x="9" y="2.5" width="6" height="12" rx="3" /><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21M8.5 21h7" /></Svg>;
export const IcChat = (p: P) => <Svg {...p}><path d="M20 11.5a7.5 7.5 0 0 1-10.8 6.8L4 19.5l1.2-4.1A7.5 7.5 0 1 1 20 11.5Z" /></Svg>;
export const IcSpark = (p: P) => <Svg {...p}><path d="M12 3.5 13.7 9l5.3 1.7-5.3 1.7L12 18l-1.7-5.6L5 10.7 10.3 9 12 3.5Z" /></Svg>;
export const IcArrow = (p: P) => <Svg {...p}><path d="M5 12h14M13 6l6 6-6 6" /></Svg>;
export const IcArrowUp = (p: P) => <Svg {...p}><path d="M12 19V5M6 11l6-6 6 6" /></Svg>;
export const IcTrash = (p: P) => <Svg {...p}><path d="M4 7h16M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2M6 7l1 13a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1l1-13" /></Svg>;
export const IcCheck = (p: P) => <Svg {...p}><path d="M5 12.5l4.5 4.5L19 6.5" /></Svg>;
export const IcReturn = (p: P) => <Svg {...p}><path d="M4 12a8 8 0 1 1 3 6.2" /><path d="M3 18v-4h4" /></Svg>;
export const IcClose = (p: P) => <Svg {...p}><path d="M6 6l12 12M18 6 6 18" /></Svg>;
export const IcPlus = (p: P) => <Svg {...p}><path d="M12 5v14M5 12h14" /></Svg>;
export const IcClock = (p: P) => <Svg {...p}><circle cx="12" cy="12" r="8.5" /><path d="M12 7.5V12l3 1.8" /></Svg>;
export const IcChevron = (p: P) => <Svg {...p}><path d="M9 6l6 6-6 6" /></Svg>;
export const IcCommand = (p: P) => <Svg {...p}><path d="M9 6a3 3 0 1 0-3 3h12a3 3 0 1 0-3-3v12a3 3 0 1 0 3-3H6a3 3 0 1 0 3 3V6Z" /></Svg>;
export const IcGhost = (p: P) => <Svg {...p}><path d="M5 20V10a7 7 0 0 1 14 0v10l-2.3-1.6L14.4 20 12 18.4 9.6 20 7.3 18.4 5 20Z" /><path d="M9.5 9.5h.01M14.5 9.5h.01" /></Svg>;
export const IcWave = (p: P) => <Svg {...p}><path d="M2 12h2M7 7v10M12 4v16M17 8v8M22 12h0" /></Svg>;
export const IcDrag = (p: P) => <Svg {...p}><circle cx="9" cy="6" r="1.3" fill="currentColor" stroke="none" /><circle cx="15" cy="6" r="1.3" fill="currentColor" stroke="none" /><circle cx="9" cy="12" r="1.3" fill="currentColor" stroke="none" /><circle cx="15" cy="12" r="1.3" fill="currentColor" stroke="none" /><circle cx="9" cy="18" r="1.3" fill="currentColor" stroke="none" /><circle cx="15" cy="18" r="1.3" fill="currentColor" stroke="none" /></Svg>;
export const IcExpand = (p: P) => <Svg {...p}><path d="M9 4H5a1 1 0 0 0-1 1v4M15 4h4a1 1 0 0 1 1 1v4M9 20H5a1 1 0 0 1-1-1v-4M15 20h4a1 1 0 0 0 1-1v-4" /></Svg>;
export const IcPause = (p: P) => <Svg {...p}><rect x="6.5" y="5" width="3.5" height="14" rx="1" /><rect x="14" y="5" width="3.5" height="14" rx="1" /></Svg>;
export const IcPlay = (p: P) => <Svg {...p}><path d="M7 4.5l12 7.5-12 7.5z" /></Svg>;
export const IcMinimize = (p: P) => <Svg {...p}><path d="M4 9h4a1 1 0 0 0 1-1V4M20 9h-4a1 1 0 0 1-1-1V4M4 15h4a1 1 0 0 1 1 1v4M20 15h-4a1 1 0 0 1-1 1v4" /></Svg>;
export const IcUser = (p: P) => <Svg {...p}><circle cx="12" cy="8" r="4" /><path d="M4.5 20a7.5 7.5 0 0 1 15 0" /></Svg>;
