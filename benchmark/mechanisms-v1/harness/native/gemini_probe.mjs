// SPDX-License-Identifier: Apache-2.0
// Quota-free real settings-loader + native Config probe, NOT a post-auth dump.
// Do not call initialize(), refreshAuth(), or any content generator.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {installDispatchGuard} from '/out/guard.mjs';
import {Config, resolveModel, processSingleFileContent, DEFAULT_MODEL_CONFIGS, MemoryContextManager}
  from '/gemini/bundle/chunk-RCB6BI5H.js';
const writeReport = process.stdout.write.bind(process.stdout);
process.stdout.write = process.stderr.write.bind(process.stderr);
const {loadSettings} = await import('/gemini/bundle/chunk-VFM6AETN.js');
const loaded = loadSettings('/packet');
if (loaded.errors.length) throw new Error('Native settings loader rejected configuration');
const settings = loaded.merged;
const config = new Config({
  sessionId: '00000000-0000-4000-8000-000000000001', targetDir: '/packet', cwd: '/packet',
  model: settings.model.name, coreTools: settings.tools.core, useRipgrep: settings.tools.useRipgrep,
  mcpEnabled: settings.admin.mcp.enabled, mcpServers: settings.mcpServers,
  extensionsEnabled: settings.admin.extensions.enabled, skillsSupport: settings.skills.enabled,
  enableHooks: settings.hooksConfig.enabled, enableAgents: settings.experimental.enableAgents,
  includeDirectoryTree: settings.context.includeDirectoryTree,
  plan: settings.general.plan.enabled, checkpointing: settings.general.checkpointing.enabled,
  dynamicModelConfiguration: settings.experimental.dynamicModelConfiguration,
  modelConfigServiceConfig: settings.modelConfigs, telemetry: settings.telemetry,
  interactive: false, trustedFolder: true, memoryBoundaryMarkers: settings.context.memoryBoundaryMarkers,
});
const registry = await config.createToolRegistry();
await config.storage.initialize();
const memory = new MemoryContextManager(config);
await memory.refresh();
const model = config.getModel();
const resolved = config.getModelConfigService().getResolvedConfig({model, isChatModel: true});
const text = await processSingleFileContent('/packet/probe.txt', '/packet', config.getFileSystemService());
const image = await processSingleFileContent('/packet/probe.png', '/packet', config.getFileSystemService());
// Synthetic auth lifecycle only: no native initialize/refreshAuth or provider
// methods run. Use the real native registry, then contaminate it after startup.
const dispatchGuard = {};
if (registry.getAllTools().length === 0) for (const method of ['generateContent', 'generateContentStream']) {
  let sends = 0;
  const request = {model, config: {thinkingConfig: {thinkingLevel: 'HIGH'}, tools: [{functionDeclarations: []}]}};
  class SyntheticLifecycle {
    initialized = false;
    registry = registry;
    getToolRegistry() { return this.registry; }
    getModel() { return model; }
    isInitialized() { return this.initialized; }
    async refreshAuth() {
      this.contentGenerator = {generateContent: () => ++sends, generateContentStream: () => ++sends};
      this.cachedGenerator = this.contentGenerator;
      assert.throws(() => this.cachedGenerator[method](request), /startup\/auth incomplete/);
    }
  }
  installDispatchGuard(SyntheticLifecycle, model);
  const lifecycle = new SyntheticLifecycle();
  await lifecycle.refreshAuth(); // Synthetic method above, never native auth.
  assert.throws(() => lifecycle.cachedGenerator[method](request), /startup\/auth incomplete/);
  lifecycle.initialized = true;
  lifecycle.registry = undefined;
  assert.throws(() => lifecycle.cachedGenerator[method](request), /startup\/auth incomplete/);
  lifecycle.registry = registry;
  // A tool introduced after startup (including a remote MCP tool) must stop
  // dispatch even when a model-filtered declaration list would be empty.
  const getAllTools = registry.getAllTools.bind(registry);
  registry.getAllTools = () => [{name: 'synthetic_remote_tool'}];
  assert.throws(() => lifecycle.cachedGenerator[method](request), /final tool registry/);
  registry.getAllTools = getAllTools;
  const declarations = registry.getFunctionDeclarations.bind(registry);
  registry.getFunctionDeclarations = () => [{name: 'synthetic_function'}];
  assert.throws(() => lifecycle.cachedGenerator[method](request), /final tool registry/);
  registry.getFunctionDeclarations = declarations;
  for (const bad of [{...request, model: 'other'},
    {model, config: {tools: [{functionDeclarations: [{name: 'hidden'}]}]}},
    {model, config: {thinkingConfig: {thinkingLevel: 'LOW'}}},
    {model, config: {thinkingConfig: {thinkingLevel: 'HIGH'}, tools: [{googleSearch: {}}]}}]) {
    assert.throws(() => lifecycle.cachedGenerator[method](bad), /request differs/);
  }
  assert.equal(sends, 0);
  assert.equal(lifecycle.cachedGenerator[method](request), 1);
  assert.throws(() => lifecycle.cachedGenerator[method](request), /second generation attempt/);
  assert.equal(sends, 1);
  dispatchGuard[method] = true;
}
writeReport(JSON.stringify({
  dispatchGuard,
  loadedMemory: memory.getGlobalMemory() + memory.getEnvironmentMemory() + memory.getExtensionMemory(),
  toolDefinitions: registry.getFunctionDeclarations(model).map(t => t.name),
  modelWithoutPreviewAccess: resolveModel(model, false, false, false, config),
  modelWithPreviewAccess: resolveModel(model, true, true, true, config),
  modelConditions: [false, true].flatMap(useGemini3_1 => [false, true].flatMap(useCustomTools =>
    [false, true].map(hasAccessToPreview => ({useGemini3_1, useCustomTools, hasAccessToPreview,
      resolved: resolveModel(model, useGemini3_1, useCustomTools, hasAccessToPreview, config)})))),
  mergedAdmin: settings.admin,
  isolationSettings: {core: settings.tools.core, mcpServers: settings.mcpServers,
    skills: settings.skills.enabled, hooks: settings.hooksConfig.enabled,
    agents: settings.experimental.enableAgents},
  registeredModelThinking: config.getModelConfigService().getResolvedConfig({
    model: 'gemini-4-argon', isChatModel: true}).generateContentConfig?.thinkingConfig,
  thinking: resolved.generateContentConfig?.thinkingConfig,
  bundledModel: DEFAULT_MODEL_CONFIGS.modelDefinitions[model] ?? null,
  registeredModelBundled: Object.hasOwn(DEFAULT_MODEL_CONFIGS.modelDefinitions, 'gemini-4-argon'),
  textExact: text.llmContent === fs.readFileSync('/packet/probe.txt', 'utf8') && !text.isTruncated,
  imageExact: image.llmContent?.inlineData?.data === fs.readFileSync('/packet/probe.png').toString('base64'),
  imageMime: image.llmContent?.inlineData?.mimeType,
}) + "\n");
process.exit(0);
