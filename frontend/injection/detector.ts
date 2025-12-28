import type { UIModeConfig, GamePageInfo } from '../types';

export function detectGamePage(doc: Document, config: UIModeConfig): GamePageInfo | null {
  // Try primary selector first (logo.png)
  const primaryImg = doc.querySelector(config.headerImageSelector) as HTMLImageElement | null;
  if (primaryImg) {
    const src = primaryImg.src || '';
    const match = src.match(config.appIdPattern);
    if (match) {
      const appId = parseInt(match[1], 10);
      const container = primaryImg.closest(config.containerSelector) as HTMLElement | null;
      if (container) {
        return { appId, container };
      }
    }
  }

  // Try fallback selector (library_hero.jpg for games without logo)
  const fallbackImg = doc.querySelector(config.fallbackImageSelector) as HTMLImageElement | null;
  if (fallbackImg) {
    const src = fallbackImg.src || '';
    const match = src.match(config.appIdPattern);
    if (match) {
      const appId = parseInt(match[1], 10);
      const container = fallbackImg.closest(config.containerSelector) as HTMLElement | null;
      if (container) {
        return { appId, container };
      }
    }
  }

  return null;
}
