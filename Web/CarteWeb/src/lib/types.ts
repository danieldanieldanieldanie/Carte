export type Side = 'front' | 'back';

export interface UserProfile {
  uid: string;
  username: string;
  number: number;
  createdAt: number;
}

export interface DraftCard {
  frontText: string;
  backText: string;
  photoFile?: File | null;
}

export interface DeliveryCard {
  id: string;
  senderUid: string;
  senderUsername: string;
  senderNumber: number;
  recipientNumber: number;
  recipientUid: string;
  frontText: string;
  backText?: string;
  photoURL?: string;
  photoPath?: string;
  createdAt: number;
}

export interface ArchivedCard extends DeliveryCard {
  archivedAt: number;
  localPhotoDataURL?: string;
}
