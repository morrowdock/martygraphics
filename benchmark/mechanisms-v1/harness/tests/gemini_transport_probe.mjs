// SPDX-License-Identifier: Apache-2.0
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {registerHooks} from 'node:module';

registerHooks({load(url, context, nextLoad) {
  const loaded = nextLoad(url, context);
  if (url === 'file:///gemini/bundle/chunk-RCB6BI5H.js') {
    return {...loaded, source: loaded.source +
      '\nexport const TestOAuth2Client = import_google_auth_library3.OAuth2Client;\n'};
  }
  return loaded;
}});

const {CodeAssistServer, TestOAuth2Client} = await import('/gemini/bundle/chunk-RCB6BI5H.js');
const [method, statusText, mode = 'guarded'] = process.argv.slice(2);
if (mode !== 'baseline') await import('/out/guard.mjs');
const status = Number(statusText);
const client = new TestOAuth2Client({clientId: 'synthetic', clientSecret: 'synthetic'});
client.setCredentials({access_token: 'synthetic-access', refresh_token: 'synthetic-refresh',
  ...(mode === 'expired' ? {expiry_date: 1} : {})});
const posts = [];
let refreshes = 0;
const transport = async options => {
  if (new URL(options.url).pathname === '/token') {
    refreshes++;
    return {data: {access_token: 'synthetic-refreshed', expires_in: 3600}};
  }
  assert.equal(options.method, 'POST');
  assert.match(new URL(options.url).pathname, /:(?:generateContent|streamGenerateContent)$/);
  if (mode !== 'baseline') {
    assert.equal(options.retry, false);
    assert.deepEqual(options.retryConfig, {retry: 0});
    assert.equal(options.redirect, 'error');
    assert.equal(options.maxRedirects, 0);
  }
  posts.push({url: options.url, body: options.body, refreshesBeforeDispatch: refreshes});
  const error = new Error('Synthetic HTTP ' + status);
  error.response = {status, config: options};
  throw error;
};
client.transporter.request = transport;

const request = {model: process.env.MARTYGRAPHICS_GEMINI_MODEL,
  contents: [{role: 'user', parts: [{text: 'Synthetic transport fixture'}]}],
  config: {thinkingConfig: {thinkingLevel: 'HIGH'}, tools: []}};
let outcome = 'unexpected-success';
let reason;
try {
  const server = new CodeAssistServer(client, 'synthetic-project');
  await server[method](request, 'synthetic-prompt');
} catch (error) {
  outcome = 'refused';
  reason = error.message;
}
let secondRefusal;
if (mode === 'second-client') {
  const otherClient = new TestOAuth2Client({clientId: 'synthetic-other'});
  otherClient.setCredentials({access_token: 'synthetic-other', expiry_date: Date.now() + 3600000});
  otherClient.transporter.request = transport;
  const otherServer = new CodeAssistServer(otherClient, 'synthetic-other-project');
  const otherMethod = method === 'generateContent' ? 'generateContentStream' : 'generateContent';
  try {
    await otherServer[otherMethod](request, 'synthetic-second-prompt');
  } catch (error) {
    secondRefusal = error.message;
  }
}
fs.writeFileSync('/out/transport-result.json', JSON.stringify({method, status, mode,
  generationPosts: posts.length, refreshes, posts, outcome, reason, secondRefusal}));
process.exit(outcome === 'refused' ? 1 : 0);
