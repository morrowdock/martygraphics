// SPDX-License-Identifier: Apache-2.0
// Quota-free probe of pinned native library functions, NOT a CLI config dump.
// Do not call initialize(), refreshAuth(), or any content generator.
import fs from 'node:fs';
import {Config, resolveModel, processSingleFileContent, DEFAULT_MODEL_CONFIGS, MemoryContextManager}
  from '/gemini/bundle/chunk-RCB6BI5H.js';
const writeReport = process.stdout.write.bind(process.stdout);
process.stdout.write = process.stderr.write.bind(process.stderr);
const settings = JSON.parse(fs.readFileSync('/home/grader/.gemini/settings.json', 'utf8'));
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
writeReport(JSON.stringify({
  loadedMemory: memory.getGlobalMemory() + memory.getEnvironmentMemory() + memory.getExtensionMemory(),
  toolDefinitions: registry.getFunctionDeclarations(model).map(t => t.name),
  modelWithoutPreviewAccess: resolveModel(model, false, false, false, config),
  modelWithPreviewAccess: resolveModel(model, true, true, true, config),
  thinking: resolved.generateContentConfig?.thinkingConfig,
  bundledModel: DEFAULT_MODEL_CONFIGS.modelDefinitions[model],
  registeredModelBundled: Object.hasOwn(DEFAULT_MODEL_CONFIGS.modelDefinitions, 'gemini-4-argon'),
  textExact: text.llmContent === fs.readFileSync('/packet/probe.txt', 'utf8') && !text.isTruncated,
  imageExact: image.llmContent?.inlineData?.data === fs.readFileSync('/packet/probe.png').toString('base64'),
  imageMime: image.llmContent?.inlineData?.mimeType,
}) + "\n");
process.exit(0);
