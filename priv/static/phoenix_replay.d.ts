/**
 * Client context for PhoenixReplay: the browser's viewport and a per-tab id,
 * sent with LiveView's connect params and its event metadata.
 *
 *     import { replayParams, replayMetadata } from "phoenix_replay"
 *
 *     const liveSocket = new LiveSocket("/live", Socket, {
 *       params: () => ({ _csrf_token: csrfToken, ...replayParams() }),
 *       metadata: replayMetadata
 *     })
 *
 * Both are optional: without them, recordings simply carry no viewport.
 */
export interface ReplayViewport {
    width: number;
    height: number;
    dpr: number;
}
/**
 * Returns an id for this browser tab, kept in sessionStorage so it survives
 * navigation and reloads within the tab. Returns an empty string when
 * storage is unavailable.
 */
export declare const tabId: () => string;
/** Connect params to merge into LiveSocket's `params`. */
export declare const replayParams: () => {
    _replay: ReplayViewport & {
        tab: string;
    };
};
/**
 * Event metadata for LiveSocket's `metadata` option. The viewport travels
 * with each click and key press, so the recording follows resizes. Merge it
 * into your own metadata functions if you have some.
 */
export declare const replayMetadata: {
    click: () => {
        _replay: ReplayViewport;
    };
    keydown: () => {
        _replay: ReplayViewport;
    };
    keyup: () => {
        _replay: ReplayViewport;
    };
};
