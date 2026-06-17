/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React from 'react';

interface PartyPhotoRendererProps {
  illustrationId: string;
  className?: string;
}

export const PartyPhotoRenderer: React.FC<PartyPhotoRendererProps> = ({
  illustrationId,
  className = '',
}) => {
  // Styles & gradients
  const baseClasses = `relative aspect-square overflow-hidden rounded-xl bg-[#0C0C0C] border border-[#222] ${className}`;

  switch (illustrationId) {
    // ------------------- SELFIES / PORTRAITS -------------------
    case 'alex':
      return (
        <div id="illustration-alex" className={baseClasses}>
          <div className="absolute inset-0 bg-gradient-to-tr from-cyan-950 via-slate-900 to-emerald-950" />
          {/* Neon laser backdrop */}
          <div className="absolute top-1/2 left-0 right-0 h-[10px] bg-emerald-500/30 blur-md transform -translate-y-1/2 rotate-12" />
          <div className="absolute top-1/3 left-0 right-0 h-[6px] bg-cyan-400/20 blur-sm transform -translate-y-1/2 -rotate-6" />
          
          <svg viewBox="0 0 100 100" className="absolute inset-0 w-full h-full">
            {/* Shoulders */}
            <path d="M20,95 C20,75 35,68 50,68 C65,68 80,75 80,95" fill="#0f172a" stroke="#334155" strokeWidth="1" />
            <path d="M25,95 C25,78 37,72 50,72 C63,72 75,78 75,95" fill="#065f46" />
            
            {/* Neck */}
            <rect x="44" y="58" width="12" height="15" fill="#fbcfe8" rx="2" className="opacity-80" />
            
            {/* Head/Face */}
            <circle cx="50" cy="46" r="18" fill="#fbcfe8" />
            
            {/* Beanie Hat */}
            <path d="M30,38 C30,22 40,16 50,16 C60,16 70,22 70,38" fill="#1e293b" />
            <rect x="28" y="34" width="44" height="6" fill="#0f172a" rx="3" />
            <circle cx="50" cy="14" r="3.5" fill="#1e293b" />
            
            {/* Eyes & Eyebrows */}
            <path d="M40,39 Q44,38 45,41" stroke="#334155" strokeWidth="1.5" fill="none" />
            <path d="M60,39 Q56,38 55,41" stroke="#334155" strokeWidth="1.5" fill="none" />
            <circle cx="42" cy="44" r="1.5" fill="#0f172a" />
            <circle cx="58" cy="44" r="1.5" fill="#0f172a" />
            
            {/* Mouth (Happy Smile) */}
            <path d="M44,52 Q50,57 56,52" stroke="#0f172a" strokeWidth="1.5" fill="none" />
            
            {/* Signature Neon Glasses */}
            <circle cx="41" cy="45" r="7.5" fill="none" stroke="#22c55e" strokeWidth="2.5" className="filter drop-shadow-[0_0_2px_rgba(34,197,94,0.8)]" />
            <circle cx="59" cy="45" r="7.5" fill="none" stroke="#22c55e" strokeWidth="2.5" className="filter drop-shadow-[0_0_2px_rgba(34,197,94,0.8)]" />
            <line x1="48.5" y1="45" x2="51.5" y2="45" stroke="#22c55e" strokeWidth="2.5" />
          </svg>
        </div>
      );

    case 'chloe':
      return (
        <div id="illustration-chloe" className={baseClasses}>
          <div className="absolute inset-0 bg-gradient-to-tr from-fuchsia-950 via-slate-900 to-indigo-950" />
          {/* Laser grids */}
          <div className="absolute inset-x-0 bottom-0 h-1/2 bg-[linear-gradient(rgba(139,92,246,0.1)_1px,transparent_1px)] bg-[size:100%_8px]" />
          <div className="absolute top-1/4 right-0 left-0 h-[8px] bg-pink-500/20 blur-md transform rotate-6" />

          <svg viewBox="0 0 100 100" className="absolute inset-0 w-full h-full">
            {/* Mesh Crop Top Shoulders */}
            <path d="M22,95 C22,76 36,69 50,69 C64,69 78,76 78,95" fill="#0f172a" stroke="#475569" strokeWidth="1" />
            <path d="M26,95 C26,79 38,73 50,73 C62,73 74,79 74,95" fill="#581c87" />
            
            {/* Grid mesh texture on top */}
            <path d="M30,95 L50,73 L70,95 M35,95 L50,76 L65,95 M40,95 L50,81 L60,95" stroke="#a21caf" strokeWidth="0.5" fill="none" className="opacity-60" />
            
            {/* Neck */}
            <rect x="44" y="60" width="12" height="13" fill="#fed7aa" rx="1.5" className="opacity-90" />
            
            {/* Head/Face */}
            <circle cx="50" cy="48" r="17" fill="#fed7aa" />
            
            {/* Sharp Blue Bob Hair (Back Layer) */}
            <path d="M30,42 C28,52 30,62 33,67 C35,70 38,62 38,55 C38,45 34,42 34,42" fill="#06b6d4" />
            <path d="M70,42 C72,52 70,62 67,67 C65,70 62,62 62,55 C62,45 66,42 66,42" fill="#06b6d4" />
            
            {/* Main Hair Cap */}
            <path d="M31,44 C31,23 40,18 50,18 C60,18 69,23 69,44 C69,56 68,64 68,66 C65,60 62,55 62,46 L38,46 C38,55 35,60 32,66 C32,64 31,56 31,44 Z" fill="#0891b2" />
            <path d="M31,34 C35,24 43,21 50,21 C57,21 65,24 69,34" stroke="#22d3ee" strokeWidth="1.5" fill="none" className="opacity-60" />
            
            {/* Eyes & Glitter Accents */}
            <path d="M39,43 Q43,42 44,45" stroke="#334155" strokeWidth="1.5" fill="none" />
            <path d="M61,43 Q57,42 56,45" stroke="#334155" strokeWidth="1.5" fill="none" />
            
            {/* Glitter on cheeks (glowing circles) */}
            <circle cx="38" cy="51" r="2.5" fill="#f472b6" className="filter drop-shadow-[0_0_2px_rgba(244,114,182,0.8)]" />
            <circle cx="39" cy="53" r="1.5" fill="#22d3ee" className="filter drop-shadow-[0_0_2px_rgba(34,211,238,0.8)]" />
            <circle cx="62" cy="51" r="2.5" fill="#f472b6" className="filter drop-shadow-[0_0_2px_rgba(244,114,182,0.8)]" />
            <circle cx="61" cy="53" r="1.5" fill="#22d3ee" className="filter drop-shadow-[0_0_2px_rgba(34,211,238,0.8)]" />
            
            {/* Eyes (Glowing cyan spark) */}
            <circle cx="41" cy="46" r="1.5" fill="#22d3ee" />
            <circle cx="59" cy="46" r="1.5" fill="#22d3ee" />

            {/* Mouth */}
            <path d="M45,54 Q50,59 55,54" stroke="#db2777" strokeWidth="2.2" fill="none" strokeLinecap="round" />
          </svg>
        </div>
      );

    // ------------------- DETROIT BOILER ROOM PHOTOS -------------------
    case 'dj-booth-red':
      return (
        <div id="illustration-dj-booth-red" className={baseClasses}>
          <div className="absolute inset-0 bg-gradient-to-b from-red-950 via-zinc-950 to-black" />
          {/* Pulsing strobe flare */}
          <div className="absolute inset-0 bg-red-500/10 animate-pulse" />
          
          {/* Laser Lines */}
          <div className="absolute top-10 left-0 w-full h-[1px] bg-red-500 shadow-[0_0_8px_4px_rgba(239,68,68,0.7)] rotate-[15deg]" />
          <div className="absolute top-24 left-0 w-full h-[1px] bg-red-400 shadow-[0_0_6px_3px_rgba(248,113,113,0.5)] rotate-[-10deg]" />
          <div className="absolute top-16 left-0 w-full h-[1px] bg-red-500 shadow-[0_0_8px_4px_rgba(239,68,68,0.6)] rotate-[25deg]" />

          {/* Crowd Outline */}
          <div className="absolute bottom-0 inset-x-0 h-1/2 bg-gradient-to-t from-black to-slate-950/40 opacity-90">
            <svg viewBox="0 0 100 50" className="w-full h-full text-slate-950/70">
              <path d="M 0 50 Q 8 30 15 52 Q 22 25 32 51 Q 40 15 48 53 Q 55 20 62 49 Q 72 35 80 52 Q 91 22 100 50 L 100 50 L 0 50 Z" fill="currentColor" />
              <path d="M 0 50 Q 12 35 25 50 Q 38 28 50 51 Q 65 32 75 52 Q 88 25 100 50" fill="none" stroke="rgba(248,113,113,0.15)" strokeWidth="1" />
            </svg>
          </div>

          {/* DJ Mixing Console */}
          <div className="absolute bottom-0 left-1/2 transform -translate-x-1/2 w-3/5 h-2/5 bg-zinc-900 border-x border-t border-red-920/40 rounded-t-lg shadow-2xl p-2 flex flex-col justify-end">
            {/* Turntables and mixers */}
            <div className="flex justify-between items-center opacity-60 px-2 h-2">
              <div className="w-4 h-4 rounded-full border border-red-500/30" />
              <div className="w-3 h-2 bg-zinc-800" />
              <div className="w-4 h-4 rounded-full border border-red-500/30" />
            </div>
            {/* Equalizer lines */}
            <div className="flex justify-center space-x-1 mt-2 h-4 items-end px-3">
              <div className="w-1 h-3 bg-red-500" />
              <div className="w-1 h-4 bg-red-400" />
              <div className="w-1 h-1 bg-red-600" />
              <div className="w-1 h-2 bg-red-500" />
              <div className="w-1 h-3 bg-red-400" />
            </div>
          </div>
          {/* Ambient text label */}
          <div className="absolute top-3 left-3 bg-zinc-950/60 border border-zinc-800/60 px-1.5 py-0.5 rounded text-[8px] font-mono text-zinc-500">
            RAVE SEC_04
          </div>
        </div>
      );

    case 'alex-by-speaker':
      return (
        <div id="illustration-alex-by-speaker" className={baseClasses}>
          <div className="absolute inset-0 bg-gradient-to-br from-zinc-950 via-slate-900 to-red-950/40" />

          {/* Sound waves graphic */}
          <div className="absolute top-1/4 left-5 w-24 h-24 rounded-full border border-teal-500/10 scale-105 animate-ping opacity-20" />
          <div className="absolute top-1/4 left-5 w-24 h-24 rounded-full border border-teal-500/10 scale-125 opacity-10" />

          {/* Massive Speaker stack on left */}
          <div className="absolute bottom-0 left-2 w-16 h-3/4 bg-zinc-950 border-r border-t border-zinc-800 rounded-tr p-1 flex flex-col justify-around">
            <div className="w-full aspect-square rounded-full bg-zinc-900 border border-zinc-800 flex items-center justify-center">
              <div className="w-6 h-6 rounded-full bg-zinc-950 border border-teal-500/20" />
            </div>
            <div className="w-full aspect-square rounded-full bg-zinc-900 border border-zinc-800 flex items-center justify-center">
              <div className="w-10 h-10 rounded-full bg-zinc-950 border border-teal-500/30 flex items-center justify-center">
                <div className="w-4 h-4 rounded-full bg-black border border-teal-500/40" />
              </div>
            </div>
          </div>

          <svg viewBox="0 0 100 100" className="absolute inset-0 w-full h-full">
            {/* Alex silhouette on right, detailed */}
            <g transform="translate(18, 0)">
              {/* Body */}
              <path d="M40,95 C40,79 50,71 62,71 C74,71 84,79 84,95" fill="#0a0a0a" stroke="#262626" strokeWidth="1" />
              <path d="M43,95 C43,82 51,74 62,74 C73,74 81,82 81,95" fill="#075e47" />
              {/* Cup in hand */}
              <path d="M38,82 L42,82 L44,92 L36,92 Z" fill="#22d3ee" className="filter drop-shadow-[0_0_2px_rgba(34,211,238,0.8)]" />
              
              {/* Neck */}
              <rect x="58" y="63" width="8" height="12" fill="#fbcfe8" className="opacity-90" />
              {/* Head */}
              <circle cx="62" cy="51" r="14" fill="#fbcfe8" />
              {/* Beanie Hat */}
              <path d="M47,44 C47,32 54,27 62,27 C70,27 77,32 77,44" fill="#171717" />
              <rect x="45" y="41" width="34" height="5" fill="#0a0a0a" rx="2" />
              {/* Glasses (glowing green) */}
              <circle cx="55" cy="50" r="5" fill="none" stroke="#22c55e" strokeWidth="2" className="filter drop-shadow-[0_0_2px_rgba(34,197,94,0.8)]" />
              <circle cx="69" cy="50" r="5" fill="none" stroke="#22c55e" strokeWidth="2" className="filter drop-shadow-[0_0_2px_rgba(34,197,94,0.8)]" />
              <line x1="60" y1="50" x2="64" y2="50" stroke="#22c55e" strokeWidth="2" />
              {/* Smile */}
              <path d="M58,56 Q62,60 66,56" stroke="#000" strokeWidth="1.2" fill="none" />
            </g>
          </svg>
          <div className="absolute top-3 right-3 bg-emerald-950/80 border border-emerald-500/20 px-1.5 py-0.5 rounded text-[8px] font-mono text-emerald-400">
            DETECTED
          </div>
        </div>
      );

    case 'girls-dancing':
      return (
        <div id="illustration-girls-dancing" className={baseClasses}>
          <div className="absolute inset-0 bg-gradient-to-tr from-fuchsia-950 via-zinc-950 to-indigo-950" />
          
          {/* Sparkles backdrop */}
          <div className="absolute top-4 left-6 w-1 h-1 bg-white rounded-full animate-ping" />
          <div className="absolute top-12 right-12 w-2 h-2 bg-yellow-400 rounded-full blur-[1px]" />
          <div className="absolute bottom-1/3 left-1/4 w-1.5 h-1.5 bg-pink-400 rounded-full blur-[0.5px]" />

          <svg viewBox="0 0 100 100" className="absolute inset-0 w-full h-full">
            {/* Friend 1 on Left */}
            <g transform="translate(-8, 5)">
              <path d="M15,95 C15,80 25,74 35,74 C45,74 55,80 55,95" fill="#090514" />
              <circle cx="35" cy="53" r="11" fill="#ec4899" className="opacity-40" />
              <rect x="31" y="62" width="8" height="13" fill="#fda4af" />
              <circle cx="35" cy="51" r="11" fill="#fda4af" />
              {/* Brown wavy hair ponytail */}
              <path d="M24,45 C20,50 18,58 20,62 C23,60 25,54 26,49" fill="#1c0d02" />
            </g>

            {/* Chloe in center, dancing */}
            <g transform="translate(14, 0)">
              {/* Crop top torso */}
              <path d="M22,95 C22,78 34,71 46,71 C58,71 70,78 70,95" fill="#120e2e" />
              <path d="M25,95 C25,81 35,75 46,75 C57,75 67,81 67,95" fill="#4c0519" /> {/* glitter clothing */}
              {/* Off-neck and arms */}
              <rect x="41" y="62" width="10" height="14" fill="#fdbaf8" className="opacity-90" />
              
              {/* Head / Face */}
              <circle cx="46" cy="50" r="15" fill="#fdbaf8" />
              
              {/* Blue Bob Cut */}
              <path d="M29,46 C27,55 29,64 31,69 C33,71 35,64 35,58" fill="#06b6d4" />
              <path d="M63,46 C65,55 63,64 61,69 C59,71 57,64 57,58" fill="#06b6d4" />
              <path d="M30,47 C30,27 38,22 46,22 C54,22 62,27 62,47 L56,42 L36,42 Z" fill="#0891b2" />
              
              {/* Eyes & Glitter Dots */}
              <circle cx="38" cy="52" r="1" fill="#ec4899" />
              <circle cx="54" cy="52" r="1" fill="#ec4899" />
              {/* Sparkling face glitter */}
              <circle cx="35" cy="55" r="1.5" fill="#22d3ee" className="filter drop-shadow-[0_0_1px_#22d3ee]" />
              <circle cx="57" cy="55" r="1.5" fill="#22d3ee" className="filter drop-shadow-[0_0_1px_#22d3ee]" />
              {/* Smile */}
              <path d="M41,56 Q46,61 51,56" stroke="#4c0519" strokeWidth="1.5" fill="none" />
            </g>
          </svg>
          <div className="absolute top-3 right-3 bg-pink-950/80 border border-pink-500/20 px-1.5 py-0.5 rounded text-[8px] font-mono text-pink-400">
            DETECTED
          </div>
        </div>
      );

    case 'crowd-wide':
      return (
        <div id="illustration-crowd-wide" className={baseClasses}>
          <div className="absolute inset-0 bg-gradient-to-t from-zinc-950 via-zinc-900 to-violet-950/50" />
          
          {/* Sweeping laser triangles */}
          <svg className="absolute inset-0 w-full h-full" viewBox="0 0 100 100" preserveAspectRatio="none">
            <polygon points="50,10 0,90 20,90" fill="rgba(168,85,247,0.15)" />
            <polygon points="50,10 80,95 100,80" fill="rgba(236,72,153,0.12)" />
            <polygon points="50,10 30,100 45,100" fill="rgba(6,182,212,0.1)" />
          </svg>

          {/* Crowd columns */}
          <div className="absolute bottom-0 inset-x-0 h-3/5 flex items-end justify-between px-2">
            <div className="w-10 h-16 bg-neutral-950 border-t border-r border-neutral-800 rounded-t-full" />
            <div className="w-12 h-20 bg-neutral-950 border-t border-l border-neutral-850 rounded-t-full transform translate-y-2" />
            <div className="w-9 h-14 bg-neutral-950 border-t border-neutral-800 rounded-t-full" />
            <div className="w-11 h-24 bg-neutral-950 border-t border-x border-neutral-800 rounded-t-full transform translate-y-4" />
            <div className="w-8 h-18 bg-neutral-950 border-t border-l border-neutral-900 rounded-t-full" />
            <div className="w-10 h-16 bg-neutral-950 border-t border-neutral-800 rounded-t-full transform translate-y-1" />
          </div>

          <div className="absolute bottom-3 left-3 bg-zinc-950/60 border border-zinc-850 px-1.5 py-0.5 rounded text-[8px] font-mono text-zinc-400">
            CROWDSTAGE WIDE
          </div>
        </div>
      );

    case 'alex-shadows':
      return (
        <div id="illustration-alex-shadows" className={baseClasses}>
          <div className="absolute inset-0 bg-zinc-950" />
          
          {/* Pure High Contrast Monochrome Shadow Play */}
          <svg viewBox="0 0 100 100" className="absolute inset-0 w-full h-full">
            {/* White strobe blast */}
            <polygon points="0,0 100,40 100,100 0,60" fill="rgba(255,255,255,0.06)" />

            <g transform="translate(10, 5)">
              {/* Shadow contours */}
              <path d="M25,95 C25,75 35,68 53,68 C71,68 81,75 81,95" fill="#09090b" stroke="#27272a" strokeWidth="1.5" />
              <rect x="47" y="58" width="12" height="15" fill="#f4f4f5" className="opacity-90" />
              
              {/* Highlight side of head */}
              <circle cx="53" cy="46" r="18" fill="#f4f4f5" />
              {/* Shadows over half face */}
              <path d="M35,46 C35,56 46,64 53,64 L53,28 C43,28 35,36 35,46 Z" fill="#09090b" className="opacity-95" />

              {/* Beanie details */}
              <path d="M33,38 C33,22 43,16 53,16 C63,16 73,22 73,38" fill="#27272a" />
              <rect x="31" y="34" width="44" height="6" fill="#18181b" rx="2" />
              
              {/* Neon Green Glasses cutting through the shadow */}
              <circle cx="44" cy="45" r="7.5" fill="none" stroke="#22c55e" strokeWidth="2.5" className="filter drop-shadow-[0_0_2px_#22c55e]" />
              <circle cx="62" cy="45" r="7.5" fill="none" stroke="#22c55e" strokeWidth="2.5" className="filter drop-shadow-[0_0_2px_#22c55e]" />
              <line x1="51.5" y1="45" x2="54.5" y2="45" stroke="#22c55e" strokeWidth="2.5" />

              {/* Laughing Mouth */}
              <path d="M47,53 Q53,58 59,53" stroke="black" strokeWidth="2" fill="none" />
            </g>
          </svg>
          <div className="absolute bottom-3 right-3 bg-emerald-950/80 border border-emerald-500/20 px-1.5 py-0.5 rounded text-[8px] font-mono text-emerald-400">
            92% CONFIDENCE
          </div>
        </div>
      );

    case 'chloe-bar':
      return (
        <div id="illustration-chloe-bar" className={baseClasses}>
          <div className="absolute inset-0 bg-gradient-to-b from-zinc-900 via-neutral-950 to-zinc-950" />
          
          {/* Neon Tube Bar header */}
          <div className="absolute top-6 left-1/4 right-10 h-1.5 bg-red-500 rounded-full shadow-[0_0_12px_4px_rgba(239,68,68,0.8)]" />

          {/* Hanging glass shelf silhouette */}
          <div className="absolute top-0 left-0 w-full h-[22px] bg-zinc-950/80 border-b border-zinc-800 flex justify-around items-end pb-1 px-8 opacity-45">
            <div className="w-[1px] h-3 bg-zinc-700" />
            <div className="w-1.5 h-2.5 bg-neutral-800 rounded-sm" />
            <div className="w-[1px] h-3 bg-zinc-700" />
            <div className="w-[1.5px] h-3.5 bg-neutral-800 rounded-sm" />
          </div>

          {/* Chloe standing at bar */}
          <svg viewBox="0 0 100 100" className="absolute inset-0 w-full h-full">
            <g transform="translate(18, 12)">
              {/* Shoulders */}
              <path d="M22,95 C22,76 36,69 50,69 C64,69 78,76 78,95" fill="#09090b" />
              <path d="M26,95 C26,79 38,73 50,73 C62,73 74,79 74,95" fill="#2d064e" className="opacity-90Color" />
              
              {/* Neck */}
              <rect x="44" y="60" width="12" height="13" fill="#fed7aa" rx="1.5" className="opacity-95" />
              {/* Head */}
              <circle cx="50" cy="48" r="17" fill="#fed7aa" />
              
              {/* Blue Hair catching overhead red glow */}
              <path d="M29,48 C27,57 29,66 31,71" fill="none" stroke="#22d3ee" strokeWidth="2.5" />
              <path d="M71,48 C73,57 71,66 69,71" fill="none" stroke="#22d3ee" strokeWidth="2.5" />
              <path d="M30,47 C30,27 38,22 46,22 C54,22 62,27 62,47 L56,42 L36,42 Z" fill="#0891b2" />
              
              {/* Profile shadows */}
              <path d="M30,42 C33,35 45,30 50,30 L50,65 C41,65 31,57 30,42 Z" fill="rgba(0,0,0,0.15)" />
            </g>
          </svg>
          <div className="absolute top-3 left-3 bg-red-950/70 border border-red-500/20 px-1.5 py-0.5 rounded text-[8px] font-mono text-red-400">
            BAR ZONE Red
          </div>
        </div>
      );

    case 'smoke-floor':
      return (
        <div id="illustration-smoke-floor" className={baseClasses}>
          <div className="absolute inset-0 bg-neutral-950" />
          
          {/* Strong green spotlight and foggy circles */}
          <div className="absolute top-0 left-1/2 transform -translate-x-1/2 w-28 h-56 bg-gradient-to-b from-emerald-500/30 to-transparent clip-path-spotlight" />
          
          {/* Shadows kissing shapes */}
          <svg viewBox="0 0 100 100" className="absolute inset-0 w-full h-full opacity-65">
            <circle cx="45" cy="55" r="14" fill="#121212" />
            <circle cx="58" cy="53" r="12" fill="#181818" />
          </svg>

          {/* Swirling thick smoke clouds */}
          <div className="absolute bottom-0 inset-x-0 h-1/3 bg-gradient-to-t from-zinc-900 to-transparent blur-md opacity-90" />
          <div className="absolute bottom-2 left-4 w-12 h-8 bg-zinc-800/40 rounded-full filter blur-md" />
          <div className="absolute bottom-4 right-2 w-16 h-10 bg-zinc-800/50 rounded-full filter blur-lg" />
        </div>
      );

    // ------------------- NEON SKY OPEN AIR PHOTOS -------------------
    case 'neon-stage-wide':
      return (
        <div id="illustration-neon-stage-wide" className={baseClasses}>
          {/* EDM Mega Sky Gradient */}
          <div className="absolute inset-0 bg-gradient-to-b from-indigo-950 via-purple-900 to-slate-950" />
          
          {/* Giant circle Sun visual */}
          <div className="absolute top-1/4 left-1/2 transform -translate-x-1/2 w-24 h-24 rounded-full bg-gradient-to-b from-pink-500 to-amber-400/45 border-inner border-pink-400/20" />
          
          {/* Converging overhead fan lasers */}
          <svg className="absolute inset-x-0 top-0 h-3/4 w-full" viewBox="0 0 100 50" preserveAspectRatio="none">
            <line x1="50" y1="20" x2="0" y2="50" stroke="#06b6d4" strokeWidth="0.8" className="opacity-80" />
            <line x1="50" y1="20" x2="20" y2="50" stroke="#06b6d4" strokeWidth="0.5" className="opacity-50" />
            <line x1="50" y1="20" x2="40" y2="50" stroke="#d946ef" strokeWidth="0.5" className="opacity-60" />
            <line x1="50" y1="20" x2="60" y2="50" stroke="#d946ef" strokeWidth="0.5" className="opacity-60" />
            <line x1="50" y1="20" x2="80" y2="50" stroke="#06b6d4" strokeWidth="0.5" className="opacity-50" />
            <line x1="50" y1="20" x2="100" y2="50" stroke="#06b6d4" strokeWidth="0.8" className="opacity-80" />
          </svg>

          {/* Ground crowd silhouette */}
          <div className="absolute bottom-0 inset-x-0 h-1/3 bg-black opacity-95">
            <div className="absolute inset-x-0 top-0 h-[4px] bg-purple-500/50 blur-sm" />
          </div>
        </div>
      );

    case 'group-ferris-wheel':
      return (
        <div id="illustration-group-ferris-wheel" className={baseClasses}>
          <div className="absolute inset-0 bg-gradient-to-tr from-indigo-950 via-slate-900 to-violet-950" />
          
          {/* Ferris Wheel Outline with beautiful glowing ring */}
          <div className="absolute right-[-40px] top-4 w-40 h-40 rounded-full border-2 border-violet-500/25 border-dashed flex items-center justify-center animate-spin" style={{ animationDuration: '40s' }}>
            <div className="w-24 h-24 rounded-full border border-violet-400/25" />
            <div className="w-12 h-12 rounded-full border border-pink-400/20" />
          </div>

          <svg viewBox="0 0 100 100" className="absolute inset-0 w-full h-full">
            {/* Friends Standing Front Center */}
            {/* Alex on right, detailed */}
            <g transform="translate(36, 16)">
              {/* Body */}
              <path d="M22,80 C22,66 33,60 45,60 C57,60 68,66 68,80" fill="#0f172a" />
              <path d="M25,80 C25,69 33,63 45,63 C57,63 65,69 65,80" fill="#064e3b" />
              {/* Neck */}
              <rect x="41" y="52" width="8" height="12" fill="#fbcfe8" />
              {/* Head */}
              <circle cx="45" cy="42" r="12" fill="#fbcfe8" />
              {/* Beanie */}
              <path d="M33,36 C33,25 39,21 45,21 C51,21 57,25 57,36" fill="#1e293b" />
              <rect x="31" y="33" width="28" height="4" fill="#0f172a" rx="1.5" />
              {/* Smiling glasses */}
              <circle cx="40" cy="42" r="4" fill="none" stroke="#22c55e" strokeWidth="1.5" className="filter drop-shadow-[0_0_1.5px_#22c55e]" />
              <circle cx="50" cy="42" r="4" fill="none" stroke="#22c55e" strokeWidth="1.5" className="filter drop-shadow-[0_0_1.5px_#22c55e]" />
            </g>

            {/* Friend 2 on left */}
            <g transform="translate(6, 20)">
              <path d="M22,80 C22,68 31,62 42,62 C53,62 62,68 62,80" fill="#020617" />
              <circle cx="42" cy="44" r="11" fill="#fed7aa" />
              {/* Orange cap */}
              <path d="M31,38 C31,33 36,30 42,30 C48,30 53,33 53,38" fill="#f97316" />
              <path d="M42,34 L58,34 L58,37 L42,37 Z" fill="#eb5e00" />
            </g>
          </svg>
          <div className="absolute top-3 left-3 bg-indigo-950/80 border border-indigo-400/20 px-1.5 py-0.5 rounded text-[8px] font-mono text-indigo-300">
            WHEEL VIBE
          </div>
        </div>
      );

    case 'chloe-shoulders':
      return (
        <div id="illustration-chloe-shoulders" className={baseClasses}>
          {/* Confetti Explosion Backdrop */}
          <div className="absolute inset-0 bg-gradient-to-br from-violet-950 via-fuchsia-950 to-slate-900" />
          
          {/* Confetti pieces */}
          <div className="absolute top-6 left-12 w-2 h-1 bg-yellow-400 transform rotate-12 blur-[0.5px]" />
          <div className="absolute top-16 right-16 w-1 h-3 bg-cyan-400 transform -rotate-45 blur-[0.2px]" />
          <div className="absolute top-24 left-2/3 w-2.5 h-1.5 bg-pink-500 transform rotate-45" />

          {/* SVG representation of Chloe on shoulders making heart outline */}
          <svg viewBox="0 0 100 100" className="absolute inset-0 w-full h-full">
            <g transform="translate(14, 15)">
              {/* Shoulders */}
              <path d="M22,85 C22,68 34,61 46,61 C58,61 70,68 70,85" fill="#0c0a0f" />
              <path d="M25,85 C25,72 35,66 46,66 C57,66 67,72 67,85" fill="#4a044e" />
              {/* Neck */}
              <rect x="41" y="55" width="10" height="12" fill="#fed7aa" />
              {/* Head */}
              <circle cx="46" cy="43" r="14" fill="#fed7aa" />
              {/* Blue Bob Cut */}
              <path d="M29,40 C27,48 29,56 31,61 C33,63 35,56 35,51" fill="#06b6d4" />
              <path d="M63,40 C65,48 63,56 61,61 C59,63 57,56 57,51" fill="#06b6d4" />
              <path d="M30,41 C30,23 38,18 46,18 C54,18 62,23 62,41" fill="#0891b2" />
              
              {/* Heart Hands silhouette overhead */}
              <path d="M33,22 Q37,13 41,17 Q45,21 44,25" stroke="#fed7aa" strokeWidth="2.5" strokeLinecap="round" fill="none" />
              <path d="M59,22 Q55,13 51,17 Q47,21 48,25" stroke="#fed7aa" strokeWidth="2.5" strokeLinecap="round" fill="none" />
              {/* Heart Shape icon floating */}
              <path d="M46,21 Q44.5,19 43,20 Q41.5,21 42,23 L46,26 L50,23 Q50.5,21 49,20 Q47.5,19 46,21 Z" fill="#ec4899" className="filter drop-shadow-[0_0_2px_#ec4899]" />
            </g>
          </svg>
          <div className="absolute top-3 right-3 bg-pink-950/85 border border-pink-500/20 px-1.5 py-0.5 rounded text-[8px] font-mono text-pink-400">
            98% MATCH
          </div>
        </div>
      );

    case 'rave-group-chill':
      return (
        <div id="illustration-rave-group-chill" className={baseClasses}>
          <div className="absolute inset-0 bg-gradient-to-b from-teal-950 via-slate-900 to-emerald-950" />
          
          {/* Checkered Picnic Blanket Graphic */}
          <div className="absolute bottom-2 left-6 right-6 h-1/2 bg-[linear-gradient(rgba(244,63,94,0.1)_1px,transparent_1px),linear-gradient(270deg,rgba(244,63,94,0.1)_1px,transparent_1px)] bg-[size:16px_16px] border border-rose-500/10 rounded-lg shadow-inner transform -rotate-2" />

          {/* Interactive silhouette shapes */}
          <svg viewBox="0 0 100 100" className="absolute inset-0 w-full h-full">
            {/* Alex sitting left */}
            <g transform="translate(18, 40)">
              <circle cx="20" cy="20" r="7" fill="#fda4af" />
              {/* Dark Beanie silhouette */}
              <path d="M14,16 C14,11 17,9 20,9 C23,9 26,11 26,16 Z" fill="#0f172a" />
              <line x1="16" y1="18" x2="24" y2="18" stroke="#22c55e" strokeWidth="1.2" /> {/* Green glasses */}
              <path d="M8,42 C8,31 16,27 24,27 C32,27 36,31 36,42" fill="#0f172a" />
            </g>

            {/* Chloe sitting right */}
            <g transform="translate(42, 42)">
              <circle cx="26" cy="18" r="7" fill="#fed7aa" />
              {/* Blue Bob Cut silhouette */}
              <path d="M20,18 C20,9 24,6 26,6 C28,6 32,9 32,18 Z" fill="#0891b2" />
              <path d="M12,40 C12,31 20,25 28,25 C36,25 40,31 40,40" fill="#0a0a0c" />
            </g>
          </svg>
          <div className="absolute bottom-3 left-3 bg-zinc-950/60 border border-zinc-850 px-1.5 py-0.5 rounded text-[8px] font-mono text-zinc-400">
            CHILL MEADOW
          </div>
        </div>
      );

    default:
      // Fallback for custom uploaded files (just display a generic colorful party gradient visualizer, telling them they can scan!)
      return (
        <div id="illustration-fallback" className={baseClasses}>
          <div className="absolute inset-0 bg-gradient-to-br from-violet-900 via-fuchsia-900 to-indigo-950 flex flex-col justify-between p-3" />
          <div className="absolute inset-x-0 top-0 h-[2px] bg-cyan-400/30 blur-[1px]" />
          <svg viewBox="0 0 100 100" className="absolute inset-0 w-full h-full text-white/5 opacity-20">
            <line x1="0" y1="20" x2="100" y2="80" stroke="currentColor" strokeWidth="2" />
            <line x1="100" y1="20" x2="0" y2="80" stroke="currentColor" strokeWidth="2" />
            <circle cx="50" cy="50" r="30" fill="none" stroke="currentColor" strokeWidth="2" />
          </svg>
          <div className="flex justify-between items-start z-10">
            <span className="text-[10px] bg-black/40 px-2 py-0.5 rounded-full font-mono text-gray-300">
              CUSTOM ALBUM
            </span>
            <span className="text-[10px] text-cyan-400 font-mono">
              ★ READY
            </span>
          </div>
          <div className="z-10 bg-black/40 backdrop-blur-sm p-1.5 rounded-lg border border-white/5">
            <p className="text-[8px] font-mono text-gray-400 truncate leading-tight">
              {illustrationId}
            </p>
          </div>
        </div>
      );
  }
};
