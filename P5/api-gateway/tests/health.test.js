import 'dotenv/config';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import app from '../src/app.js';

test('GET /health responde 200 y status ok', async () => {
    const res = await request(app).get('/health');
    assert.equal(res.status, 200);
    assert.equal(res.body.status, 'ok');
    assert.equal(res.body.service, 'api-gateway');
});

test('GET /api/docs sirve la documentacion Swagger', async () => {
    const res = await request(app).get('/api/docs/');
    assert.equal(res.status, 200);
});

test('ruta desconocida responde 404', async () => {
    const res = await request(app).get('/no-existe');
    assert.equal(res.status, 404);
});
