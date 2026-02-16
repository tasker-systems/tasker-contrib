/**
 * Shared Tasker client singleton.
 *
 * The FfiLayer is loaded once at module initialization and reused by all
 * route handlers. This avoids the overhead of loading the native library
 * on every HTTP request.
 */
import { FfiLayer, TaskerClient } from '@tasker-systems/tasker';

let sharedFfiLayer: FfiLayer | null = null;
let loadPromise: Promise<FfiLayer> | null = null;

/**
 * Returns a loaded FfiLayer, initializing it on first call.
 * Subsequent calls return the same instance.
 */
export async function getFfiLayer(): Promise<FfiLayer> {
  if (sharedFfiLayer) {
    return sharedFfiLayer;
  }

  if (!loadPromise) {
    loadPromise = (async () => {
      const layer = new FfiLayer();
      await layer.load();
      sharedFfiLayer = layer;
      return layer;
    })();
  }

  return loadPromise;
}

/**
 * Returns a TaskerClient backed by the shared FfiLayer.
 */
export async function getTaskerClient(): Promise<TaskerClient> {
  const ffiLayer = await getFfiLayer();
  return new TaskerClient(ffiLayer);
}
