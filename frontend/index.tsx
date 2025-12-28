import { log } from './services/logger';
import {
  initUIMode,
  getCurrentConfig,
  registerModeChangeListener,
  onModeChange,
} from './ui/uiMode';
import { setupObserver, resetState } from './injection/observer';
import { exposeDebugTools } from './debug/tools';

async function init(): Promise<void> {
  log('Initializing HLTB plugin...');

  try {
    const { mode, document } = await initUIMode();
    const config = getCurrentConfig();

    log('Mode:', config.modeName);
    log('Using selectors:', {
      headerImage: config.headerImageSelector,
      fallbackImage: config.fallbackImageSelector,
      container: config.containerSelector,
    });

    await setupObserver(document, config);
    exposeDebugTools(document);

    registerModeChangeListener();

    onModeChange(async (newMode, newDoc) => {
      log('Reinitializing for mode change...');
      resetState();
      const newConfig = getCurrentConfig();
      await setupObserver(newDoc, newConfig);
      exposeDebugTools(newDoc);
      log('Reinitialized for', newConfig.modeName, 'mode');
    });
  } catch (e) {
    log('Failed to initialize:', e);
  }
}

init();

export default async function PluginMain() {
  // Plugin initialization is handled by init()
}
