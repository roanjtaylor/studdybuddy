export type Source = {
  title: string;
  author: string;
  url: string;
  kind: 'essay' | 'paper' | 'lecture' | 'book' | 'talk' | 'other';
  timeCost: string;
  whyCanonical: string;
  blurb: string;
  coreIdea: string;
};

export type StudyCard = {
  id: string;
  topic: string;
  firstPrinciples: string[];
  sources: Source[];
  createdAt: number;
};
