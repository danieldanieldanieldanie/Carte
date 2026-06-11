import { describe, expect, it } from 'vitest';
import { draftHasContent, normalizeUsername, parseRecipientNumber, usernameToEmail, validateUsername } from '../lib/validation';

describe('username validation', () => {
  it('normalizes and maps usernames to Firebase email addresses', () => {
    expect(normalizeUsername(' Alice_01 ')).toBe('alice_01');
    expect(usernameToEmail('Alice_01')).toBe('alice_01@users.carte.local');
  });

  it('rejects short or punctuation-heavy usernames', () => {
    expect(validateUsername('ab')).toBeTruthy();
    expect(validateUsername('alice!')).toBeTruthy();
    expect(validateUsername('alice_01')).toBeNull();
  });
});

describe('recipient keypad parsing', () => {
  it('accepts non-negative integer numbers starting at zero', () => {
    expect(parseRecipientNumber('0')).toBe(0);
    expect(parseRecipientNumber('42')).toBe(42);
  });

  it('rejects blank, signed, decimal, and unsafe values', () => {
    expect(parseRecipientNumber('')).toBeNull();
    expect(parseRecipientNumber('-1')).toBeNull();
    expect(parseRecipientNumber('1.5')).toBeNull();
    expect(parseRecipientNumber(String(Number.MAX_SAFE_INTEGER + 10))).toBeNull();
  });
});

describe('draft content', () => {
  it('requires text or a photo before sending', () => {
    expect(draftHasContent('', ' ', false)).toBe(false);
    expect(draftHasContent('hello', '', false)).toBe(true);
    expect(draftHasContent('', '', true)).toBe(true);
  });
});
