import { describe, it, expect, beforeEach, vi } from 'vitest';
import { useLanguageStore } from '@/lib/store/language-store';
import { DEFAULT_UI_LANGUAGE, getResponseLanguage } from '../response-language';

// `setLanguage` lazily imports the full i18n config (locales, detector);
// the store's `language` value is all that matters here.
vi.mock('@/lib/i18n/config', () => ({ default: { changeLanguage: vi.fn() } }));

describe('getResponseLanguage', () => {
  beforeEach(() => {
    useLanguageStore.setState({ language: DEFAULT_UI_LANGUAGE });
  });

  it('is undefined for the default UI language so the model follows the question', () => {
    expect(getResponseLanguage()).toBeUndefined();
  });

  it('returns the chosen locale once the user picks a non-default language', () => {
    useLanguageStore.getState().setLanguage('de-DE');
    expect(getResponseLanguage()).toBe('de-DE');
  });

  it('tracks later changes to the setting', () => {
    useLanguageStore.getState().setLanguage('hi-IN');
    expect(getResponseLanguage()).toBe('hi-IN');
    useLanguageStore.getState().setLanguage(DEFAULT_UI_LANGUAGE);
    expect(getResponseLanguage()).toBeUndefined();
  });
});
