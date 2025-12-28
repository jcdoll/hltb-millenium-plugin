// HLTB game data from backend
export interface HltbGameResult {
  game_id: number;
  game_name: string;
  comp_main: number; // seconds
  comp_plus: number; // seconds
  comp_100: number; // seconds
  comp_all: number; // seconds
}

// Cache entry for localStorage
export interface CacheEntry {
  data: HltbGameResult | null;
  timestamp: number;
  notFound: boolean;
}

// Result from fetchHltbData with stale-while-revalidate support
export interface FetchResult {
  data: HltbGameResult | null;
  fromCache: boolean;
  refreshPromise: Promise<HltbGameResult | null> | null;
}

// UI Mode enum matching Steam's internal values
export enum EUIMode {
  Unknown = -1,
  GamePad = 4, // Big Picture / Steam Deck
  Desktop = 7,
}

// Selector configuration for each UI mode
export interface UIModeConfig {
  mode: EUIMode;
  modeName: string;
  headerImageSelector: string;
  fallbackImageSelector: string;
  containerSelector: string;
  appIdPattern: RegExp;
}

// Detected game page info
export interface GamePageInfo {
  appId: number;
  container: HTMLElement;
}
