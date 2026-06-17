/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState } from 'react';
import {
  Sparkles,
  Camera,
  FolderOpen,
  HelpCircle,
  CheckCircle2,
  Trash2,
  Maximize2,
  Download,
  RefreshCw,
  AlertCircle,
  X,
  ArrowRight,
  MapPin,
  Calendar,
  ChevronRight,
  Lock,
} from 'lucide-react';
import { CameraSelfie } from './components/CameraSelfie';
import { AlbumSelector } from './components/AlbumSelector';
import { PartyPhotoRenderer } from './components/PartyPhotoRenderer';
import { DEMO_MATCH_RESULTS } from './data/demoEvents';
import { CandidatePhoto, MatchResult, MatchProgress, DemoEvent } from './types';

export default function App() {
  // Selfie State
  const [selfie, setSelfie] = useState<string | null>(null);
  const [isSelfieDemo, setIsSelfieDemo] = useState<boolean>(false);
  const [selfieDemoId, setSelfieDemoId] = useState<string | null>(null);

  // Album Selection State
  const [selectedEvent, setSelectedEvent] = useState<DemoEvent | null>(null);
  const [customPhotos, setCustomPhotos] = useState<CandidatePhoto[]>([]);

  // Scanning State
  const [matches, setMatches] = useState<Record<string, MatchResult>>({});
  const [matchStatus, setMatchStatus] = useState<'idle' | 'matching' | 'completed' | 'error'>('idle');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [progress, setProgress] = useState<MatchProgress | null>(null);
  const [activeScanFeedback, setActiveScanFeedback] = useState<string>('Initializing matching core...');
  const [isPrivacyAccepted, setIsPrivacyAccepted] = useState<boolean>(false);

  // Navigation Filter
  const [filterTab, setFilterTab] = useState<'matches' | 'unmatched' | 'all'>('matches');

  // Zoom Modal State
  const [selectedPhotoForModal, setSelectedPhotoForModal] = useState<{
    id: string;
    url?: string;
    illustrationUrl?: string;
    name?: string;
    description: string;
    matchResult?: MatchResult;
  } | null>(null);

  // Handle Selfie callback
  const handleSelfieSelected = (referenceImage: string | null, isDemo: boolean = false, demoId: string | null = null) => {
    setSelfie(referenceImage);
    setIsSelfieDemo(isDemo);
    setSelfieDemoId(demoId);
    // Clear matches if selfie is changed to force fresh scan
    setMatches({});
    setMatchStatus('idle');
  };

  // Handle preset selector
  const handleEventSelected = (event: DemoEvent | null) => {
    setSelectedEvent(event);
    if (event) {
      customPhotos.forEach((photo) => URL.revokeObjectURL(photo.url));
      setCustomPhotos([]);
    }
    setMatches({});
    setMatchStatus('idle');
  };

  // Handle custom photo uploads
  const handleCustomPhotosLoaded = (photos: CandidatePhoto[]) => {
    setCustomPhotos(photos);
    setSelectedEvent(null);
    setMatches({});
    setMatchStatus('idle');
  };

  // Clear all custom uploads
  const handleClearCustom = () => {
    // Revoke object URLs to avoid client-side memory leaks
    customPhotos.forEach((photo) => URL.revokeObjectURL(photo.url));
    setCustomPhotos([]);
    setMatches({});
    setMatchStatus('idle');
  };

  const handleClearSession = () => {
    customPhotos.forEach((photo) => URL.revokeObjectURL(photo.url));
    setSelfie(null);
    setIsSelfieDemo(false);
    setSelfieDemoId(null);
    setSelectedEvent(null);
    setCustomPhotos([]);
    setMatches({});
    setMatchStatus('idle');
    setErrorMessage(null);
    setProgress(null);
    setSelectedPhotoForModal(null);
    setIsPrivacyAccepted(false);
  };

  const handleRunScan = async () => {
    if (!selfie) return;

    if (!isPrivacyAccepted) {
      setErrorMessage('Please confirm the privacy notice before running any face comparison.');
      setMatchStatus('idle');
      return;
    }

    setErrorMessage(null);

    // Scenario A: Both are presets/demos, run interactive simulated scan
    if (isSelfieDemo && selectedEvent) {
      setMatchStatus('matching');
      const feedbackPhrases = [
        'Caching reference face vectors...',
        'Analyzing hairstyle & bone structure...',
        'Comparing clothing color profiles...',
        'Filtering crowd backgrounds...',
        'Deducing coordinate positions...',
        'Submitting match ratings...',
      ];

      setProgress({ total: selectedEvent.photos.length, processed: 0, currentBatch: 1 });
      
      const totalPhotos = selectedEvent.photos.length;
      for (let i = 1; i <= totalPhotos; i++) {
        // Stagger updates for a beautiful cyberpunk scanning illusion
        const phraseIdx = Math.floor((i / totalPhotos) * feedbackPhrases.length);
        setActiveScanFeedback(feedbackPhrases[phraseIdx] || 'Finishing analysis...');
        await new Promise((resolve) => setTimeout(resolve, 450));
        setProgress({ total: totalPhotos, processed: i, currentBatch: 1 });
      }

      const selfieId = selfieDemoId || '';
      const eventResults = DEMO_MATCH_RESULTS[selfieId] || {};

      const finalMatches: Record<string, MatchResult> = {};
      selectedEvent.photos.forEach((photo) => {
        const match = eventResults[photo.id] || {
          isMatch: false,
          confidence: 0,
          explanation: 'No visual traits matches this identity.',
        };
        finalMatches[photo.id] = {
          photoId: photo.id,
          isMatch: match.isMatch,
          confidence: match.confidence,
          explanation: match.explanation,
        };
      });

      setMatches(finalMatches);
      setMatchStatus('completed');
      setFilterTab('matches');
      return;
    }

    if (customPhotos.length > 0) {
      setErrorMessage('Custom photo face matching is disabled in the web prototype to avoid uploading personal images. Use the native macOS app for local-only custom matching.');
      setMatchStatus('idle');
      setProgress(null);
      return;
    }

    if (customPhotos.length === 0) {
      setErrorMessage('Please select a custom folder / upload party photos, or select a Demo Preset combination to scan.');
      setMatchStatus('idle');
      return;
    }
  };

  // Helper lists of photos based on chosen modes
  const getDisplayPhotos = () => {
    if (selectedEvent) {
      return selectedEvent.photos.map((p) => ({
        id: p.id,
        illustrationUrl: p.illustrationUrl,
        name: `photo-${p.id}`,
        description: p.description,
        tags: p.tags,
      }));
    }
    return customPhotos.map((p) => ({
      id: p.id,
      url: p.url,
      name: p.name,
      description: 'Your uploaded party photograph file.',
      tags: ['Uploaded File'],
    }));
  };

  const displayPhotos = getDisplayPhotos();

  // Matched counts
  const matchesList = displayPhotos.filter((p) => {
    const m = matches[p.id];
    return m && m.isMatch;
  });

  const unmatchedList = displayPhotos.filter((p) => {
    const m = matches[p.id];
    return m && !m.isMatch;
  });

  const getFilteredPhotos = () => {
    if (matchStatus !== 'completed') return displayPhotos;
    if (filterTab === 'matches') return matchesList;
    if (filterTab === 'unmatched') return unmatchedList;
    return displayPhotos;
  };

  const filteredPhotos = getFilteredPhotos();

  // Save/Download dynamic photo files
  const handleDownloadPhoto = (photo: typeof displayPhotos[0], matchResult?: MatchResult) => {
    if (photo.url) {
      // It is a real blob custom photo uploaded by the user
      const a = document.createElement('a');
      a.href = photo.url;
      a.download = `spotted-${photo.name || 'party-photo.jpg'}`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
    } else {
      // For demo event, simulate/visualize download success with a native browser message, or make a mock download
      const svgElement = document.getElementById(`illustration-${photo.illustrationUrl}`);
      if (svgElement) {
        // We present a simulated download trigger
        alert(`"What Happened Last Night" simulation: Saved "${photo.id}.jpg" (Confidence: ${matchResult?.confidence || 98}%) directly to downloads!`);
      }
    }
  };

  return (
    <div className="min-h-screen bg-[#050505] text-[#E0D8D0] flex flex-col font-sans selection:bg-[#D4AF37] selection:text-black transition-colors duration-300 relative overflow-hidden">
      
      {/* Subtle gold elegant background glow */}
      <div className="absolute top-[-10%] left-[-10%] w-[45vw] h-[45vw] rounded-full bg-[#D4AF37]/5 blur-[130px] pointer-events-none" />
      <div className="absolute bottom-[-10%] right-[-10%] w-[40vw] h-[40vw] rounded-full bg-[#D4AF37]/3 blur-[120px] pointer-events-none" />

      {/* Primary Header */}
      <header className="border-b border-[#222] bg-[#050505] sticky top-0 z-40 py-4 px-6 flex justify-between items-center transition-all shadow-sm">
        <div className="flex items-center gap-4">
          <div className="w-10 h-10 border border-[#333] rounded-full flex items-center justify-center">
            <div className="w-4 h-4 bg-[#D4AF37] rounded-full shadow-[0_0_12px_rgba(212,175,55,0.6)]"></div>
          </div>
          <div>
            <h1 className="text-2xl tracking-normal font-light italic font-serif leading-none text-[#E0D8D0]" style={{ fontFamily: 'Georgia, serif' }}>
              What Happened Last Night
            </h1>
            <p className="text-[9px] uppercase tracking-[0.2em] font-medium text-[#666] mt-1.5 font-sans">
              PARTY PIC SEARCH / FACIAL RECOGNITION V1
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2 text-[10px] bg-[#0A0A0A] border border-[#222] px-3 py-1.5 rounded-lg text-[#888] font-mono uppercase tracking-wider">
          <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse" />
          <span>No Upload Mode</span>
        </div>
      </header>

      {/* Main Content Workspace Layout */}
      <main className="max-w-7xl mx-auto p-4 md:p-6 w-full flex-1 grid grid-cols-1 md:grid-cols-12 gap-6 items-start z-10">
        
        {/* LEFT COLUMN: Setup Configuration (Selfie, Directory Upload) */}
        <section className="md:col-span-5 flex flex-col gap-6">
          <CameraSelfie
            onSelfieSelected={handleSelfieSelected}
            selectedSelfie={selfie}
            selectedDemoId={isSelfieDemo ? selfieDemoId : null}
          />
          <AlbumSelector
            onEventSelected={handleEventSelected}
            selectedEvent={selectedEvent}
            onCustomPhotosLoaded={handleCustomPhotosLoaded}
            customPhotos={customPhotos}
            onClearCustom={handleClearCustom}
          />
        </section>

        {/* RIGHT COLUMN: Running Scans and Viewing filtered Matches */}
        <section className="md:col-span-7 flex flex-col gap-6 w-full h-full">
          
          {/* Diagnostic Active Scanner Trigger Deck */}
          <div className="bg-[#080808] border border-[#222] rounded-2xl p-5 relative overflow-hidden flex flex-col justify-between">
            <div className="absolute inset-0 bg-gradient-to-r from-[#D4AF37]/5 via-transparent to-amber-500/3" />
            
            <div className="relative z-10">
              <h3 className="text-[10px] uppercase tracking-[0.2em] text-[#666] font-medium flex items-center gap-2 mb-3">
                <Sparkles className="w-4 h-4 text-[#D4AF37]" />
                3. Face-Detection Core
              </h3>

              {/* Status summary taglines */}
              <div className="grid grid-cols-2 gap-3 mb-4 text-xs">
                <div className="bg-[#050505] p-2.5 rounded-xl border border-[#222] flex flex-col gap-1 leading-relaxed">
                  <span className="text-[#555] font-mono text-[9px] uppercase tracking-wider">Face Target</span>
                  <span className="font-semibold text-[#E0D8D0] uppercase tracking-wide text-[10px]">
                    {selfie ? (isSelfieDemo ? 'ALEX/CHLOE BIOMETRIC' : 'CUSTOM RECOGNITION') : 'NONE REGISTERED'}
                  </span>
                </div>
                <div className="bg-[#050505] p-2.5 rounded-xl border border-[#222] flex flex-col gap-1 leading-relaxed">
                  <span className="text-[#555] font-mono text-[9px] uppercase tracking-wider">Search Corpus</span>
                  <span className="font-semibold text-[#E0D8D0] uppercase tracking-wide text-[10px]">
                    {selectedEvent ? selectedEvent.name : customPhotos.length > 0 ? `${customPhotos.length} custom images` : 'None Loaded'}
                  </span>
                </div>
              </div>

              <div className="bg-[#050505] border border-[#222] rounded-xl p-3 mb-4 text-[10px] text-[#777] leading-relaxed">
                <label className="flex items-start gap-2 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={isPrivacyAccepted}
                    onChange={(event) => setIsPrivacyAccepted(event.target.checked)}
                    className="mt-0.5 accent-[#D4AF37]"
                  />
                  <span>
                    I understand this browser prototype keeps custom images in temporary browser memory and does not upload them for matching. Demo scans are simulated; real custom matching should use the offline native app.
                  </span>
                </label>
                <button
                  onClick={handleClearSession}
                  className="mt-2 text-[9px] uppercase tracking-wider text-red-400 hover:text-red-300 transition-colors flex items-center gap-1"
                >
                  <Trash2 className="w-3.5 h-3.5" />
                  Clear Browser Session
                </button>
              </div>
            </div>

            {/* ERROR CARD INSIDE WORKSPACE */}
            {errorMessage && (
              <div className="p-3 bg-red-950/25 border border-red-500/25 rounded-xl mb-4 text-xs text-red-300 leading-relaxed flex items-start gap-2.5 animate-bounce">
                <AlertCircle className="w-4 h-4 text-red-400 mt-0.5 flex-shrink-0" />
                <div>
                  <p className="font-semibold text-red-200">Privacy Notice</p>
                  <p className="text-[11px] text-red-400/90 mt-0.5 whitespace-pre-wrap">{errorMessage}</p>
                </div>
              </div>
            )}

            {/* SCANNING ACTIVE INDICATORS */}
            {matchStatus === 'matching' && progress && (
              <div className="border border-[#D4AF37]/30 bg-[#050505] p-4 rounded-xl mb-4 text-xs relative overflow-hidden">
                <div className="absolute top-0 inset-x-0 h-0.5 bg-gradient-to-r from-transparent via-[#D4AF37] to-transparent animate-pulse" />
                <div className="flex justify-between font-mono text-[10px] text-[#D4AF37] uppercase tracking-widest mb-1.5">
                  <span className="animate-pulse">{activeScanFeedback}</span>
                  <span>Batch {progress.currentBatch}</span>
                </div>
                {/* Visual bar */}
                <div className="w-full h-2 bg-[#050505] rounded-full overflow-hidden border border-[#222]">
                  <div
                    className="h-full bg-gradient-to-r from-[#D4AF37] to-amber-500 transition-all duration-300 rounded-full"
                    style={{ width: `${(progress.processed / progress.total) * 100}%` }}
                  />
                </div>
                <div className="flex justify-between text-[10px] text-[#555] font-mono mt-1.5 leading-none uppercase tracking-wider">
                  <span>Processed {progress.processed} of {progress.total} photos</span>
                  <span>{Math.round((progress.processed / progress.total) * 100)}% Complete</span>
                </div>
              </div>
            )}

            {/* RUN BUTTON */}
            <button
              id="cta-scan-trigger"
              disabled={!selfie || !isPrivacyAccepted || (customPhotos.length === 0 && !selectedEvent) || matchStatus === 'matching'}
              onClick={handleRunScan}
              className={`w-full py-3.5 px-4 rounded-xl font-bold tracking-widest text-[10px] uppercase transition-all duration-300 flex items-center justify-center gap-2 shadow-lg filter ${
                !selfie || !isPrivacyAccepted || (customPhotos.length === 0 && !selectedEvent)
                  ? 'bg-[#111] text-[#444] border border-[#222] border-dashed cursor-not-allowed shadow-none'
                  : matchStatus === 'matching'
                  ? 'bg-black text-[#D4AF37] border border-[#D4AF37]/40 cursor-not-allowed'
                  : 'bg-[#D4AF37] hover:bg-[#C4A030] text-black cursor-pointer hover:shadow-[#D4AF37]/10 hover:scale-[1.01]'
              }`}
            >
              {matchStatus === 'matching' ? (
                <>
                  <RefreshCw className="w-4 h-4 animate-spin text-[#D4AF37]" />
                  ANALYZING PHOTOGRAPHS...
                </>
              ) : (
                <>
                  <Sparkles className="w-4 h-4 text-black animate-pulse" />
                  Trigger Demo Scanner
                </>
              )}
            </button>
          </div>

          {/* MAIN RESULTS ALBUM FRAME */}
          <div className="bg-[#080808] rounded-2xl border border-[#222] p-5 flex-1 flex flex-col min-h-[300px]">
            
            {/* Navigational Tabs to filter Matches */}
            <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center border-b border-[#222] pb-3 mb-4 gap-3">
              <div>
                <h3 className="text-xs font-semibold tracking-wider text-[#E0D8D0] uppercase">Matched Result Albums</h3>
                <p className="text-[10px] text-[#555] font-mono mt-1 uppercase tracking-wider">
                  {matchStatus === 'completed' ? `Found ${matchesList.length} matching photos.` : 'Photo grid standby.'}
                </p>
              </div>
              
              {/* Tab Filters */}
              {matchStatus === 'completed' && (
                <div className="flex space-x-0.5 p-0.5 bg-[#050505] border border-[#222] rounded-lg text-[9px] uppercase tracking-wider font-mono">
                  <button
                    onClick={() => setFilterTab('matches')}
                    className={`px-2.5 py-1 rounded font-medium transition-colors cursor-pointer ${
                      filterTab === 'matches'
                        ? 'bg-[#111] border border-[#222] text-[#D4AF37]'
                        : 'text-[#666] hover:text-[#888]'
                    }`}
                  >
                    Matches ({matchesList.length})
                  </button>
                  <button
                    onClick={() => setFilterTab('unmatched')}
                    className={`px-2.5 py-1 rounded font-medium transition-colors cursor-pointer ${
                      filterTab === 'unmatched'
                        ? 'bg-[#111] text-[#666] border border-transparent'
                        : 'text-[#666] hover:text-[#888]'
                    }`}
                  >
                    Unmatched ({unmatchedList.length})
                  </button>
                  <button
                    onClick={() => setFilterTab('all')}
                    className={`px-2.5 py-1 rounded font-medium transition-colors cursor-pointer ${
                      filterTab === 'all'
                        ? 'bg-[#111] text-[#666] border border-transparent'
                        : 'text-[#666] hover:text-[#888]'
                    }`}
                  >
                    All ({displayPhotos.length})
                  </button>
                </div>
              )}
            </div>

            {/* Candidate / Matches list rendering */}
            {displayPhotos.length === 0 ? (
              <div className="flex-1 flex flex-col items-center justify-center text-center py-10 opacity-75">
                <FolderOpen className="w-12 h-12 text-[#333] mb-2.5" />
                <p className="text-xs font-semibold text-[#888] uppercase tracking-wider">No photos loaded</p>
                <p className="text-[10px] text-[#555] max-w-[240px] mt-1.5 leading-relaxed uppercase tracking-wide">
                  Toggle the preset events or drag directory folder structures under step 2 to index album snapshots first.
                </p>
              </div>
            ) : matchStatus === 'idle' ? (
              <div className="flex-1 flex flex-col items-center justify-center text-center py-10">
                <div className="relative mb-3 flex items-center justify-center">
                  <div className="w-12 h-12 rounded-full border border-dashed border-[#222] animate-spin" />
                  <Sparkles className="w-5 h-5 text-[#D4AF37] absolute animate-pulse" />
                </div>
                <p className="text-xs font-semibold text-[#888] uppercase tracking-wider">Ready for Scan</p>
                <p className="text-[10px] text-[#555] max-w-[240px] mt-1.5 leading-relaxed uppercase tracking-wider">
                  We have loaded {displayPhotos.length} photo candidate cards. Check your selfie reference setup and click the trigger above.
                </p>
              </div>
            ) : (
              /* Grid Layout of photos */
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 flex-1">
                {filteredPhotos.map((photo) => {
                  const m = matches[photo.id];
                  return (
                    <div
                      key={photo.id}
                      className="bg-[#050505]/60 rounded-xl border border-[#222] overflow-hidden flex flex-col group hover:border-[#444] hover:bg-[#070707] transition-all duration-250 hover:shadow-lg"
                    >
                      {/* Image Viewer Container */}
                      <div className="relative aspect-square overflow-hidden bg-black border-b border-[#222]">
                        {photo.illustrationUrl ? (
                          <PartyPhotoRenderer
                            illustrationId={photo.illustrationUrl}
                            className="w-full h-full"
                          />
                        ) : (
                          <img
                            src={photo.url}
                            alt={photo.name}
                            className="w-full h-full object-cover group-hover:scale-[1.02] transition-transform duration-300"
                            referrerPolicy="no-referrer"
                          />
                        )}

                        {/* Top corner confidence badge */}
                        {m && (
                          <div className={`absolute top-2.5 right-2.5 text-[9px] font-mono font-bold tracking-wider uppercase px-2 py-1 rounded shadow-md z-10 ${
                            m.isMatch
                              ? 'bg-emerald-950/80 border border-emerald-500/20 text-emerald-400 animate-pulse'
                              : 'bg-red-950/80 border border-red-500/20 text-red-200'
                          }`}>
                            {m.isMatch ? `Spotted: ${m.confidence}%` : 'Unmatched'}
                          </div>
                        )}

                        {/* Magnifying overlay action */}
                        <button
                          onClick={() => setSelectedPhotoForModal({ ...photo, matchResult: m })}
                          className="absolute inset-0 bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center gap-1.5 focus:opacity-100 z-10 cursor-pointer"
                        >
                          <Maximize2 className="w-4 h-4 text-[#D4AF37]" />
                          <span className="text-[9px] font-semibold text-[#D4AF37] tracking-widest uppercase font-mono">Zoom View</span>
                        </button>
                      </div>

                      {/* Info & explanations block */}
                      <div className="p-3.5 flex-1 flex flex-col justify-between">
                        <div>
                          {/* Tags row */}
                          <div className="flex flex-wrap gap-1 mb-2">
                            {photo.tags.map((tag) => (
                              <span key={tag} className="text-[9px] font-mono px-1.5 py-0.5 rounded bg-[#0A0A0A] border border-[#222] text-[#666] uppercase">
                                #{tag}
                              </span>
                            ))}
                          </div>

                          <p className="text-[11px] text-[#A0A0A0] leading-relaxed block italic pr-1">
                            {photo.description}
                          </p>

                          {m && m.isMatch && (
                            <div className="mt-3 p-2 bg-emerald-950/10 border border-emerald-500/10 rounded text-[10px] leading-relaxed text-emerald-300/80 font-sans">
                              {m.explanation}
                            </div>
                          )}
                        </div>

                        {/* Card bottom actions */}
                        <div className="mt-3.5 pt-2.5 border-t border-[#222] flex justify-between items-center h-5">
                          <span className="text-[9px] font-mono text-[#555] truncate max-w-[120px] uppercase tracking-wider">
                            {photo.name || photo.id}
                          </span>
                          <button
                            onClick={() => handleDownloadPhoto(photo, m)}
                            className="text-[9px] text-[#D4AF37] hover:text-[#C4A030] font-mono font-bold tracking-wider uppercase transition-colors flex items-center gap-1 leading-none cursor-pointer"
                          >
                            <Download className="w-3.5 h-3.5" />
                            SAVE FILE
                          </button>
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </section>
      </main>

      {/* DETAIL SIDE-BY-SIDE VERIFICATION MODAL */}
      {selectedPhotoForModal && (
        <div className="fixed inset-0 bg-black/90 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-[#080808] border border-[#222] rounded-2xl w-full max-w-3xl overflow-hidden shadow-2xl relative animate-scale-up max-h-[90vh] flex flex-col">
            
            {/* Close trigger */}
            <button
              onClick={() => setSelectedPhotoForModal(null)}
              className="absolute top-4 right-4 text-[#888] hover:text-[#E0D8D0] bg-[#050505] p-2 rounded-full border border-[#222] z-12 cursor-pointer transition-all duration-200 hover:rotate-90 animate-fade-in"
            >
              <X className="w-4 h-4" />
            </button>

            {/* Modal Header */}
            <div className="p-4 border-b border-[#222] bg-[#050505] flex flex-col pr-14 leading-tight">
              <h4 className="text-xs font-semibold text-white tracking-widest uppercase font-sans flex items-center gap-2">
                <Maximize2 className="w-4 h-4 text-[#D4AF37] animate-pulse" />
                Identity Match Verification Detail
              </h4>
              <p className="text-[9px] text-[#555] mt-1.5 font-mono uppercase tracking-wider">Comparing demo alignment details against the selected reference.</p>
            </div>

            {/* Main Side-by-Side Area */}
            <div className="flex-1 overflow-y-auto p-5 grid grid-cols-1 md:grid-cols-5 gap-6">
              
              {/* Reference Selfie Left Panel */}
              <div className="md:col-span-2 flex flex-col gap-3">
                <span className="text-[9px] font-mono uppercase tracking-widest text-[#888] flex items-center gap-1.5">
                  <Lock className="w-3.5 h-3.5 text-[#D4AF37]" />
                  Target Identity Ref
                </span>
                <div className="aspect-square bg-black border border-dashed border-[#D4AF37]/40 rounded-xl overflow-hidden p-1.5 flex items-center justify-center">
                  {isSelfieDemo && selfieDemoId ? (
                    <div className="w-full h-full flex items-center justify-center bg-zinc-900 rounded-lg overflow-hidden">
                      {selfieDemoId.includes('alex') ? (
                        <svg viewBox="0 0 100 100" className="w-full h-full">
                          <rect width="100" height="100" fill="#022c22" />
                          <circle cx="50" cy="46" r="18" fill="#fbcfe8" />
                          <path d="M30,38 C30,22 40,16 50,16 C60,16 70,22 70,38" fill="#1e293b" />
                          <circle cx="41" cy="45" r="7.5" fill="none" stroke="#22c55e" strokeWidth="2.5" />
                          <circle cx="59" cy="45" r="7.5" fill="none" stroke="#22c55e" strokeWidth="2.5" />
                        </svg>
                      ) : (
                        <svg viewBox="0 0 100 100" className="w-full h-full">
                          <rect width="100" height="100" fill="#4c0519" />
                          <circle cx="50" cy="48" r="17" fill="#fed7aa" />
                          <path d="M31,44 C31,23 40,18 50,18 C60,18 69,23 69,44" fill="#0891b2" />
                          <path d="M29,46 C27,55 29,64 31,69" fill="#06b6d4" />
                          <circle cx="38" cy="51" r="2.5" fill="#f472b6" />
                        </svg>
                      )}
                    </div>
                  ) : (
                    <img
                      src={selfie || ''}
                      alt="Ref Selfie"
                      className="w-full h-full object-cover rounded-lg"
                      referrerPolicy="no-referrer"
                    />
                  )}
                </div>
                <div className="bg-[#050505] border border-[#222] p-2.5 rounded text-[9px] text-[#555] font-mono leading-relaxed uppercase tracking-wider">
                  <span className="text-[#888] font-bold block mb-1">REFERENCE DETAILS:</span>
                  <span>Reference preview is held in browser memory for this session only.</span>
                </div>
              </div>

              {/* Event cand photo zoom Right Panel */}
              <div className="md:col-span-3 flex flex-col gap-3">
                <span className="text-[9px] font-mono uppercase tracking-widest text-[#888] flex items-center gap-1.5">
                  <CheckCircle2 className="w-3.5 h-3.5 text-[#D4AF37]" />
                  Candidate Party Frame
                </span>
                <div className="aspect-square bg-black border border-[#222] rounded-xl overflow-hidden relative">
                  {selectedPhotoForModal.illustrationUrl ? (
                    <PartyPhotoRenderer
                      illustrationId={selectedPhotoForModal.illustrationUrl}
                      className="w-full h-full"
                    />
                  ) : (
                    <img
                      src={selectedPhotoForModal.url}
                      alt="Full Zoom"
                      className="w-full h-full object-cover"
                      referrerPolicy="no-referrer"
                    />
                  )}
                </div>

                <div className="flex flex-wrap gap-1.5">
                  {selectedPhotoForModal.tags?.map((tag) => (
                    <span key={tag} className="text-[9px] font-mono px-2 py-0.5 rounded bg-black border border-[#222] text-[#555] uppercase tracking-wide">
                      #{tag}
                    </span>
                  ))}
                </div>
              </div>

            </div>

            {/* Modal Bottom Analysis Drawer */}
            <div className="p-4 bg-[#050505] border-t border-[#222] flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3">
              <div className="flex-1 leading-relaxed">
                {selectedPhotoForModal.matchResult ? (
                  <div className="flex items-start gap-2 max-w-sm sm:max-w-md">
                    {selectedPhotoForModal.matchResult.isMatch ? (
                      <span className="text-[9px] bg-emerald-950/80 text-emerald-400 px-2.5 py-1 rounded border border-emerald-800/40 font-mono font-bold tracking-widest uppercase mt-0.5">
                        Matched!
                      </span>
                    ) : (
                      <span className="text-[9px] bg-red-950/80 text-red-200 px-2.5 py-1 rounded border border-red-800/40 font-mono font-bold tracking-widest uppercase mt-0.5">
                        Miss
                      </span>
                    )}
                    <span className="text-[11px] text-[#A0A0A0] leading-relaxed block mt-0.5">
                      {selectedPhotoForModal.matchResult.explanation}
                    </span>
                  </div>
                ) : (
                  <p className="text-[10px] text-[#555] font-mono uppercase tracking-wider">No scanner matches have run for this candidate card yet.</p>
                )}
              </div>

              <div className="flex gap-2">
                <button
                  onClick={() => setSelectedPhotoForModal(null)}
                  className="bg-[#111] hover:bg-[#222] border border-[#222] px-3.5 py-1.5 rounded text-[10px] uppercase tracking-widest font-bold text-[#888] hover:text-[#E0D8D0] cursor-pointer"
                >
                  Close
                </button>
                <button
                  onClick={() => handleDownloadPhoto(selectedPhotoForModal as any, selectedPhotoForModal.matchResult)}
                  className="bg-[#D4AF37] hover:bg-[#C4A030] text-black font-bold px-3.5 py-1.5 rounded text-[10px] uppercase tracking-widest cursor-pointer flex items-center gap-1.5 transition-colors"
                >
                  <Download className="w-3.5 h-3.5" />
                  Save Photo
                </button>
              </div>
            </div>

          </div>
        </div>
      )}

      {/* Footer Branding */}
      <footer className="border-t border-[#222] bg-[#050505] py-6 px-8 flex flex-col sm:flex-row justify-between items-center gap-3 text-[9px] text-[#555] font-mono uppercase tracking-widest mt-12">
        <span className="text-center sm:text-left">© 2026 What Happened Last Night. All rights protected.</span>
        <span className="flex items-center gap-3">
          <span>Offline-first face comparison prototype</span>
          <span className="w-1.5 h-1.5 rounded-full bg-[#D4AF37] opacity-60" />
          <span>No unsolicited databases or trackers</span>
        </span>
      </footer>

    </div>
  );
}
