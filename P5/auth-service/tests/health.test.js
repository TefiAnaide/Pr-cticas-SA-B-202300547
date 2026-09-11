import { test } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import app from '../src/app.js';

test('GET /health responde 200 y status ok', async () => {
    const res = await request(app).get('/health');
    assert.equal(res.status, 200);
    assert.equal(res.body.status, 'ok');
    assert.equal(res.body.service, 'auth-service');
});

test('ruta desconocida responde 404', async () => {
    const res = await request(app).get('/no-existe');
    assert.equal(res.status, 404);
});
