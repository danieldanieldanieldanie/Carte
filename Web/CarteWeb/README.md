# Carte Web Prototype

A Firebase-backed web/PWA prototype for Carte. This codebase is intentionally separate from the Swift/iPhone app at the repository root.

## What it does

- Username + password accounts using Firebase Auth.
- Persistent Carte identities stored in Firestore.
- Sequential Carte numbers starting at `0`, allocated transactionally through `system/numberCounter`.
- Numeric keypad addressing for sending postcards.
- Text front/back composition plus one photo attachment.
- Realtime in-tray through Firestore `deliveries`.
- `Done` saves the examined card into the browser's local IndexedDB archive, then deletes the in-transit Firestore delivery and transient Storage photo.
- Modern, minimal, warm paper-like interface.

## Firebase setup

1. Create a Firebase project.
2. Enable **Authentication → Email/Password**.
3. Enable **Firestore Database**.
4. Enable **Storage**.
5. Create a Web App in Firebase project settings.
6. Copy `.env.example` to `.env.local` and fill in the web app values.
7. Deploy rules/indexes when ready:

```sh
firebase deploy --only firestore:rules,firestore:indexes,storage
```

## Local development

```sh
npm install
npm run dev
```

Then open the Vite URL on desktop or iPhone Safari.

## Build

```sh
npm run build
```

## Deploy to Firebase Hosting

```sh
npm run build
firebase deploy --only hosting
```

## Prototype caveats

- Firebase Auth requires email/password internally, so usernames are mapped to hidden local emails like `alice@users.carte.local`.
- The archive is local browser storage. If a user clears site data or changes browsers/devices, local archived cards will not follow them.
- Firestore/Storage rules are prototype rules. Tighten recipient-specific deletes and abuse controls before broad public testing.
