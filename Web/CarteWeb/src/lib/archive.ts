import type { ArchivedCard } from './types';

const DB_NAME = 'carte-local-archive';
const STORE_NAME = 'cards';
const DB_VERSION = 1;

function openArchiveDB(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(STORE_NAME)) {
        db.createObjectStore(STORE_NAME, { keyPath: 'id' });
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function withStore<T>(mode: IDBTransactionMode, work: (store: IDBObjectStore) => IDBRequest<T> | void): Promise<T | undefined> {
  const db = await openArchiveDB();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, mode);
    const store = transaction.objectStore(STORE_NAME);
    const request = work(store);
    let result: T | undefined;
    if (request) {
      request.onsuccess = () => {
        result = request.result;
      };
      request.onerror = () => reject(request.error);
    }
    transaction.oncomplete = () => {
      db.close();
      resolve(result);
    };
    transaction.onerror = () => {
      db.close();
      reject(transaction.error);
    };
  });
}

export async function saveArchivedCard(card: ArchivedCard): Promise<void> {
  await withStore('readwrite', (store) => store.put(card));
}

export async function listArchivedCards(): Promise<ArchivedCard[]> {
  const cards = (await withStore<ArchivedCard[]>('readonly', (store) => store.getAll())) ?? [];
  return cards.sort((a, b) => b.archivedAt - a.archivedAt);
}

export async function deleteArchivedCard(id: string): Promise<void> {
  await withStore('readwrite', (store) => store.delete(id));
}

export async function imageURLToDataURL(url: string): Promise<string | undefined> {
  const response = await fetch(url);
  if (!response.ok) return undefined;
  const blob = await response.blob();
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(typeof reader.result === 'string' ? reader.result : undefined);
    reader.onerror = () => reject(reader.error);
    reader.readAsDataURL(blob);
  });
}
