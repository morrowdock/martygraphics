// SPDX-License-Identifier: Apache-2.0
// Loaded by Node --import before the untouched pinned CLI entry point.
import {Config, CodeAssistServer} from '/gemini/bundle/chunk-RCB6BI5H.js';

export function installTransportGuard(ServerClass) {
  const protectedTransports = new WeakSet();
  let generationPosts = 0;
  for (const method of ['requestPost', 'requestStreamingPost']) {
    const original = ServerClass.prototype[method];
    ServerClass.prototype[method] = function (...args) {
      const transport = this.client?.transporter;
      if (!transport || typeof transport.request !== 'function') {
        throw new Error('G2 dispatch refused: unsupported auth transport');
      }
      if (!protectedTransports.has(transport)) {
        const request = transport.request.bind(transport);
        transport.request = options => {
          const path = new URL(options.url).pathname;
          if (/:(?:generateContent|streamGenerateContent)$/.test(path)) {
            if (options.method !== 'POST' || generationPosts++ !== 0) {
              throw new Error('G2 dispatch refused: second generation POST or unsupported method');
            }
            options = {...options, retry: false, retryConfig: {retry: 0},
              redirect: 'error', maxRedirects: 0};
          }
          return request(options);
        };
        protectedTransports.add(transport);
      }
      return original.apply(this, args);
    };
  }
}

export function assertDispatchAllowed(config, request, model, authenticated) {
  const registry = config.getToolRegistry();
  if (!authenticated || !config.isInitialized() || !registry ||
      registry.getAllTools().length !== 0 || registry.getFunctionDeclarations().length !== 0) {
    throw new Error('G2 dispatch refused: startup/auth incomplete or final tool registry is not empty');
  }
  const tools = request?.config?.tools ?? [];
  // Native GeminiChat emits [{functionDeclarations: []}] for an empty registry.
  // Permit that empty wrapper, never built-in tools or unknown tool fields.
  const emptyTools = Array.isArray(tools) && tools.every(tool => tool &&
    Object.keys(tool).length === 1 && Array.isArray(tool.functionDeclarations) &&
    tool.functionDeclarations.length === 0);
  if (config.getModel() !== model || request?.model !== model || !emptyTools ||
      request.config?.thinkingConfig?.thinkingLevel !== 'HIGH') {
    throw new Error('G2 dispatch refused: request differs from model/thinking/no-tools policy');
  }
}

export function installDispatchGuard(ConfigClass, model) {
  const original = ConfigClass.prototype.refreshAuth;
  const states = new WeakMap();
  // One generation attempt per CLI process, including retry/fallback attempts.
  let attempts = 0;
  ConfigClass.prototype.refreshAuth = async function (...args) {
    let state = states.get(this);
    if (!state) {
      state = {authenticated: false, generator: undefined};
      states.set(this, state);
      const protect = generator => {
        if (!generator) return generator;
        for (const method of ['generateContent', 'generateContentStream']) {
          if (typeof generator[method] !== 'function') {
            throw new Error('G2 dispatch refused: unsupported content generator');
          }
          const dispatch = generator[method].bind(generator);
          generator[method] = (...params) => {
            assertDispatchAllowed(this, params[0], model, state.authenticated);
            if (attempts++ !== 0) throw new Error('G2 dispatch refused: second generation attempt');
            return dispatch(...params);
          };
        }
        return generator;
      };
      const previous = this.contentGenerator;
      // Install before auth assigns the generator. BaseLlmClient and cached
      // references see the same guarded object; auth-time generation fails too.
      Object.defineProperty(this, 'contentGenerator', {
        configurable: false, enumerable: true,
        get: () => state.generator,
        set: value => { state.generator = protect(value); },
      });
      this.contentGenerator = previous;
    }
    state.authenticated = false;
    const result = await original.apply(this, args);
    state.authenticated = true;
    return result;
  };
}

installDispatchGuard(Config, process.env.MARTYGRAPHICS_GEMINI_MODEL);
installTransportGuard(CodeAssistServer);
