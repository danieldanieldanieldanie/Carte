import { useEffect, useMemo, useRef, useState } from 'react';
import type React from 'react';
import { onAuthStateChanged, type User } from 'firebase/auth';
import { auth, firebaseIsConfigured, missingFirebaseKeys } from './lib/firebase';
import {
  clearTransitCard,
  loadProfile,
  logInWithUsername,
  logOut,
  sendCard,
  signUpWithUsername,
  subscribeToInbox,
} from './lib/carteService';
import { deleteArchivedCard, imageURLToDataURL, listArchivedCards, saveArchivedCard } from './lib/archive';
import { draftHasContent, parseRecipientNumber, validateUsername } from './lib/validation';
import type { ArchivedCard, DeliveryCard, DraftCard, Side, UserProfile } from './lib/types';

const emptyDraft: DraftCard = { frontText: '', backText: '', photoFile: null };

export default function App() {
  const [user, setUser] = useState<User | null>(null);
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [authLoading, setAuthLoading] = useState(true);
  const [inbox, setInbox] = useState<DeliveryCard[]>([]);
  const [archive, setArchive] = useState<ArchivedCard[]>([]);
  const [status, setStatus] = useState('');
  const [tab, setTab] = useState<'write' | 'tray' | 'archive' | 'me'>('write');

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, async (currentUser) => {
      setUser(currentUser);
      setAuthLoading(false);
      if (!currentUser) {
        setProfile(null);
        setInbox([]);
        return;
      }
      const loaded = await loadProfile(currentUser);
      setProfile(loaded);
      setArchive(await listArchivedCards());
    });
    return unsubscribe;
  }, []);

  useEffect(() => {
    if (!profile) return undefined;
    return subscribeToInbox(
      profile,
      setInbox,
      (error) => setStatus(error.message),
    );
  }, [profile]);

  async function dismissToArchive(card: DeliveryCard) {
    const localPhotoDataURL = card.photoURL ? await imageURLToDataURL(card.photoURL).catch(() => undefined) : undefined;
    const archived: ArchivedCard = { ...card, archivedAt: Date.now(), localPhotoDataURL };
    await saveArchivedCard(archived);
    await clearTransitCard(card);
    setArchive(await listArchivedCards());
    setStatus('Saved to your local archive.');
  }

  async function erase(card: DeliveryCard) {
    await clearTransitCard(card);
    setStatus('Erased from transit.');
  }

  async function removeArchived(id: string) {
    await deleteArchivedCard(id);
    setArchive(await listArchivedCards());
  }

  if (!firebaseIsConfigured) {
    return <ConfigNotice missingKeys={missingFirebaseKeys} />;
  }

  if (authLoading) {
    return <main className="centered"><p className="muted">Opening Carte…</p></main>;
  }

  if (!user || !profile) {
    return <AuthScreen onProfile={setProfile} />;
  }

  return (
    <main className="app-shell">
      <header className="topbar">
        <div>
          <p className="eyebrow">Carte</p>
          <h1>{tabLabel(tab)}</h1>
        </div>
        <div className="identity-pill">#{profile.number}</div>
      </header>

      {status && <button className="status" onClick={() => setStatus('')}>{status}</button>}

      <section className="panel">
        {tab === 'write' && <Composer profile={profile} onSend={sendCard} onStatus={setStatus} />}
        {tab === 'tray' && <Tray cards={inbox} onDone={dismissToArchive} onErase={erase} />}
        {tab === 'archive' && <Archive cards={archive} onDelete={removeArchived} />}
        {tab === 'me' && <Me profile={profile} onLogout={logOut} />}
      </section>

      <nav className="tabbar" aria-label="Carte sections">
        {(['write', 'tray', 'archive', 'me'] as const).map((item) => (
          <button key={item} className={tab === item ? 'active' : ''} onClick={() => setTab(item)}>
            {tabLabel(item)}
          </button>
        ))}
      </nav>
    </main>
  );
}

