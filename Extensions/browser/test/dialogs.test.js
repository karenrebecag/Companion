import test from 'node:test';
import assert from 'node:assert/strict';
import { dialogPolicy, sanitizeDialogMessage, createDialogReports } from '../lib/dialogs.js';

test('alert: accepted, not escalated', () => {
  const out = dialogPolicy({ kind: 'alert', message: 'anything' });
  assert.deepEqual([out.accept, out.escalate], [true, false]);
});

test('confirm: always no and escalated; a destructive question is flagged', () => {
  const safe = dialogPolicy({ kind: 'confirm', message: 'Are you sure?' });
  assert.deepEqual([safe.accept, safe.answer, safe.escalate, safe.destructive], [false, 'no', true, false]);
  for (const m of ['Do you want to delete this account?', 'Remove this item?', 'This action is irreversible.',
    'eliminar cuenta', 'borrar archivo', 'descartar cambios', 'pagar pedido', 'comprar ahora',
    'enviar dinero', 'transferir fondos', 'excluir usuario', 'apagar servidor', 'Show deleted items?']) {
    assert.equal(dialogPolicy({ kind: 'confirm', message: m }).destructive, true, m);
  }
});

test('prompt: the page default is accepted unless the question is destructive', () => {
  const out = dialogPolicy({ kind: 'prompt', message: 'Your name', defaultValue: 'Ana' });
  assert.deepEqual([out.accept, out.promptText, out.answer, out.escalate, out.destructive], [true, 'Ana', 'default', true, false]);
});

test('S3 a destructive prompt is cancelled and its default is not echoed', () => {
  const out = dialogPolicy({ kind: 'prompt', message: 'Type DELETE to permanently delete the repo', defaultValue: 'DELETE' });
  assert.deepEqual([out.accept, out.promptText, out.answer, out.destructive], [false, '', 'no', true]);
});

test('beforeunload: the page stays and it is escalated, unless Companion is the one leaving', () => {
  const stay = dialogPolicy({ kind: 'beforeunload', message: 'Changes may not be saved.' });
  assert.deepEqual([stay.accept, stay.answer, stay.escalate], [false, 'no', true]);
  const leave = dialogPolicy({ kind: 'beforeunload', message: 'x', leaving: true });
  assert.deepEqual([leave.accept, leave.escalate], [true, false]);
});

test('an unknown kind is treated like an alert', () => {
  const out = dialogPolicy({ kind: 'mystery', message: 'x' });
  assert.deepEqual([out.accept, out.escalate], [true, false]);
});

test('S2 sanitizeDialogMessage strips control, format, private, unassigned and separator characters', () => {
  assert.equal(sanitizeDialogMessage('hello\u0000\u0007world'), 'hello world');
  assert.equal(sanitizeDialogMessage('a‮b⁦c\u0085d؜e­f'), 'abc def');
  assert.equal(sanitizeDialogMessage('a​b‏c﻿d'), 'abcd');
  assert.equal(sanitizeDialogMessage('x\u{E0041}y᠎z￹w️vu'), 'xyzwvu');
  assert.equal(sanitizeDialogMessage('a b c'), 'a b c');
  assert.equal(sanitizeDialogMessage('   collapse    spaces   '), 'collapse spaces');
  assert.equal(sanitizeDialogMessage(null), '');
  assert.equal(sanitizeDialogMessage(42), '');
});

test('sanitizeDialogMessage caps by code points, not UTF-16 units', () => {
  const out = sanitizeDialogMessage('\u{1F600}'.repeat(500), 120);
  assert.equal(Array.from(out).length, 120);
  assert.doesNotMatch(out, /\p{Cs}/u);
  assert.equal(Array.from(sanitizeDialogMessage('x'.repeat(500))).length, 120);
});

test('C1 controls in a long message are neutralised, so the check can fail', () => {
  const out = sanitizeDialogMessage('a\u0085\u009fb' + 'x'.repeat(500));
  assert.doesNotMatch(out, /[\u0080-\u009f]/);
  assert.ok(out.startsWith('a b'));
});

const entry = (n) => ({ kind: 'confirm', answer: 'no', destructive: false, message: `q${n}` });

test('F3 reports keep the last five entries and count the rest', () => {
  const reports = createDialogReports();
  for (let i = 0; i < 8; i++) reports.record(1, entry(i));
  const out = reports.attach({ done: 'ok' }, 1);
  assert.deepEqual(out.dialogs.map((d) => d.message), ['q3', 'q4', 'q5', 'q6', 'q7']);
  assert.equal(out.more, 3);
});

test('F3 attach never mutates the result it is given', () => {
  const reports = createDialogReports();
  reports.record(1, entry(1));
  const original = Object.freeze({ done: 'ok' });
  const out = reports.attach(original, 1);
  assert.notEqual(out, original);
  assert.deepEqual(original, { done: 'ok' });
  const page = Object.freeze({ page: Object.freeze({ text: 't' }) });
  reports.record(1, entry(2));
  assert.equal(reports.attach(page, 1).page, page.page);
});

test('F3 drain empties the tab, and tabs do not share entries', () => {
  const reports = createDialogReports();
  reports.record(1, entry(1));
  reports.record(2, entry(2));
  assert.equal(reports.attach({ done: 'ok' }, 1).dialogs.length, 1);
  assert.equal(reports.attach({ done: 'ok' }, 1).dialogs, undefined);
  assert.equal(reports.attach({ done: 'ok' }, 2).dialogs[0].message, 'q2');
});

test('F3 clear drops what a tab had queued', () => {
  const reports = createDialogReports();
  reports.record(1, entry(1));
  reports.clear(1);
  assert.equal(reports.attach({ done: 'ok' }, 1).dialogs, undefined);
});

test('T6 a result with neither a done text nor a page keeps the queue, and so does a non-integer tab', () => {
  const reports = createDialogReports();
  reports.record(1, entry(1));
  const shapeless = { tabs: [] };
  assert.equal(reports.attach(shapeless, 1), shapeless);
  assert.equal(reports.attach({ done: 'ok' }, undefined).dialogs, undefined);
  assert.equal(reports.attach({ page: { text: '' } }, 1).dialogs.length, 1);
});

test('S4 ten thousand dialogs at once keep at most five entries and a bounded memory', () => {
  const reports = createDialogReports();
  for (let i = 0; i < 10000; i++) reports.record(1, entry(i));
  const out = reports.attach({ done: 'ok' }, 1);
  assert.equal(out.dialogs.length, 5);
  assert.equal(out.more, 9995);
  assert.equal(reports.size(), 0);
});

test('S4 after the burst window a tab records again', () => {
  let t = 0;
  const reports = createDialogReports({ now: () => t });
  for (let i = 0; i < 30; i++) reports.record(1, entry(i));
  reports.attach({ done: 'ok' }, 1);
  t = 1500;
  reports.record(1, entry('late'));
  const out = reports.attach({ done: 'ok' }, 1);
  assert.deepEqual(out.dialogs.map((d) => d.message), ['qlate']);
  assert.equal(out.more, 0);
});
