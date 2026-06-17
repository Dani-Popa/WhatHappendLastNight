/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useRef } from 'react';
import { FolderOpen, Sparkles, MapPin, Calendar, Image as ImageIcon, Trash2, PlusCircle, HelpCircle } from 'lucide-react';
import { DEMO_EVENTS } from '../data/demoEvents';
import { CandidatePhoto, DemoEvent } from '../types';

interface AlbumSelectorProps {
  onEventSelected: (event: DemoEvent | null) => void;
  selectedEvent: DemoEvent | null;
  onCustomPhotosLoaded: (photos: CandidatePhoto[]) => void;
  customPhotos: CandidatePhoto[];
  onClearCustom: () => void;
}

export const AlbumSelector: React.FC<AlbumSelectorProps> = ({
  onEventSelected,
  selectedEvent,
  onCustomPhotosLoaded,
  customPhotos,
  onClearCustom,
}) => {
  const [activeTab, setActiveTab] = useState<'presets' | 'custom'>('presets');
  const [isDragOver, setIsDragOver] = useState<boolean>(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const folderInputRef = useRef<HTMLInputElement>(null);

  const handlePresetSelect = (event: DemoEvent) => {
    onEventSelected(event);
  };

  const processFiles = (files: FileList) => {
    const validImageFiles = Array.from(files).filter(file => file.type.startsWith('image/'));
    
    if (validImageFiles.length === 0) return;

    const newPhotos: CandidatePhoto[] = [];
    let processedCount = 0;

    validImageFiles.forEach((file) => {
      const reader = new FileReader();
      reader.onload = () => {
        if (typeof reader.result === 'string') {
          newPhotos.push({
            id: `custom-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
            name: file.name,
            url: URL.createObjectURL(file), // Free memory when cleared
            base64: reader.result,
            size: file.size,
          });
        }
        processedCount++;
        if (processedCount === validImageFiles.length) {
          onCustomPhotosLoaded([...customPhotos, ...newPhotos]);
          onEventSelected(null); // Unselect demo event if custom files are selected
        }
      };
      reader.readAsDataURL(file);
    });
  };

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files.length > 0) {
      processFiles(e.target.files);
    }
  };

  const handleDragOver = (e: React.DragEvent) => {
    e.preventDefault();
    setIsDragOver(true);
  };

  const handleDragLeave = () => {
    setIsDragOver(false);
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    setIsDragOver(false);
    if (e.dataTransfer.files && e.dataTransfer.files.length > 0) {
      processFiles(e.dataTransfer.files);
    }
  };

  const formatSize = (bytes: number) => {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const dm = 1;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
  };

  const totalSizeStr = () => {
    const sum = customPhotos.reduce((acc, curr) => acc + (curr.size || 0), 0);
    return formatSize(sum);
  };

  return (
    <div id="album-module" className="bg-[#080808] rounded-2xl border border-[#222] p-5 flex flex-col h-full">
      {/* Title */}
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-[10px] uppercase tracking-[0.2em] text-[#666] font-medium flex items-center gap-2">
          <FolderOpen className="w-4 h-4 text-[#D4AF37]" />
          2. Source Media
        </h3>
        {customPhotos.length > 0 && activeTab === 'custom' && (
          <button
            onClick={onClearCustom}
            className="text-[9px] uppercase tracking-wider text-red-400 hover:text-red-300 transition-colors flex items-center gap-1 bg-red-950/20 border border-red-500/20 px-2.5 py-1 rounded"
          >
            <Trash2 className="w-3.5 h-3.5" />
            Clear Files
          </button>
        )}
      </div>

      {/* Tabs */}
      <div className="flex space-x-1 p-1 bg-[#050505] border border-[#222] rounded-lg mb-4 text-xs">
        <button
          onClick={() => { setActiveTab('presets'); }}
          className={`flex-1 py-1.5 rounded-md text-[10px] uppercase tracking-wider font-semibold transition-all duration-250 flex items-center justify-center gap-1.5 cursor-pointer ${
            activeTab === 'presets' ? 'bg-[#111] text-[#D4AF37] border border-[#222]/80 shadow-sm' : 'text-[#666] hover:text-[#888]'
          }`}
        >
          <Sparkles className="w-3.5 h-3.5 text-[#D4AF37]" />
          Demo Event Albums
        </button>
        <button
          onClick={() => { setActiveTab('custom'); }}
          className={`flex-1 py-1.5 rounded-md text-[10px] uppercase tracking-wider font-semibold transition-all duration-250 flex items-center justify-center gap-1.5 cursor-pointer ${
            activeTab === 'custom' ? 'bg-[#111] text-[#D4AF37] border border-[#222]/80 shadow-sm' : 'text-[#666] hover:text-[#888]'
          }`}
        >
          <FolderOpen className="w-3.5 h-3.5 text-[#D4AF37]" />
          Scan My Own Folder
        </button>
      </div>

      {/* Main Containers */}
      <div className="flex-1 overflow-y-auto max-h-[360px] pr-1">
        {activeTab === 'presets' ? (
          /* Preset Demo Events */
          <div className="space-y-3">
            {DEMO_EVENTS.map((event) => {
              const isSelected = selectedEvent?.id === event.id;
              return (
                <button
                  key={event.id}
                  onClick={() => handlePresetSelect(event)}
                  className={`w-full text-left p-4 rounded-xl border transition-all duration-200 flex flex-col justify-between relative overflow-hidden group cursor-pointer ${
                    isSelected
                      ? 'bg-[#0A0A0A] border-[#D4AF37]/60 shadow-[0_0_12px_rgba(212,175,55,0.15)]'
                      : 'bg-[#0A0A0A]/40 border-[#222] hover:border-[#444] hover:bg-[#0A0A0A]/80'
                  }`}
                >
                  <div className={`absolute inset-0 bg-opacity-35 opacity-10 transition-opacity group-hover:opacity-15 matches-pattern ${event.coverImage}`} />
                  
                  <div className="relative z-10 w-full">
                    <div className="flex justify-between items-start">
                      <h4 className="text-xs font-semibold text-[#E0D8D0] group-hover:text-[#D4AF37] transition-colors uppercase tracking-wider">
                        {event.name}
                      </h4>
                      {isSelected && (
                        <span className="text-[9px] font-semibold bg-[#111] text-[#D4AF37] px-2 py-0.5 rounded border border-[#333] uppercase font-mono tracking-widest">
                          Active
                        </span>
                      )}
                    </div>
                    <p className="text-[11px] text-[#888] mt-1 lines-clamp-2 leading-relaxed">
                      {event.description}
                    </p>

                    <div className="flex flex-wrap gap-x-4 gap-y-1.5 mt-3 text-[10px] text-[#555] font-mono uppercase tracking-wider">
                      <span className="flex items-center gap-1">
                        <MapPin className="w-3 h-3 text-[#D4AF37]" />
                        {event.location}
                      </span>
                      <span className="flex items-center gap-1">
                        <Calendar className="w-3 h-3 text-[#D4AF37]" />
                        {event.date}
                      </span>
                      <span className="flex items-center gap-1">
                        <ImageIcon className="w-3 h-3 text-[#555]" />
                        {event.photos.length} frames
                      </span>
                    </div>
                  </div>
                </button>
              );
            })}
          </div>
        ) : (
          /* Custom Multi-photo File / Folder Upload */
          <div className="space-y-4">
            {customPhotos.length === 0 ? (
              <div
                onDragOver={handleDragOver}
                onDragLeave={handleDragLeave}
                onDrop={handleDrop}
                className={`border-2 border-dashed rounded-xl p-8 text-center flex flex-col items-center justify-center transition-all ${
                  isDragOver
                    ? 'border-[#D4AF37] bg-[#0A0A0A]/80'
                    : 'border-[#222] bg-[#0C0C0C] hover:border-[#333] hover:bg-[#0A0A0A]'
                }`}
              >
                <FolderOpen className="w-10 h-10 text-[#555] mb-3 animate-pulse" />
                <h4 className="text-xs font-semibold text-[#E0D8D0] uppercase tracking-wider">Indexed Folder Scanners</h4>
                <p className="text-[10px] text-[#666] leading-relaxed max-w-[240px] mt-2">
                  Drag and drop party photos here, or select folders from your local finder/storage.
                </p>

                <div className="flex flex-col sm:flex-row gap-2 mt-4">
                  {/* Select Files Button */}
                  <button
                    onClick={() => fileInputRef.current?.click()}
                    className="bg-[#111] hover:bg-[#1C1C1C] border border-[#222] text-[#888] hover:text-[#E0D8D0] text-[10px] uppercase tracking-wider font-semibold px-4 py-2 rounded-lg flex items-center justify-center gap-1 transition-colors cursor-pointer"
                  >
                    <PlusCircle className="w-3.5 h-3.5 text-[#D4AF37]" />
                    Select Files
                  </button>
                  
                  {/* Select Folder Button - supports WebKit Directory folder picker! */}
                  <button
                    onClick={() => folderInputRef.current?.click()}
                    className="bg-[#D4AF37]/10 hover:bg-[#D4AF37]/25 border border-[#D4AF37]/35 text-[#D4AF37] text-[10px] uppercase tracking-wider font-semibold px-4 py-2 rounded-lg flex items-center justify-center gap-1 transition-colors cursor-pointer"
                  >
                    <FolderOpen className="w-3.5 h-3.5 text-[#D4AF37]" />
                    Select Folder
                  </button>
                </div>

                <input
                  type="file"
                  ref={fileInputRef}
                  accept="image/*"
                  multiple
                  onChange={handleFileChange}
                  className="hidden"
                />

                <input
                  type="file"
                  ref={folderInputRef}
                  accept="image/*"
                  multiple
                  /* @ts-ignore - webkitdirectory directory properties are supported in browsers */
                  webkitdirectory=""
                  directory=""
                  onChange={handleFileChange}
                  className="hidden"
                />
              </div>
            ) : (
              <div id="custom-album-active" className="space-y-3">
                {/* Stats Header */}
                <div className="bg-[#050505] p-3 rounded-xl border border-[#222] flex items-center justify-between">
                  <div className="flex items-center gap-2.5">
                    <div className="p-2 rounded-lg bg-[#D4AF37]/10 border border-[#D4AF37]/30 text-[#D4AF37]">
                      <ImageIcon className="w-4 h-4" />
                    </div>
                    <div>
                      <h4 className="text-xs font-semibold text-[#E0D8D0] uppercase tracking-wider leading-none">Loaded Custom Album</h4>
                      <p className="text-[10px] text-[#666] font-mono mt-1.5 uppercase leading-none">
                        {customPhotos.length} files • {totalSizeStr()}
                      </p>
                    </div>
                  </div>
                  <button
                    onClick={() => fileInputRef.current?.click()}
                    className="text-[9px] text-[#D4AF37] bg-[#111] hover:bg-[#222] px-2.5 py-1.5 rounded font-bold border border-[#333] uppercase tracking-wider flex items-center gap-1 cursor-pointer"
                  >
                    <PlusCircle className="w-2.5 h-2.5" />
                    Add More
                  </button>
                </div>

                {/* Grid layout of thumbnails */}
                <div className="grid grid-cols-4 gap-2 bg-[#050505]/40 p-2 border border-[#222]/80 rounded-xl max-h-[140px] overflow-y-auto">
                  {customPhotos.map((photo, i) => (
                    <div key={photo.id} className="relative aspect-square bg-[#0c0c0c] border border-[#222] rounded-lg overflow-hidden group">
                      <img
                        src={photo.url}
                        alt={photo.name}
                        className="w-full h-full object-cover group-hover:scale-105 transition-transform"
                        referrerPolicy="no-referrer"
                      />
                      <div className="absolute inset-0 bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                        <span className="text-[8px] font-mono text-zinc-300 font-medium truncate px-1 max-w-full">
                          {photo.name}
                        </span>
                      </div>
                    </div>
                  ))}
                </div>

                {/* Helpful tips */}
                <div className="text-[10px] text-[#555] leading-relaxed font-mono flex items-start gap-1.5 bg-[#0A0A0A] p-3 rounded-lg border border-[#222]">
                  <HelpCircle className="w-3.5 h-3.5 text-[#D4AF37] flex-shrink-0 mt-0.5" />
                  <div>
                    <p className="text-[#888] font-semibold uppercase tracking-wider text-[9px]">Using Real Face Detection</p>
                    <p className="mt-1 leading-normal text-[8px] uppercase tracking-wide">
                      By adding your own files, the server uses standard multimodal vision prompts to scan and match faces. Make sure your API key is declared in Settings.
                    </p>
                  </div>
                </div>
              </div>
            )}
          </div>
        )}
      </div>

      <div className="text-[9px] uppercase tracking-wider text-center text-[#555] mt-2 border-t border-[#222] pt-2 font-mono">
        {selectedEvent ? `Loaded: ${selectedEvent.name}.` : customPhotos.length > 0 ? `${customPhotos.length} custom files active.` : 'Select folder or select preset items.'}
      </div>
    </div>
  );
};
