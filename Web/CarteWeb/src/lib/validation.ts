export function normalizeUsername(username: string): string {
  return username.trim().toLowerCase();
}

export function validateUsername(username: string): string | null {
  const normalized = normalizeUsername(username);
  if (normalized.length < 3) return 'Use at least 3 characters.';
  if (normalized.length > 24) return 'Use 24 characters or fewer.';
  if (!/^[a-z0-9_]+$/.test(normalized)) return 'Use letters, numbers, and underscores only.';
  return null;
}

export function usernameToEmail(username: string): string {
  return `${normalizeUsername(username)}@users.carte.local`;
}

export function parseRecipientNumber(input: string): number | null {
  if (!/^\d+$/.test(input.trim())) return null;
  const parsed = Number(input);
  return Number.isSafeInteger(parsed) && parsed >= 0 ? parsed : null;
}

export function draftHasContent(frontText: string, backText: string, hasPhoto: boolean): boolean {
  return frontText.trim().length > 0 || backText.trim().length > 0 || hasPhoto;
}
