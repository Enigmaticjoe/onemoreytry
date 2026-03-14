"""
common_utils.py — Shared utilities for homelab install scripts.

This module contains functions used by both ``bos.py`` and
``boss_multi_agent_install.py`` to avoid code duplication.  All helpers
are pure-Python with no third-party runtime dependencies (BeautifulSoup is
an optional soft dependency for :func:`fetch_first_paragraph`).
"""

from __future__ import annotations

import getpass
import urllib.parse as urlparse
import urllib.request as urlrequest
from html import unescape
from typing import Any, Dict, List, Optional


# ---------------------------------------------------------------------------
# Interactive input
# ---------------------------------------------------------------------------

def prompt_input(
    text: str, default: Optional[str] = None, secret: bool = False
) -> str:
    """Prompt the user for input with an optional default and secret masking.

    Args:
        text:    Prompt label shown to the user.
        default: Value returned when the user presses Enter without typing.
        secret:  When True the input is hidden (password-style).

    Returns:
        The stripped user input, or *default* when the input is empty.
    """
    suffix = f" [{default}]" if default else ""
    prompt_text = f"{text}{suffix}: "
    try:
        val = getpass.getpass(prompt_text) if secret else input(prompt_text)
    except EOFError:
        val = ""
    return val.strip() or (default or "")


# ---------------------------------------------------------------------------
# Web search helpers (DuckDuckGo Lite — best-effort)
# ---------------------------------------------------------------------------

def search_web(query: str, max_results: int = 3) -> List[Dict[str, str]]:
    """Scrape DuckDuckGo Lite for search results.

    Returns a list of dicts with ``'title'`` and ``'url'`` keys.
    This is best-effort; any network or parsing failure returns an empty list.

    Args:
        query:       Search query string.
        max_results: Maximum number of results to return.

    Returns:
        List of ``{"title": ..., "url": ...}`` dicts.
    """
    encoded = urlparse.quote_plus(query)
    url = f"https://lite.duckduckgo.com/lite/?q={encoded}"
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0"
        )
    }
    req = urlrequest.Request(url, headers=headers)
    try:
        with urlrequest.urlopen(req, timeout=15) as resp:
            html = resp.read().decode("utf-8", errors="ignore")
    except Exception:
        return []

    results: List[Dict[str, str]] = []
    for marker in ('class="result-link"', 'class="result__a"'):
        for part in html.split(marker)[1:]:
            href_start = part.find('href="')
            if href_start == -1:
                continue
            href_start += 6
            href_end = part.find('"', href_start)
            link = part[href_start:href_end]
            if "uddg=" in link:
                _, _, redirect = link.partition("uddg=")
                link = urlparse.unquote(redirect.split("&")[0])
            title_start = part.find(">") + 1
            title_end = part.find("</a>", title_start)
            if title_end == -1:
                title_end = title_start + 80
            title = part[title_start:title_end]
            title = title.replace("<b>", "").replace("</b>", "").strip()
            if link.startswith("http"):
                results.append({"title": unescape(title), "url": link})
            if len(results) >= max_results:
                return results
    return results


def fetch_first_paragraph(url: str) -> str:
    """Best-effort fetch of the first substantial ``<p>`` text from a URL.

    Requires *BeautifulSoup4* (``bs4``).  Returns a placeholder string when
    the library is not installed, and an empty string on any network error.

    Args:
        url: Page URL to fetch.

    Returns:
        First paragraph text (up to 300 chars), or an empty string on failure.
    """
    try:
        from bs4 import BeautifulSoup  # type: ignore[import-untyped]
    except ImportError:
        return "(bs4 not available for preview)"
    try:
        req = urlrequest.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urlrequest.urlopen(req, timeout=10) as resp:
            html = resp.read().decode("utf-8", errors="ignore")
    except Exception:
        return ""
    soup = BeautifulSoup(html, "html.parser")
    for p in soup.find_all("p"):
        text = p.get_text(strip=True)
        if len(text) > 40:
            return text[:300]
    return ""


def answer_query(query: str) -> Dict[str, Any]:
    """Web-search-backed Q&A helper.

    Searches DuckDuckGo for *query*, fetches a short summary from each result
    page, and returns a structured answer dict.

    Args:
        query: The question or search phrase.

    Returns:
        Dict with keys ``'query'``, ``'results'`` (list), and ``'summary'`` (str).
    """
    results = search_web(query, max_results=3)
    entries: List[Dict[str, Any]] = []
    summaries: List[str] = []
    for res in results:
        summary = fetch_first_paragraph(res["url"])
        entries.append({"title": res["title"], "url": res["url"], "summary": summary})
        if summary:
            summaries.append(summary)
    combined = "\n\n".join(summaries) if summaries else "No results found for that query."
    if summaries:
        combined = "Here's what I found:\n\n" + combined
    return {"query": query, "results": entries, "summary": combined}
