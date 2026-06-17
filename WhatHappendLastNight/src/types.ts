/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

export interface CandidatePhoto {
  id: string;
  name: string;
  url: string; // Object URL for client-side rendering
  size?: number;
}

export interface MatchResult {
  photoId: string;
  isMatch: boolean;
  confidence: number;
  explanation: string;
}

export interface MatchProgress {
  total: number;
  processed: number;
  currentBatch: number;
}

export interface DemoEvent {
  id: string;
  name: string;
  location: string;
  date: string;
  description: string;
  coverImage: string;
  selfies: {
    id: string;
    label: string;
    gender: 'male' | 'female';
    illustrationUrl: string;
  }[];
  photos: {
    id: string;
    illustrationUrl: string;
    tags: string[];
    description: string;
  }[];
}