function ConfigNotice({ missingKeys }: { missingKeys: string[] }) {
  return (
    <main className="centered config-card">
      <p className="eyebrow">Setup needed</p>
      <h1>Connect Firebase</h1>
      <p className="muted">Create <code>.env.local</code> in <code>Web/CarteWeb</code> with your Firebase web app keys.</p>
      <pre>{missingKeys.join('\n')}</pre>
    </main>
  );
}

function AuthScreen({ onProfile }: { onProfile: (profile: UserProfile) => void }) {
  const [mode, setMode] = useState<'signup' | 'login'>('signup');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setError('');
    const usernameError = validateUsername(username);
    if (usernameError) {
      setError(usernameError);
      return;
    }
    setBusy(true);
    try {
      const profile = mode === 'signup'
        ? await signUpWithUsername(username, password)
        : await logInWithUsername(username, password);
      onProfile(profile);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Could not continue.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="centered auth-layout">
      <section className="hero-card">
        <p className="eyebrow">Carte</p>
        <h1>Minimal postcards for people, not feeds.</h1>
        <p className="muted">Create a numbered account, write a card, add a photo, and send it by keypad.</p>
      </section>
      <form className="auth-card" onSubmit={submit}>
        <div className="segmented">
          <button type="button" className={mode === 'signup' ? 'active' : ''} onClick={() => setMode('signup')}>Create</button>
          <button type="button" className={mode === 'login' ? 'active' : ''} onClick={() => setMode('login')}>Log in</button>
        </div>
        <label>Username<input value={username} onChange={(e) => setUsername(e.target.value)} autoComplete="username" /></label>
        <label>Password<input value={password} onChange={(e) => setPassword(e.target.value)} type="password" autoComplete={mode === 'signup' ? 'new-password' : 'current-password'} /></label>
        {error && <p className="error">{error}</p>}
        <button className="primary" disabled={busy || password.length < 6}>{busy ? 'Working…' : mode === 'signup' ? 'Create Carte' : 'Enter'}</button>
      </form>
    </main>
  );
}

