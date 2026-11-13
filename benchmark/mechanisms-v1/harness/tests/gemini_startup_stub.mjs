// SPDX-License-Identifier: Apache-2.0
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {registerHooks} from 'node:module';

registerHooks({load(url, context, nextLoad) {
  const loaded = nextLoad(url, context);
  if (url === 'file:///gemini/bundle/chunk-RCB6BI5H.js') {
    const source = String(loaded.source);
    const signature = 'async function getOauthClient(authType, config2) {';
    assert.equal(source.split(signature).length, 2);
    return {...loaded, source: source.replace(signature, signature +
      '\nreturn {request: async () => {throw new Error("OFFLINE AUTH NETWORK REFUSED");}};\n')};
  }
  return loaded;
}});
const {Config, BaseLlmClient, loadTrustedFolders} = await import('/gemini/bundle/chunk-RCB6BI5H.js');

Config.prototype.refreshAuth = async function (authType) {
  assert.equal(authType, 'oauth-personal');
  assert.equal(fs.existsSync('/home/grader/.gemini/oauth_creds.json'), false);
  const refuse = () => {
    fs.writeFileSync('/out/generation-refused.json', JSON.stringify({outcome: 'refused'}));
    throw new Error('OFFLINE SYNTHETIC GENERATION REFUSED');
  };
  this.contentGenerator = {
    generateContent: refuse, generateContentStream: refuse,
    countTokens: async () => ({totalTokens: 1}),
  };
  this.contentGeneratorConfig = {authType};
  this.baseLlmClient = new BaseLlmClient(this.contentGenerator, this);
  fs.writeFileSync('/out/synthetic-auth.json', JSON.stringify({authType}));
};

const initialize = Config.prototype.initialize;
Config.prototype.initialize = async function (...args) {
  const result = await initialize.apply(this, args);
  assert.equal(this.isInitialized(), true);
  assert.equal(this.isTrustedFolder(), true);
  const trust = loadTrustedFolders();
  assert.equal(trust.isPathTrusted('/packet'), true);
  assert.equal(trust.isPathTrusted('/home/grader'), undefined);
  assert.equal(trust.isPathTrusted('/input'), undefined);
  fs.writeFileSync('/out/initialized.json', JSON.stringify({initialized: true,
    trusted: this.isTrustedFolder(), tools: this.getToolRegistry().getAllTools().length}));
  return result;
};

await import('/out/guard.mjs');
