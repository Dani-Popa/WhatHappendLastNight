/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useRef, useEffect } from 'react';
import { Camera, Upload, Trash2, User, Sparkles, RefreshCw, AlertCircle } from 'lucide-react';

interface CameraSelfieProps {
  onSelfieSelected: (referenceImage: string | null, isDemo?: boolean, demoId?: string) => void;
  selectedSelfie: string | null;
  selectedDemoId: string | null;
}

export const CameraSelfie: React.FC<CameraSelfieProps> = ({
  onSelfieSelected,
  selectedSelfie,
  selectedDemoId,
}) => {
  const [activeTab, setActiveTab] = useState<'upload' | 'camera' | 'demos'>('upload');
  const [isCameraActive, setIsCameraActive] = useState<boolean>(false);
  const [cameraError, setCameraError] = useState<string | null>(null);
  const [countdown, setCountdown] = useState<number | null>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);

  // Stop camera when component unmounts or tab changes
  useEffect(() => {
    return () => {
      stopCamera();
    };
  }, [activeTab]);

  const startCamera = async () => {
    setCameraError(null);
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { width: 480, height: 480, facingMode: 'user' },
        audio: false,
      });
      streamRef.current = stream;
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        videoRef.current.play();
      }
      setIsCameraActive(true);
    } catch (err: any) {
      setCameraError('Could not access camera. Please check your system/browser permissions.');
      setActiveTab('upload');
    }
  };

  const stopCamera = () => {
    if (streamRef.current) {
      streamRef.current.getTracks().forEach(track => track.stop());
      streamRef.current = null;
    }
    setIsCameraActive(false);
  };

  const handleCapture = () => {
    setCountdown(3);
    const interval = setInterval(() => {
      setCountdown(prev => {
        if (prev === null) return null;
        if (prev <= 1) {
          clearInterval(interval);
          takeSnapshot();
          return null;
        }
        return prev - 1;
      });
    }, 800);
  };

  const takeSnapshot = () => {
    if (!videoRef.current) return;
    const canvas = document.createElement('canvas');
    canvas.width = 480;
    canvas.height = 480;
    const ctx = canvas.getContext('2d');
    if (ctx) {
      // Mirror the selfie snapshot for intuitive natural orientation
      ctx.translate(canvas.width, 0);
      ctx.scale(-1, 1);
      ctx.drawImage(videoRef.current, 0, 0, canvas.width, canvas.height);
      const dataUrl = canvas.toDataURL('image/jpeg', 0.9);
      onSelfieSelected(dataUrl, false);
      stopCamera();
    }
  };

  const handleFileUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = () => {
      if (typeof reader.result === 'string') {
        onSelfieSelected(reader.result, false);
      }
    };
    reader.readAsDataURL(file);
  };

  const selectDemoProfile = (id: string) => {
    // We set dummy identifiers or demo face descriptions
    if (id === 'alex') {
      onSelfieSelected('alex', true, 'alex-selfie');
    } else if (id === 'chloe') {
      onSelfieSelected('chloe', true, 'chloe-selfie');
    }
  };

  return (
    <div id="selfie-module" className="bg-[#080808] rounded-2xl border border-[#222] p-5 flex flex-col h-full">
      {/* Title */}
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-[10px] uppercase tracking-[0.2em] text-[#666] font-medium flex items-center gap-2">
          <Camera className="w-4 h-4 text-[#D4AF37]" />
          1. Identity Reference
        </h3>
        {selectedSelfie && (
          <button
            onClick={() => onSelfieSelected(null)}
            className="text-[9px] uppercase tracking-wider text-red-400 hover:text-red-300 transition-colors flex items-center gap-1 bg-red-950/20 border border-red-500/20 px-2.5 py-1 rounded"
          >
            <Trash2 className="w-3.5 h-3.5" />
            Clear
          </button>
        )}
      </div>

      {/* Tabs */}
      {!selectedSelfie && (
        <div className="flex space-x-1 p-1 bg-[#050505] border border-[#222] rounded-lg mb-4 text-xs">
          <button
            onClick={() => { setActiveTab('upload'); stopCamera(); }}
            className={`flex-1 py-1.5 rounded-md text-[10px] uppercase tracking-wider font-semibold transition-all duration-250 flex items-center justify-center gap-1.5 cursor-pointer ${
              activeTab === 'upload' ? 'bg-[#111] text-[#D4AF37] border border-[#222]/80 shadow-sm' : 'text-[#666] hover:text-[#888]'
            }`}
          >
            <Upload className="w-3.5 h-3.5 text-[#D4AF37]" />
            Upload File
          </button>
          <button
            onClick={() => { setActiveTab('camera'); startCamera(); }}
            className={`flex-1 py-1.5 rounded-md text-[10px] uppercase tracking-wider font-semibold transition-all duration-250 flex items-center justify-center gap-1.5 cursor-pointer ${
              activeTab === 'camera' ? 'bg-[#111] text-[#D4AF37] border border-[#222]/80 shadow-sm' : 'text-[#666] hover:text-[#888]'
            }`}
          >
            <Camera className="w-3.5 h-3.5 text-[#D4AF37]" />
            Instant Camera
          </button>
          <button
            onClick={() => { setActiveTab('demos'); stopCamera(); }}
            className={`flex-1 py-1.5 rounded-md text-[10px] uppercase tracking-wider font-semibold transition-all duration-250 flex items-center justify-center gap-1.5 cursor-pointer ${
              activeTab === 'demos' ? 'bg-[#111] text-[#D4AF37] border border-[#222]/80 shadow-sm' : 'text-[#666] hover:text-[#888]'
            }`}
          >
            <Sparkles className="w-3.5 h-3.5 text-[#D4AF37]" />
            Demo Faces
          </button>
        </div>
      )}

      {/* Content Canvas */}
      <div className="flex-1 flex flex-col items-center justify-center min-h-[220px]">
        {selectedSelfie ? (
          <div className="text-center w-full max-w-[200px] animate-fade-in">
            {/* Visual indicator of selfie type */}
            <div className="relative aspect-square rounded-2xl border border-[#D4AF37] p-1.5 bg-[#0C0C0C] overflow-hidden shadow-[0_0_15px_rgba(212,175,55,0.25)] ring-2 ring-[#D4AF37] ring-offset-4 ring-offset-[#080808]">
              {selectedDemoId ? (
                <div className="w-full h-full flex flex-col justify-center items-center">
                  {selectedDemoId.includes('alex') ? (
                    <div className="w-full h-full flex items-center justify-center bg-zinc-900 rounded-lg">
                      <div className="scale-95 w-full h-full rounded-lg overflow-hidden">
                        {/* Alex dynamic SVG */}
                        <svg viewBox="0 0 100 100" className="w-full h-full">
                          <rect width="100" height="100" fill="#022c22" />
                          <circle cx="50" cy="46" r="18" fill="#fbcfe8" />
                          <path d="M30,38 C30,22 40,16 50,16 C60,16 70,22 70,38" fill="#1e293b" />
                          <circle cx="41" cy="45" r="7.5" fill="none" stroke="#22c55e" strokeWidth="2.5" />
                          <circle cx="59" cy="45" r="7.5" fill="none" stroke="#22c55e" strokeWidth="2.5" />
                          <path d="M44,52 Q50,57 56,52" stroke="#000" strokeWidth="1.5" fill="none" />
                        </svg>
                      </div>
                    </div>
                  ) : (
                    <div className="w-full h-full flex items-center justify-center bg-zinc-900 rounded-lg">
                      <div className="scale-95 w-full h-full rounded-lg overflow-hidden">
                        {/* Chloe dynamic SVG */}
                        <svg viewBox="0 0 100 100" className="w-full h-full">
                          <rect width="100" height="100" fill="#4c0519" />
                          <circle cx="50" cy="48" r="17" fill="#fed7aa" />
                          <path d="M31,44 C31,23 40,18 50,18 C60,18 69,23 69,44" fill="#0891b2" />
                          <path d="M29,46 C27,55 29,64 31,69" fill="#06b6d4" />
                          <path d="M63,46 C65,55 63,64 61,69" fill="#06b6d4" />
                          <circle cx="38" cy="51" r="2.5" fill="#f472b6" />
                          <circle cx="62" cy="51" r="2.5" fill="#f472b6" />
                          <path d="M45,54 Q50,59 55,54" stroke="#db2777" strokeWidth="2.2" fill="none" />
                        </svg>
                      </div>
                    </div>
                  )}
                </div>
              ) : (
                <img
                  src={selectedSelfie}
                  alt="My Selfie"
                  className="w-full h-full object-cover rounded-xl"
                  referrerPolicy="no-referrer"
                />
              )}
              {/* Scanline overlay */}
              <div className="absolute inset-x-0 top-0 h-0.5 bg-[#D4AF37] opacity-65 shadow-[0_0_8px_rgb(212,175,55)] animate-bounce" />
            </div>
            <p className="text-xs text-[#E0D8D0] mt-3 font-mono uppercase tracking-[0.15em]">
              {selectedDemoId ? (selectedDemoId.includes('alex') ? 'Alex demo selected' : 'Chloe demo selected') : 'Reference ready'}
            </p>
          </div>
        ) : (
          <div className="w-full h-full flex flex-col justify-center items-center">
            {/* 1. Upload File Panel */}
            {activeTab === 'upload' && (
              <label className="border-2 border-dashed border-[#222] hover:border-[#D4AF37]/50 bg-[#0C0C0C] hover:bg-[#0A0A0A] rounded-xl p-6 flex flex-col items-center justify-center cursor-pointer transition-all group w-full max-w-xs text-center">
                <Upload className="w-8 h-8 text-[#555] group-hover:text-[#D4AF37] transition-colors mb-4" />
                <span className="text-xs font-semibold text-[#E0D8D0] uppercase tracking-widest">Choose portrait file</span>
                <span className="text-[10px] text-[#555] mt-1 font-mono">PNG, JPG or WEBP</span>
                <input
                  type="file"
                  accept="image/*"
                  onChange={handleFileUpload}
                  className="hidden"
                />
              </label>
            )}

            {/* 2. Webcam Stream Panel */}
            {activeTab === 'camera' && (
              <div className="relative w-full max-w-[240px] rounded-2xl overflow-hidden border border-[#222] bg-black aspect-square flex flex-col justify-center items-center">
                {cameraError ? (
                  <div className="p-4 text-center">
                    <AlertCircle className="w-8 h-8 text-red-500 mx-auto mb-2" />
                    <p className="text-xs text-[#888] leading-relaxed">{cameraError}</p>
                    <button
                      onClick={startCamera}
                      className="mt-3 text-[10px] uppercase tracking-wider font-semibold bg-[#111] hover:bg-[#222] border border-[#222] px-3 py-1.5 rounded text-white flex items-center gap-1 mx-auto cursor-pointer"
                    >
                      <RefreshCw className="w-3 h-3 text-[#D4AF37]" /> Try Again
                    </button>
                  </div>
                ) : (
                  <>
                    <video
                      ref={videoRef}
                      autoPlay
                      playsInline
                      muted
                      className="w-full h-full object-cover transform -scale-x-100"
                    />

                    {/* Laser framing mask */}
                    <div className="absolute inset-4 border border-[#D4AF37]/30 rounded-xl pointer-events-none">
                      <div className="absolute top-0 left-0 w-3 h-3 border-t-2 border-l-2 border-[#D4AF37]" />
                      <div className="absolute top-0 right-0 w-3 h-3 border-t-2 border-r-2 border-[#D4AF37]" />
                      <div className="absolute bottom-0 left-0 w-3 h-3 border-b-2 border-l-2 border-[#D4AF37]" />
                      <div className="absolute bottom-0 right-0 w-3 h-3 border-b-2 border-r-2 border-[#D4AF37]" />
                    </div>

                    {/* Countdown indicator */}
                    {countdown !== null && (
                      <div className="absolute inset-0 bg-black/65 flex items-center justify-center text-5xl font-bold text-[#D4AF37] font-mono animate-pulse">
                        {countdown}
                      </div>
                    )}

                    {/* Trigger overlay */}
                    {!countdown && isCameraActive && (
                      <button
                        onClick={handleCapture}
                        className="absolute bottom-3 left-1/2 transform -translate-x-1/2 bg-[#D4AF37] hover:bg-[#C4A030] text-black font-semibold text-[10px] uppercase tracking-widest px-4 py-2 rounded shadow-lg transition-transform hover:scale-105 cursor-pointer"
                      >
                        <Camera className="w-3.5 h-3.5" /> SNAP PORTRAIT
                      </button>
                    )}
                  </>
                )}
              </div>
            )}

            {/* 3. Prebuilt Demos Face selector */}
            {activeTab === 'demos' && (
              <div className="grid grid-cols-2 gap-4 w-full max-w-sm px-2">
                {/* Alex Profile */}
                <button
                  onClick={() => selectDemoProfile('alex')}
                  className="bg-[#050505] p-3 rounded-xl border border-[#222] hover:border-[#D4AF37]/50 flex flex-col items-center hover:bg-[#0c0c0c] transition-all text-center group cursor-pointer"
                >
                  <div className="w-14 h-14 rounded-full overflow-hidden border border-[#222] p-0.5 mb-2 bg-zinc-900 group-hover:scale-105 transition-transform">
                    {/* SVG mini representer */}
                    <svg viewBox="0 0 100 100">
                      <rect width="100" height="100" fill="#022c22" />
                      <circle cx="50" cy="46" r="18" fill="#fbcfe8" />
                      <path d="M30,38 C30,22 40,16 50,16 C60,16 70,22 70,38" fill="#1e293b" />
                      <circle cx="41" cy="45" r="7.5" fill="none" stroke="#22c55e" strokeWidth="2.5" />
                      <circle cx="59" cy="45" r="7.5" fill="none" stroke="#22c55e" strokeWidth="2.5" />
                    </svg>
                  </div>
                  <span className="text-xs font-semibold text-[#E0D8D0]">Alex</span>
                  <span className="text-[10px] text-[#D4AF37] font-mono mt-0.5">Tech Beanie</span>
                </button>

                {/* Chloe Profile */}
                <button
                  onClick={() => selectDemoProfile('chloe')}
                  className="bg-[#050505] p-3 rounded-xl border border-[#222] hover:border-[#D4AF37]/50 flex flex-col items-center hover:bg-[#0c0c0c] transition-all text-center group cursor-pointer"
                >
                  <div className="w-14 h-14 rounded-full overflow-hidden border border-[#222] p-0.5 mb-2 bg-zinc-900 group-hover:scale-105 transition-transform">
                    <svg viewBox="0 0 100 100">
                      <rect width="100" height="100" fill="#4c0519" />
                      <circle cx="50" cy="48" r="17" fill="#fed7aa" />
                      <path d="M31,44 C31,23 40,18 50,18 C60,18 69,23 69,44" fill="#0891b2" />
                      <path d="M29,46 C27,55 29,64 31,69" fill="#06b6d4" />
                      <circle cx="38" cy="51" r="2.5" fill="#f472b6" />
                    </svg>
                  </div>
                  <span className="text-xs font-semibold text-[#E0D8D0]">Chloe</span>
                  <span className="text-[10px] text-[#D4AF37] font-mono mt-0.5">Blue Bob</span>
                </button>
              </div>
            )}
          </div>
        )}
      </div>

      <div className="text-[9px] text-center text-[#555] uppercase tracking-wider mt-3 border-t border-[#222] pt-2 font-mono">
        {selectedSelfie ? 'Reference is held in this session only.' : 'Reference selfie required before matching.'}
      </div>
    </div>
  );
};
