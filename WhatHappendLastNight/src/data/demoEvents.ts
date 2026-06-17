/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import { DemoEvent } from '../types';

export const DEMO_EVENTS: DemoEvent[] = [
  {
    id: 'underground-boiler-room',
    name: 'Underground Boiler Room',
    location: 'Warehouse District, Detroit',
    date: 'Last Saturday, 11:30 PM',
    description: 'A sweat-drenched, high-energy underground techno set framed by heavy dark shadows and pulsing red strobes.',
    coverImage: 'bg-gradient-to-br from-red-950 via-zinc-900 to-black',
    selfies: [
      {
        id: 'alex-selfie',
        label: 'Alex (Tech Wear & Beanie)',
        gender: 'male',
        illustrationUrl: 'alex'
      },
      {
        id: 'chloe-selfie',
        label: 'Chloe (Glitter & Blue Bob)',
        gender: 'female',
        illustrationUrl: 'chloe'
      }
    ],
    photos: [
      {
        id: 'boiler-1',
        illustrationUrl: 'dj-booth-red',
        tags: ['DJ Booth', 'Lasers', 'Crowd'],
        description: 'Atmospheric shot behind the DJ. A massive crowd dancing in dark shadows with red laser shafts splitting the smoke.'
      },
      {
        id: 'boiler-2',
        illustrationUrl: 'alex-by-speaker',
        tags: ['Speakers', 'Dancefloor'],
        description: 'Alex standing next to a massive sub-bass speaker monitor, wearing his signature black beanie and glowing yellow neon glasses, holding a glowing cup.'
      },
      {
        id: 'boiler-3',
        illustrationUrl: 'girls-dancing',
        tags: ['Main Floor', 'Group Shot'],
        description: 'Two girls laughing and dancing close. Chloe is in the center with her bright blue bob hair-cut, covered in silver glitter cheek paint, smiling.'
      },
      {
        id: 'boiler-4',
        illustrationUrl: 'crowd-wide',
        tags: ['Wide Shot', 'Strobe'],
        description: 'Wide shot from the rafters showing the packed dancefloor. High contrast flashing strobe light capturing several silhouettes.'
      },
      {
        id: 'boiler-5',
        illustrationUrl: 'alex-shadows',
        tags: ['Vibe Shot', 'Strobe'],
        description: 'High contrast black and white strobe candid capturing Alex laughing with a group, neon glasses resting on his nose, beanie tilted back.'
      },
      {
        id: 'boiler-6',
        illustrationUrl: 'chloe-bar',
        tags: ['Bar Area', 'Neon'],
        description: 'Chloe standing near the glowing bar, ordering drinks. Her blue bob hair is catching the red neon bar lighting, wearing a mesh crop top.'
      },
      {
        id: 'boiler-7',
        illustrationUrl: 'smoke-floor',
        tags: ['Smoke Machine', 'Lights'],
        description: 'A couple kissing near the emergency exit under a green spotlight. Thick smoke completely shrouding their legs.'
      }
    ]
  },
  {
    id: 'neon-sky-festival',
    name: 'Neon Sky Festival',
    location: 'Alpine Meadow Grounds',
    date: 'May 23, 2026',
    description: 'An open-air electronic wonderland featuring massive LED screens, cyberpunk projections, and glowing wristbands.',
    coverImage: 'bg-gradient-to-br from-indigo-950 via-slate-900 to-violet-950',
    selfies: [
      {
        id: 'alex-selfie-neon',
        label: 'Alex (Tech Wear & Beanie)',
        gender: 'male',
        illustrationUrl: 'alex'
      },
      {
        id: 'chloe-selfie-neon',
        label: 'Chloe (Glitter & Blue Bob)',
        gender: 'female',
        illustrationUrl: 'chloe'
      }
    ],
    photos: [
      {
        id: 'neon-1',
        illustrationUrl: 'neon-stage-wide',
        tags: ['Main Stage', 'Lasers'],
        description: 'Huge screen visual displaying an abstract magenta sun. Billions of lasers shining over a field of thousands of cheering fans.'
      },
      {
        id: 'neon-2',
        illustrationUrl: 'group-ferris-wheel',
        tags: ['Ferris Wheel', 'Sunset'],
        description: 'Group of friends posing in front of the illuminated Ferris Wheel. Alex is in the group wearing his black beanie, waving with colorful wristbands glowing.'
      },
      {
        id: 'neon-3',
        illustrationUrl: 'chloe-shoulders',
        tags: ['Crowd Close-up', 'Epic Shot'],
        description: 'Chloe sitting up on a friend\'s shoulders under the rainbow confetti blast, holding her hands in a heart shape, blue bob bobbing.'
      },
      {
        id: 'neon-4',
        illustrationUrl: 'rave-group-chill',
        tags: ['Chill Area', 'Hammocks'],
        description: 'A cozy group lounging on a checkered blanket in the grass. Both Alex and Chloe are in the frame, sitting cross-legged, laughing holding glowing cotton candy.'
      }
    ]
  }
];

