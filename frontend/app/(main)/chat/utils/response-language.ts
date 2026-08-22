import { useLanguageStore, type Language } from '@/lib/store/language-store';

/**
 * The language the store boots with for users who never opened the Language
 * panel. It is intentionally NOT sent: the model then answers in whatever
 * language the question was asked in, which is what an untouched install
 * should keep doing. Picking any other language is an explicit preference
 * and pins every answer to it.
 */
export const DEFAULT_UI_LANGUAGE: Language = 'en-US';

/**
 * Value for the `responseLanguage` field on chat stream bodies. Pairs with
 * `timezone` / `currentTime` from `client-time.ts`; Python renders a
 * "Response Language" prompt section from it.
 */
export function getResponseLanguage(): Language | undefined {
  let language: Language = DEFAULT_UI_LANGUAGE;
  try {
    language = useLanguageStore.getState().language;
  } catch {
    return undefined;
  }
  return language && language !== DEFAULT_UI_LANGUAGE ? language : undefined;
}
