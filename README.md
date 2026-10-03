# StudySprint (macOS)

A native macOS app: paste or drop in your notes, pick how much time you have, and get a study guide built to make you learn the topic **as fast as possible**.

Each guide gives you:

- **TL;DR** of the whole topic
- **The 20% that gets you 80%**: the few core ideas to learn first
- **A time-boxed learning path** that fits your budget (30 min to 1 day), ordered so each step builds on the one before
- **Real videos found with live web search**, with which part to watch and at what speed (e.g. "Watch 1:30–7:45 at 1.5x"). Links that didn't come from an actual search result are swapped for a YouTube search, so you never get a made-up link.
- **Active-recall questions** after each step, **flashcards** (with an "again / got it" drill), **common mistakes**, a **safe-to-skip** list, and a **final self-test**
- A **sprint timer**, progress tracking, saved guide history, and **Markdown export**

Notes can be typed or pasted, or imported from `.txt`, `.md`, `.pdf`, `.docx`, `.rtf` or `.html` files.

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15+ or the Swift 5.9+ command-line tools (`xcode-select --install`)
- An Anthropic API key from https://console.anthropic.com

## Build and run

```bash
cd StudySprint
./build-app.sh            # builds build/StudySprint.app
open build/StudySprint.app
```

Drag `build/StudySprint.app` into `/Applications` to keep it. For quick development you can also run `swift run` from `StudySprint/`, or open `StudySprint/Package.swift` in Xcode and press ⌘R.

On first launch, open **StudySprint → Settings… (⌘,)** and paste your API key. It's stored in your macOS Keychain.

## How it works

The app sends your notes to Claude (`claude-opus-5-5`) with the server-side **web search** tool turned on. Claude works out what you need to know, searches for the best short videos for each step, and returns the guide as JSON. The app then:

1. checks every video URL against the URLs that actually came back from search, and replaces unverified ones with a YouTube search link
2. saves the guide to `~/Library/Application Support/StudySprint/guides.json`

A guide usually takes 1–3 minutes to build because Claude runs several searches. Each guide costs a few cents to a few tens of cents in API usage, depending on how long your notes are.

## Project layout

```
StudySprint/
  Package.swift
  build-app.sh                 # packages a double-clickable .app
  Sources/StudySprint/
    StudySprintApp.swift
    Models/StudyGuide.swift
    Services/ClaudeClient.swift    # Messages API + web search + JSON parsing
    Services/GuideStore.swift      # saved guides
    Services/KeychainStore.swift   # API key storage
    Services/NotesImporter.swift   # text from PDF/DOCX/RTF/MD
    Services/MarkdownExporter.swift
    Views/                         # SwiftUI screens
```
