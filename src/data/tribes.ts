// ─── Tribe data — i18n via translation keys ───
// Static data: leader names, links, videos (language-independent)
// Translated data: name, description, deliverables, meetingSchedule (via i18n keys)

import { t, type Lang } from '../i18n/utils';

export interface Tribe {
  id: number;
  nameKey: string;
  leader: string;
  leaderLinkedIn: string;
  quadrant: 'q1' | 'q2' | 'q3' | 'q4';
  quadrantLabelKey: string;
  descriptionKey: string;
  deliverableKeys: string[];
  meetingScheduleKey: string;
  videoUrl: string;
  videoDuration: string;
}

/** Resolved tribe with translated strings for a given lang */
export interface ResolvedTribe {
  id: number;
  name: string;
  leader: string;
  leaderLinkedIn: string;
  quadrant: 'q1' | 'q2' | 'q3' | 'q4';
  quadrantLabel: string;
  description: string;
  deliverables: string[];
  meetingSchedule: string;
  videoUrl: string;
  videoDuration: string;
}

export const MAX_SLOTS = 10;
export const MIN_SLOTS = 3;

export const TRIBES: Tribe[] = [
  {
    id: 1,
    nameKey: 'data.tribe1.name',
    leader: 'Hayala Curto, MSc, MBA, PMP®',
    leaderLinkedIn: 'https://www.linkedin.com/in/hayala/',
    quadrant: 'q1',
    quadrantLabelKey: 'data.tribe1.quadrantLabel',
    descriptionKey: 'data.tribe1.desc',
    deliverableKeys: ['data.tribe1.d1', 'data.tribe1.d2', 'data.tribe1.d3'],
    meetingScheduleKey: 'data.tribe1.meetings',
    videoUrl: 'https://www.youtube.com/watch?v=XJLAvcHFKT8',
    videoDuration: '7min',
  },
  {
    id: 2,
    nameKey: 'data.tribe2.name',
    leader: 'Débora Moura',
    leaderLinkedIn: 'https://www.linkedin.com/in/deboralmoura/',
    quadrant: 'q2',
    quadrantLabelKey: 'data.tribe2.quadrantLabel',
    descriptionKey: 'data.tribe2.desc',
    deliverableKeys: ['data.tribe2.d1', 'data.tribe2.d2', 'data.tribe2.d3', 'data.tribe2.d4'],
    meetingScheduleKey: 'data.tribe2.meetings',
    videoUrl: 'https://www.youtube.com/watch?v=HwgjMalJXQE',
    videoDuration: '8min',
  },
  {
    id: 3,
    nameKey: 'data.tribe3.name',
    leader: 'Marcel Fleming',
    leaderLinkedIn: 'https://www.linkedin.com/in/marcelfleming/',
    quadrant: 'q3',
    quadrantLabelKey: 'data.tribe3.quadrantLabel',
    descriptionKey: 'data.tribe3.desc',
    deliverableKeys: ['data.tribe3.d1', 'data.tribe3.d2', 'data.tribe3.d3'],
    meetingScheduleKey: 'data.tribe3.meetings',
    videoUrl: 'https://www.youtube.com/watch?v=vxQ4WLTyKpY',
    videoDuration: '4min',
  },
  {
    id: 4,
    nameKey: 'data.tribe4.name',
    leader: 'Fernando Maquiaveli',
    leaderLinkedIn: 'https://www.linkedin.com/in/fernandomaquiaveli/',
    quadrant: 'q3',
    quadrantLabelKey: 'data.tribe4.quadrantLabel',
    descriptionKey: 'data.tribe4.desc',
    deliverableKeys: ['data.tribe4.d1', 'data.tribe4.d2', 'data.tribe4.d3', 'data.tribe4.d4'],
    meetingScheduleKey: 'data.tribe4.meetings',
    videoUrl: 'https://www.youtube.com/watch?v=LZSk96EsepA',
    videoDuration: '3min',
  },
  {
    id: 5,
    nameKey: 'data.tribe5.name',
    leader: 'Jefferson Pinto',
    leaderLinkedIn: 'https://www.linkedin.com/in/jeffersonpp/',
    quadrant: 'q3',
    quadrantLabelKey: 'data.tribe5.quadrantLabel',
    descriptionKey: 'data.tribe5.desc',
    deliverableKeys: ['data.tribe5.d1', 'data.tribe5.d2', 'data.tribe5.d3', 'data.tribe5.d4'],
    meetingScheduleKey: 'data.tribe5.meetings',
    videoUrl: 'https://www.youtube.com/watch?v=KbhnAJdSeDw',
    videoDuration: '5min',
  },
  {
    id: 6,
    nameKey: 'data.tribe6.name',
    leader: 'Fabricio Costa, PMP',
    leaderLinkedIn: 'https://www.linkedin.com/in/fabriciorcc/',
    quadrant: 'q3',
    quadrantLabelKey: 'data.tribe6.quadrantLabel',
    descriptionKey: 'data.tribe6.desc',
    deliverableKeys: ['data.tribe6.d1', 'data.tribe6.d2', 'data.tribe6.d3', 'data.tribe6.d4'],
    meetingScheduleKey: 'data.tribe6.meetings',
    videoUrl: 'https://www.youtube.com/watch?v=R2fA7hVE1dc',
    videoDuration: '11min',
  },
  {
    id: 7,
    nameKey: 'data.tribe7.name',
    leader: 'Marcos Klemz',
    leaderLinkedIn: 'https://www.linkedin.com/in/maklemz/',
    quadrant: 'q4',
    quadrantLabelKey: 'data.tribe7.quadrantLabel',
    descriptionKey: 'data.tribe7.desc',
    deliverableKeys: ['data.tribe7.d1', 'data.tribe7.d2', 'data.tribe7.d3', 'data.tribe7.d4', 'data.tribe7.d5'],
    meetingScheduleKey: 'data.tribe7.meetings',
    videoUrl: 'https://www.youtube.com/watch?v=3su8GgtFzVY',
    videoDuration: '3min',
  },
  {
    id: 8,
    nameKey: 'data.tribe8.name',
    leader: 'Ana Carla Cavalcante',
    leaderLinkedIn: 'https://www.linkedin.com/in/anacarlacavalcante/',
    quadrant: 'q4',
    quadrantLabelKey: 'data.tribe8.quadrantLabel',
    descriptionKey: 'data.tribe8.desc',
    deliverableKeys: ['data.tribe8.d1', 'data.tribe8.d2', 'data.tribe8.d3', 'data.tribe8.d4'],
    meetingScheduleKey: 'data.tribe8.meetings',
    videoUrl: 'https://www.youtube.com/watch?v=ghrgJ3_nk4k',
    videoDuration: '14min',
  },
];

/** Resolve a tribe's i18n keys to actual strings for the given lang */
export function resolveTribe(tribe: Tribe, lang: Lang): ResolvedTribe {
  return {
    id: tribe.id,
    name: t(tribe.nameKey, lang),
    leader: tribe.leader,
    leaderLinkedIn: tribe.leaderLinkedIn,
    quadrant: tribe.quadrant,
    quadrantLabel: t(tribe.quadrantLabelKey, lang),
    description: t(tribe.descriptionKey, lang),
    deliverables: tribe.deliverableKeys.map(k => t(k, lang)),
    meetingSchedule: t(tribe.meetingScheduleKey, lang),
    videoUrl: tribe.videoUrl,
    videoDuration: tribe.videoDuration,
  };
}

/** Resolve all tribes for a given lang */
export function resolveTribes(lang: Lang): ResolvedTribe[] {
  return TRIBES.map(tribe => resolveTribe(tribe, lang));
}

/** Helper: get resolved tribes by quadrant key */
export function tribesByQuadrant(q: Tribe['quadrant'], lang: Lang): ResolvedTribe[] {
  return TRIBES.filter(t => t.quadrant === q).map(tribe => resolveTribe(tribe, lang));
}
