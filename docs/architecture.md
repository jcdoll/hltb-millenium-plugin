# Architecture

This document describes the technical architecture of the HLTB for Millennium plugin, including comparisons with related projects and key design decisions.

## Platform Comparison

The following table compares the Decky Loader platform (Steam Deck) with the Millennium platform (Desktop).

| Aspect | Decky (Steam Deck) | Millennium (Desktop) |
|--------|-------------------|---------------------|
| Frontend | TypeScript/React | TypeScript/React |
| Backend | Python | Python |
| UI Hooks | `decky-frontend-lib` | `@steambrew/client` APIs |
| Build Tool | Rollup | `@steambrew/ttc` |
| DOM Access | `serverApi.routerHook` | MutationObserver + CSS selectors |
| HTTP Requests | `serverApi.fetchNoCors()` | Python backend via `Millennium.callServerMethod()` |

Both platforms use React for the frontend, which allows significant code reuse for UI components and business logic.

## Code Reuse Analysis

### Reusable Components (60-70%)

The following components from hltb-for-deck can be adapted with minimal changes:

1. HLTB API Logic
   - HTTP POST request construction
   - Response parsing
   - Error handling

2. Game Name Normalization
   - Unicode normalization (NFD)
   - Diacritic removal
   - Special character filtering
   - Case normalization

3. Game Matching Algorithm
   - Steam App ID matching via `profile_steam` field
   - Exact normalized name matching
   - Fuzzy matching with Levenshtein distance
   - Result ranking by completion count

4. Caching Logic
   - Cache key structure
   - TTL-based expiration
   - Storage format

5. Display Component Structure
   - Stats layout (Main, Plus, 100%, All Styles)
   - Time formatting
   - Link to HLTB website

### Components Requiring Rewrite (30-40%)

1. UI Injection
   - Decky uses route patching via `serverApi.routerHook.addPatch()`
   - Millennium uses `Millennium.findElement()` with CSS selectors
   - Different DOM structures between Desktop UI and GamepadUI

2. Backend Communication
   - Decky uses Python with `serverApi.fetchNoCors()`
   - Millennium uses Python with `Millennium.callServerMethod()`
   - Backend handles HLTB lookups via `howlongtobeatpy` library

3. Storage API
   - Decky uses `localforage` (IndexedDB wrapper)
   - Millennium uses browser `localStorage`

4. Settings UI
   - Decky uses Quick Access Menu components
   - Millennium uses `definePlugin()` pattern with `Field`, `Toggle`, `DialogButton`

## Plugin Architecture

### Directory Structure

```
hltb-millennium-plugin/
├── plugin.json              # Plugin manifest
├── package.json             # Dependencies and build scripts
├── tsconfig.json            # TypeScript configuration
├── frontend/
│   ├── index.tsx            # Plugin entry point
│   ├── types.ts             # Shared TypeScript types
│   ├── debug/
│   │   └── tools.ts         # Debug utilities (hltbDebug)
│   ├── display/
│   │   ├── components.ts    # HLTB display elements
│   │   └── styles.ts        # CSS injection
│   ├── injection/
│   │   ├── detector.ts      # Game page detection
│   │   └── observer.ts      # MutationObserver setup
│   ├── services/
│   │   ├── hltbApi.ts       # HLTB API client (via backend)
│   │   ├── cache.ts         # localStorage caching
│   │   └── logger.ts        # Logging utilities
│   └── ui/
│       ├── selectors.ts     # CSS selectors for Desktop/GamePad modes
│       └── uiMode.ts        # UI mode detection and switching
├── backend/
│   └── main.py              # Python backend (HLTB lookups)
└── webkit/
    └── index.tsx            # Webkit entry point
```

### Data Flow

```
User navigates to game page
         │
         ▼
Window hook detects navigation
         │
         ▼
Extract App ID from URL/DOM
         │
         ▼
Check local cache
         │
    ┌────┴────┐
    │ cached  │ not cached
    ▼         ▼
Return data   Fetch from HLTB API
              │
              ▼
         Match game in results
              │
              ▼
         Store in cache
              │
              ▼
         Return data
              │
              ▼
    Inject display component
```

## Key Technical Decisions

### Decision 1: Backend for HLTB Lookups

Implementation: Python backend using `howlongtobeatpy` library.

Rationale:
- HLTB API requires complex search logic best handled server-side
- `howlongtobeatpy` provides reliable game matching
- Backend can sanitize game names for better search results
- Avoids CORS issues entirely

### Decision 2: Element Selection Strategy

Implementation: MutationObserver with CSS selectors for game page detection.

Rationale:
- Steam UI uses obfuscated class names that change between updates
- MutationObserver detects SPA navigation and DOM changes
- Dual image detection (logo.png primary, library_hero.jpg fallback)
- Common container selector works for games with or without custom logos

### Decision 3: Cache Storage

Recommendation: Use localStorage with JSON serialization.

Rationale:
- Simpler than IndexedDB
- Sufficient capacity for HLTB data (small payloads)
- Synchronous access simplifies code
- Matches AugmentedSteam approach

### Decision 4: Dual UI Mode Support

Recommendation: Implement Desktop UI first, add Big Picture support in subsequent phase.

Rationale:
- Desktop UI is primary use case
- Big Picture requires different selectors and injection points
- Can reuse hltb-for-deck patterns for GamepadUI
- Allows faster initial release

## Risk Mitigation

| Risk | Mitigation Strategy |
|------|---------------------|
| HLTB API changes | Python `howlongtobeatpy` library abstracts API details |
| Steam UI class changes | Fallback image selector, common container for both game types |
| HLTB rate limiting | Aggressive caching (2+ hour TTL), stale-while-revalidate |
| Game matching failures | Backend name sanitization, library handles fuzzy matching |
| Big Picture issues | Document known issues, graceful degradation |
| Mode switching | Re-initialize on window creation, clean observer cleanup |
