import assert from 'node:assert/strict';
import { normalizeTurnError } from './turn-error-normalizer.mjs';

assert.equal(normalizeTurnError({ code: 'HTTP_401', message: 'Authentication fails' }).code, 'AI_AUTH_FAILED');
assert.equal(normalizeTurnError({ code: 'INVALID_CONFIG', message: 'thinkingFormat is not supported' }).code, 'AI_REQUEST_INVALID');
assert.equal(normalizeTurnError({ code: 'MODEL_NOT_FOUND', message: 'model does not exist' }).code, 'AI_MODEL_NOT_FOUND');
assert.equal(normalizeTurnError({ code: 'ETIMEDOUT', message: 'connection timed out' }).code, 'AI_TIMEOUT');
assert.equal(normalizeTurnError({ code: 'TRANSPORT', message: 'Connection error' }).code, 'AI_NETWORK_ERROR');
assert.match(normalizeTurnError({ code: 'SOMETHING_ELSE', message: 'unknown' }).message, /详细错误/);

console.log('PASS turn error normalization');
