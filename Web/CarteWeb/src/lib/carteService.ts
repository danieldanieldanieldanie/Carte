import {
  createUserWithEmailAndPassword,
  signInWithEmailAndPassword,
  signOut,
  type User,
} from 'firebase/auth';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  limit,
  onSnapshot,
  orderBy,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  where,
  type Unsubscribe,
} from 'firebase/firestore';
import { deleteObject, getDownloadURL, ref, uploadBytes } from 'firebase/storage';
import { auth, db, storage } from './firebase';
import { normalizeUsername, usernameToEmail, validateUsername } from './validation';
import type { DeliveryCard, DraftCard, UserProfile } from './types';

interface FirestoreDelivery {
  senderUid: string;
  senderUsername: string;
  senderNumber: number;
  recipientNumber: number;
  recipientUid: string;
  frontText: string;
  backText?: string;
  photoURL?: string;
  photoPath?: string;
  createdAt?: { toMillis: () => number } | number;
}

export async function signUpWithUsername(username: string, password: string): Promise<UserProfile> {
  const usernameError = validateUsername(username);
  if (usernameError) throw new Error(usernameError);
  const normalized = normalizeUsername(username);
  const credential = await createUserWithEmailAndPassword(auth, usernameToEmail(normalized), password);
  return ensureProfile(credential.user, normalized);
}

export async function logInWithUsername(username: string, password: string): Promise<UserProfile> {
  const normalized = normalizeUsername(username);
  const credential = await signInWithEmailAndPassword(auth, usernameToEmail(normalized), password);
  return ensureProfile(credential.user, normalized);
}

export async function logOut(): Promise<void> {
  await signOut(auth);
}

export async function loadProfile(user: User): Promise<UserProfile | null> {
  const snapshot = await getDoc(doc(db, 'profiles', user.uid));
  return snapshot.exists() ? (snapshot.data() as UserProfile) : null;
}

export async function ensureProfile(user: User, username: string): Promise<UserProfile> {
  const normalized = normalizeUsername(username);
  const profileRef = doc(db, 'profiles', user.uid);
  const usernameRef = doc(db, 'usernames', normalized);
  const counterRef = doc(db, 'system', 'numberCounter');

  return runTransaction(db, async (transaction) => {
    const existing = await transaction.get(profileRef);
    if (existing.exists()) return existing.data() as UserProfile;

    const usernameDoc = await transaction.get(usernameRef);
    if (usernameDoc.exists() && usernameDoc.data().uid !== user.uid) {
      throw new Error('That username is already taken.');
    }

    const counter = await transaction.get(counterRef);
    const nextNumber = counter.exists() ? Number(counter.data().nextNumber ?? 0) : 0;
    const profile: UserProfile = {
      uid: user.uid,
      username: normalized,
      number: nextNumber,
      createdAt: Date.now(),
    };

    transaction.set(profileRef, profile);
    transaction.set(usernameRef, { uid: user.uid, username: normalized, number: nextNumber, createdAt: Date.now() });
    transaction.set(counterRef, { nextNumber: nextNumber + 1 }, { merge: true });
    return profile;
  });
}

export async function findProfileByNumber(number: number): Promise<UserProfile | null> {
  const profiles = await getDocs(query(collection(db, 'profiles'), where('number', '==', number), limit(1)));
  if (profiles.empty) return null;
  return profiles.docs[0].data() as UserProfile;
}

export async function sendCard(profile: UserProfile, recipientNumber: number, draft: DraftCard): Promise<void> {
  const recipient = await findProfileByNumber(recipientNumber);
  if (!recipient) throw new Error(`No Carte user #${recipientNumber} exists yet.`);
  if (recipient.number === profile.number) throw new Error('Send this to someone else — your archive keeps your own drafts local.');

  const deliveryRef = doc(collection(db, 'deliveries'));
  let photoURL: string | undefined;
  let photoPath: string | undefined;

  if (draft.photoFile) {
    photoPath = `transit-photos/${deliveryRef.id}/${draft.photoFile.name}`;
    const photoRef = ref(storage, photoPath);
    await uploadBytes(photoRef, draft.photoFile, { contentType: draft.photoFile.type });
    photoURL = await getDownloadURL(photoRef);
  }

  await setDoc(deliveryRef, {
    senderUid: profile.uid,
    senderUsername: profile.username,
    senderNumber: profile.number,
    recipientNumber,
    recipientUid: recipient.uid,
    frontText: draft.frontText.trim(),
    backText: draft.backText.trim() || null,
    photoURL: photoURL ?? null,
    photoPath: photoPath ?? null,
    createdAt: serverTimestamp(),
  });
}

export function subscribeToInbox(profile: UserProfile, onCards: (cards: DeliveryCard[]) => void, onError: (error: Error) => void): Unsubscribe {
  const inboxQuery = query(
    collection(db, 'deliveries'),
    where('recipientUid', '==', profile.uid),
    orderBy('createdAt', 'desc'),
  );

  return onSnapshot(
    inboxQuery,
    (snapshot) => {
      onCards(snapshot.docs.map((deliveryDoc) => mapDelivery(deliveryDoc.id, deliveryDoc.data() as FirestoreDelivery)));
    },
    (error) => onError(error),
  );
}

export async function clearTransitCard(card: DeliveryCard): Promise<void> {
  await deleteDoc(doc(db, 'deliveries', card.id));
  if (card.photoPath) {
    await deleteObject(ref(storage, card.photoPath)).catch(() => undefined);
  }
}

function mapDelivery(id: string, data: FirestoreDelivery): DeliveryCard {
  const createdAt = typeof data.createdAt === 'number' ? data.createdAt : data.createdAt?.toMillis?.() ?? Date.now();
  return {
    id,
    senderUid: data.senderUid,
    senderUsername: data.senderUsername,
    senderNumber: data.senderNumber,
    recipientNumber: data.recipientNumber,
    recipientUid: data.recipientUid,
    frontText: data.frontText,
    backText: data.backText ?? undefined,
    photoURL: data.photoURL ?? undefined,
    photoPath: data.photoPath ?? undefined,
    createdAt,
  };
}