function Composer({ profile, onSend, onStatus }: { profile: UserProfile; onSend: typeof sendCard; onStatus: (message: string) => void }) {
  const [draft, setDraft] = useState<DraftCard>(emptyDraft);
  const [side, setSide] = useState<Side>('front');
  const [recipient, setRecipient] = useState('');
  const [busy, setBusy] = useState(false);
  const previewURL = useMemo(() => draft.photoFile ? URL.createObjectURL(draft.photoFile) : undefined, [draft.photoFile]);
  const fileRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => () => { if (previewURL) URL.revokeObjectURL(previewURL); }, [previewURL]);

  async function submit() {
    const number = parseRecipientNumber(recipient);
    if (number === null) {
      onStatus('Enter a valid Carte number.');
      return;
    }
    if (!draftHasContent(draft.frontText, draft.backText, Boolean(draft.photoFile))) {
      onStatus('Write something or add a photo first.');
      return;
    }
    setBusy(true);
    try {
      await onSend(profile, number, draft);
      setDraft(emptyDraft);
      setRecipient('');
      onStatus(`Sent to #${number}.`);
    } catch (caught) {
      onStatus(caught instanceof Error ? caught.message : 'Could not send card.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="write-grid">
      <div className="postcard composer-card">
        <div className="side-switch">
          <button className={side === 'front' ? 'active' : ''} onClick={() => setSide('front')}>Front</button>
          <button className={side === 'back' ? 'active' : ''} onClick={() => setSide('back')}>Back</button>
        </div>
        {side === 'front' ? (
          <textarea aria-label="Front of card" placeholder="Write the front…" value={draft.frontText} onChange={(e) => setDraft({ ...draft, frontText: e.target.value })} />
        ) : (
          <textarea aria-label="Back of card" placeholder="Optional second side…" value={draft.backText} onChange={(e) => setDraft({ ...draft, backText: e.target.value })} />
        )}
        {previewURL && <img className="photo-preview" src={previewURL} alt="Selected postcard attachment" />}
        <div className="composer-actions">
          <input ref={fileRef} type="file" accept="image/*" hidden onChange={(e) => setDraft({ ...draft, photoFile: e.target.files?.[0] ?? null })} />
          <button onClick={() => fileRef.current?.click()}>Add photo</button>
          {draft.photoFile && <button onClick={() => setDraft({ ...draft, photoFile: null })}>Remove</button>}
        </div>
      </div>
      <div className="keypad-card">
        <p className="eyebrow">Send by number</p>
        <input className="number-display" inputMode="numeric" value={recipient} onChange={(e) => setRecipient(e.target.value.replace(/\D/g, ''))} placeholder="0" />
        <div className="keypad">
          {'123456789'.split('').map((digit) => <button key={digit} onClick={() => setRecipient((value) => value + digit)}>{digit}</button>)}
          <button onClick={() => setRecipient((value) => value.slice(0, -1))}>⌫</button>
          <button onClick={() => setRecipient((value) => value + '0')}>0</button>
          <button onClick={submit} disabled={busy}>{busy ? '…' : 'Send'}</button>
        </div>
      </div>
    </div>
  );
}

function Tray({ cards, onDone, onErase }: { cards: DeliveryCard[]; onDone: (card: DeliveryCard) => Promise<void>; onErase: (card: DeliveryCard) => Promise<void> }) {
  if (cards.length === 0) return <Empty title="Your in-tray is clear." body="New cards arrive here only while they are in transit." />;
  return <div className="card-stack">{cards.map((card) => <ReadableCard key={card.id} card={card} primaryLabel="Done" onPrimary={() => onDone(card)} secondaryLabel="Erase" onSecondary={() => onErase(card)} />)}</div>;
}

function Archive({ cards, onDelete }: { cards: ArchivedCard[]; onDelete: (id: string) => Promise<void> }) {
  if (cards.length === 0) return <Empty title="No saved cards yet." body="Tap Done in the in-tray to move examined cards into this local archive." />;
  return <div className="card-stack">{cards.map((card) => <ReadableCard key={card.id} card={card} primaryLabel="Keep" onPrimary={() => Promise.resolve()} secondaryLabel="Erase" onSecondary={() => onDelete(card.id)} archived />)}</div>;
}

function ReadableCard({ card, primaryLabel, secondaryLabel, onPrimary, onSecondary, archived = false }: { card: DeliveryCard | ArchivedCard; primaryLabel: string; secondaryLabel: string; onPrimary: () => Promise<void>; onSecondary: () => Promise<void>; archived?: boolean }) {
  const [side, setSide] = useState<Side>('front');
  const image = 'localPhotoDataURL' in card ? card.localPhotoDataURL ?? card.photoURL : card.photoURL;
  return (
    <article className="read-card">
      <div className="card-meta"><span>From @{card.senderUsername}</span><span>#{card.senderNumber}</span></div>
      <button className="postcard readable" onClick={() => setSide(side === 'front' ? 'back' : 'front')}>
        {side === 'front' ? (
          <>
            {image && <img src={image} alt="Postcard attachment" />}
            <p>{card.frontText || 'Photo card'}</p>
          </>
        ) : <p>{card.backText || 'Blank back'}</p>}
      </button>
      <div className="row-actions">
        {!archived && <button className="primary" onClick={onPrimary}>{primaryLabel}</button>}
        <button onClick={onSecondary}>{secondaryLabel}</button>
      </div>
    </article>
  );
}

function Me({ profile, onLogout }: { profile: UserProfile; onLogout: () => Promise<void> }) {
  async function copyNumber() {
    await navigator.clipboard.writeText(String(profile.number));
  }
  return (
    <div className="me-card">
      <p className="eyebrow">Your Carte number</p>
      <div className="big-number">#{profile.number}</div>
      <p className="muted">Give this number to someone so they can address a postcard to you.</p>
      <button className="primary" onClick={copyNumber}>Copy number</button>
      <button onClick={onLogout}>Log out @{profile.username}</button>
    </div>
  );
}

function Empty({ title, body }: { title: string; body: string }) {
  return <div className="empty"><h2>{title}</h2><p>{body}</p></div>;
}

function tabLabel(tab: 'write' | 'tray' | 'archive' | 'me'): string {
  return { write: 'Write', tray: 'Tray', archive: 'Archive', me: 'Me' }[tab];
}
