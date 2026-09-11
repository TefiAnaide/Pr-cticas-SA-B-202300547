import { test } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import app from '../src/app.js';

test('GET /health responde 200 y status ok', async () => {
    const res = await request(app).get('/health');
    assert.equal(res.status, 200);
    assert.equal(res.body.status, 'ok');
});

test('POST /authorize permite a Admin acceder a ruta1', async () => {
    const res = await request(app).post('/authorize').send({ rol: 'Admin', recurso: 'ruta1' });
    assert.equal(res.status, 200);
    assert.equal(res.body.allowed, true);
});

test('POST /authorize niega a Cliente acceder a ruta1', async () => {
    const res = await request(app).post('/authorize').send({ rol: 'Cliente', recurso: 'ruta1' });
    assert.equal(res.status, 200);
    assert.equal(res.body.allowed, false);
});

test('POST /authorize responde 400 si faltan rol o recurso', async () => {
    const res = await request(app).post('/authorize').send({ rol: 'Admin' });
    assert.equal(res.status, 400);
});