// Pre-programmed Match Results for Demo Playgrounds
export const DEMO_MATCH_RESULTS: Record<string, Record<string, { isMatch: boolean; confidence: number; explanation: string }>> = {
  'alex-selfie': {
    'boiler-1': { isMatch: false, confidence: 5, explanation: "Alex is not visible. Only silhouettes of the crowd can be seen near the front barrier." },
    'boiler-2': { isMatch: true, confidence: 98, explanation: "Spotted! Alex is standing directly in front of the large speaker stack on the right, wearing his signature black beanie and bright yellow neon round glasses." },
    'boiler-3': { isMatch: false, confidence: 0, explanation: "Alex is not in this shot. This is a close-up of Chloe and her prijatelji on the center floor." },
    'boiler-4': { isMatch: false, confidence: 12, explanation: "No distinct match. While there are similar hat silhouettes in the crowd, no facial features are clearly resolvable." },
    'boiler-5': { isMatch: true, confidence: 92, explanation: "Matched! Alex is seen in high-contrast strobe lighting, laughing in the middle of a lively crowd circle, beanie tilted back." },
    'boiler-6': { isMatch: false, confidence: 2, explanation: "Alex is not present at the bar area in this frame." },
    'boiler-7': { isMatch: false, confidence: 0, explanation: "Only a couple is visible in the smoke. Alex is not in this picture." }
  },
  'chloe-selfie': {
    'boiler-1': { isMatch: false, confidence: 8, explanation: "Chloe is not visible in this crowd wide-shot from the DJ booth." },
    'boiler-2': { isMatch: false, confidence: 0, explanation: "Only Alex and some other ravers are visible by the sound systems." },
    'boiler-3': { isMatch: true, confidence: 99, explanation: "Bingo! Chloe is center-stage, wearing her distinctive blue bob haircut and sparkling face glitter, smiling widely while dancing." },
    'boiler-4': { isMatch: false, confidence: 10, explanation: "She might be in the massive crowd, but no face matches Chloe with sufficient visibility." },
    'boiler-5': { isMatch: false, confidence: 0, explanation: "This frame focuses on Alex and nearby dancers. Chloe is not in the frame." },
    'boiler-6': { isMatch: true, confidence: 95, explanation: "Spotted! Chloe is waiting at the bar under a red neon light bar, her blue hair highly recognizable under the warm overhead tube." },
    'boiler-7': { isMatch: false, confidence: 0, explanation: "Only a couple is visible near the exit doors." }
  },
  'alex-selfie-neon': {
    'neon-1': { isMatch: false, confidence: 3, explanation: "Only generic crowd backs are visible in front of the immense main stage." },
    'neon-2': { isMatch: true, confidence: 96, explanation: "Spotted! Alex is standing third from left in the group line-up, wearing his black beanie with the glowing ferris wheel looping behind him." },
    'neon-3': { isMatch: false, confidence: 0, explanation: "No match. Only Chloe is seen riding on a friend's shoulders." },
    'neon-4': { isMatch: true, confidence: 94, explanation: "Matched! Alex is sitting on the blanket in the chill zone, holding glowing cotton candy and wearing his black beanie." }
  },
  'chloe-selfie-neon': {
    'neon-1': { isMatch: false, confidence: 0, explanation: "Chloe is not in this overhead crowd angle." },
    'neon-2': { isMatch: false, confidence: 5, explanation: "Group photo by the ferris wheel features Alex, but Chloe does not appear to be present in this shot." },
    'neon-3': { isMatch: true, confidence: 98, explanation: "Spotted! Chloe is riding on her friend's shoulders, throwing a heart sign with her hands. Her blue bob and glittery face are highly visible." },
    'neon-4': { isMatch: true, confidence: 92, explanation: "Matched! Chloe is lying near the edge of the blanket in the hammocks area, smiling at her phone with blue hair glowing in the meadow lighting." }
  }
};
