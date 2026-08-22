"""Prompt block that pins the assistant's answer language to the workspace
Language setting (frontend `language-store`), sent as `responseLanguage`.

The client sends a BCP-47 locale code (`de-DE`); the model reads the
human-readable name better, so the code is mapped here and an unknown code
falls back to the raw tag rather than being dropped.
"""

from __future__ import annotations

import re

_LOCALE_RE = re.compile(r"^[A-Za-z]{2,3}(?:[-_][A-Za-z0-9]{2,8})*$")

# Primary-subtag → English language name. Region variants share the name;
# `en-IN` and `en-US` are both "English".
_LANGUAGE_NAMES: dict[str, str] = {
    "en": "English",
    "de": "German",
    "es": "Spanish",
    "hi": "Hindi",
    "fr": "French",
    "it": "Italian",
    "pt": "Portuguese",
    "nl": "Dutch",
    "ja": "Japanese",
    "ko": "Korean",
    "zh": "Chinese",
    "ar": "Arabic",
    "ru": "Russian",
    "tr": "Turkish",
    "pl": "Polish",
    "sv": "Swedish",
    "da": "Danish",
    "fi": "Finnish",
    "no": "Norwegian",
    "nb": "Norwegian",
    "cs": "Czech",
    "uk": "Ukrainian",
    "id": "Indonesian",
    "vi": "Vietnamese",
    "th": "Thai",
    "he": "Hebrew",
    "bn": "Bengali",
    "ta": "Tamil",
    "te": "Telugu",
    "mr": "Marathi",
}

_RESPONSE_LANGUAGE_HEADING = "## Response Language"


def normalize_response_language(value: str | None) -> str | None:
    """Trimmed locale tag, or ``None`` when empty/malformed.

    Malformed values are dropped instead of raised: the field is advisory and
    a bad client value must not fail the chat request.
    """
    if not isinstance(value, str):
        return None
    tag = value.strip()
    if not tag or not _LOCALE_RE.match(tag):
        return None
    return tag


def language_display_name(locale: str) -> str:
    primary = re.split(r"[-_]", locale, maxsplit=1)[0].lower()
    return _LANGUAGE_NAMES.get(primary, locale)


def build_llm_response_language_context(response_language: str | None) -> str:
    """Section instructing the model to answer in the user's chosen language."""
    tag = normalize_response_language(response_language)
    if not tag:
        return ""
    name = language_display_name(tag)
    label = name if name == tag else f"{name} ({tag})"
    return "\n".join(
        [
            _RESPONSE_LANGUAGE_HEADING,
            "",
            f"The user has set their preferred language to **{label}**.",
            f"Write your entire final answer in {name}, regardless of the language "
            "of the question, the retrieved sources, or tool results.",
            "Keep code, identifiers, URLs, citation markers, and verbatim quotes "
            "exactly as they appear in the source — translate only your own prose.",
        ]
    )
