#!/usr/bin/env node
'use strict';

/**
 * Panel helpers (image-service/public/workbench-ui.js): Shift+Enter inserts a
 * newline instead of submitting (mattbsea's fork, commit 6e44e41f), and the
 * auto-continue button's label.
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const ui = require(path.join(__dirname, '..', 'claude-workbench', 'image-service', 'public', 'workbench-ui.js'));

function key(extra) {
    return Object.assign({
        type: 'keydown', key: 'Enter', shiftKey: true,
        ctrlKey: false, altKey: false, metaKey: false, isComposing: false,
    }, extra);
}

test('isShiftEnter matches plain Shift+Enter only', () => {
    assert.equal(ui.isShiftEnter(key()), true);
    assert.equal(ui.isShiftEnter(key({ shiftKey: false })), false);
    assert.equal(ui.isShiftEnter(key({ ctrlKey: true })), false);
    assert.equal(ui.isShiftEnter(key({ altKey: true })), false);
    assert.equal(ui.isShiftEnter(key({ metaKey: true })), false);
    assert.equal(ui.isShiftEnter(key({ type: 'keyup' })), false);
    assert.equal(ui.isShiftEnter(key({ isComposing: true })), false);
    assert.equal(ui.isShiftEnter(key({ key: 'a' })), false);
});

function fakeWindow(term) {
    const listeners = [];
    return {
        term,
        addEventListener(type, fn, capture) { listeners.push({ type, fn, capture }); },
        fire(event) {
            const e = Object.assign({
                prevented: false, stopped: false,
                preventDefault() { this.prevented = true; },
                stopImmediatePropagation() { this.stopped = true; },
            }, event);
            for (const l of listeners) if (l.type === e.type) l.fn(e);
            return e;
        },
        listeners,
    };
}

test('Shift+Enter sends backslash + CR as typed input and stops the event', () => {
    const inputs = [];
    const win = fakeWindow({ input(data, wasUserInput) { inputs.push([data, wasUserInput]); } });
    assert.equal(ui.installShiftEnter(win), true);
    assert.equal(win.listeners[0].capture, true, 'must run before xterm (capture phase)');

    const e = win.fire(key());
    assert.deepEqual(inputs, [['\\\r', true]]);
    assert.equal(e.prevented, true);
    assert.equal(e.stopped, true);

    const plain = win.fire(key({ shiftKey: false }));
    assert.equal(inputs.length, 1, 'plain Enter is left to xterm');
    assert.equal(plain.prevented, false);
});

test('without term.input Shift+Enter is left alone', () => {
    const win = fakeWindow({});
    ui.installShiftEnter(win);
    const e = win.fire(key());
    assert.equal(e.prevented, false);
});

test('installShiftEnter installs once per window', () => {
    const win = fakeWindow({ input() {} });
    assert.equal(ui.installShiftEnter(win), true);
    assert.equal(ui.installShiftEnter(win), false);
    assert.equal(win.listeners.length, 1);
});

const fmt = (iso) => `T(${iso})`;

test('autoContinueLabel shows off, on, the planned time and unknown', () => {
    assert.deepEqual(ui.autoContinueLabel(null, fmt),
        { text: 'Auto-continue: ?', short: '?', on: false, title: 'Auto-continue after a usage limit: state unknown' });
    assert.deepEqual(ui.autoContinueLabel({ enabled: false, scheduled: [] }, fmt),
        { text: 'Auto-continue: off', short: 'off', on: false, title: 'Auto-continue after a usage limit is off - click to switch it on' });
    assert.deepEqual(ui.autoContinueLabel({ enabled: true, scheduled: [] }, fmt),
        { text: 'Auto-continue: on', short: 'on', on: true, title: 'Auto-continue after a usage limit is on - click to switch it off' });
    assert.deepEqual(ui.autoContinueLabel({ enabled: true, scheduled: [{ pane: '%0', at: 'A' }, { pane: '%1', at: 'B' }] }, fmt),
        { text: 'Continue T(A)', short: 'T(A)', on: true, title: 'Sends "continue" at T(A) - click to switch auto-continue off' });
});

test('keySequence maps the six keys', () => {
    assert.equal(ui.keySequence('esc', {}), '\x1b');
    assert.equal(ui.keySequence('up', {}), '\x1b[A');
    assert.equal(ui.keySequence('down', {}), '\x1b[B');
    assert.equal(ui.keySequence('enter', {}), '\r');
    assert.equal(ui.keySequence('shift-tab', {}), '\x1b[Z');
    assert.equal(ui.keySequence('ctrl-c', {}), '\x03');
});

test('keySequence sends SS3 arrows in application cursor mode', () => {
    const term = { modes: { applicationCursorKeysMode: true } };
    assert.equal(ui.keySequence('up', term), '\x1bOA');
    assert.equal(ui.keySequence('down', term), '\x1bOB');
    assert.equal(ui.keySequence('esc', term), '\x1b');
    assert.equal(ui.keySequence('up', { modes: { applicationCursorKeysMode: false } }), '\x1b[A');
});

test('keySequence copes with a missing term or modes and unknown names', () => {
    assert.equal(ui.keySequence('up', null), '\x1b[A');
    assert.equal(ui.keySequence('down', {}), '\x1b[B');
    assert.equal(ui.keySequence('tab', {}), null);
    assert.equal(ui.keySequence('toString', {}), null);
});

test('createCtrlCGuard lets one Ctrl+C through per two seconds', () => {
    const clock = { t: 10000 };
    const allow = ui.createCtrlCGuard(() => clock.t);
    assert.equal(allow(), true);
    clock.t += 1000;
    assert.equal(allow(), false);
    clock.t += 999;
    assert.equal(allow(), false);
    clock.t += 1;
    assert.equal(allow(), true);
});

test('createCtrlCGuard counts from the last Ctrl+C actually let through', () => {
    const clock = { t: 0 };
    const allow = ui.createCtrlCGuard(() => clock.t, 2000);
    assert.equal(allow(), true);   // sent at 0
    clock.t = 1500;
    assert.equal(allow(), false);  // refused, does not restart the window
    clock.t = 2000;
    assert.equal(allow(), true);   // 2 s after the sent one
});

// Fake key bar: a container with buttons (dataset.key) and one listener list.
function fakeBar(keys) {
    const listeners = {};
    const bar = {
        parentNode: null,
        addEventListener(type, fn) { (listeners[type] = listeners[type] || []).push(fn); },
        fire(type, target) {
            const e = {
                type, target, prevented: false,
                preventDefault() { this.prevented = true; },
            };
            for (const fn of listeners[type] || []) fn(e);
            return e;
        },
        listeners,
        buttons: {},
    };
    for (const k of keys) {
        const classes = new Set();
        bar.buttons[k] = {
            dataset: { key: k },
            parentNode: bar,
            textContent: k === 'ctrl-c' ? '^C' : k,
            classList: {
                add: (c) => classes.add(c),
                remove: (c) => classes.delete(c),
                contains: (c) => classes.has(c),
            },
        };
    }
    return bar;
}

function fakeTerm(extra) {
    const sent = [];
    return Object.assign({ sent, input(data, user) { sent.push([data, user]); } }, extra);
}

const ALL_KEYS = ['esc', 'up', 'down', 'enter', 'shift-tab', 'ctrl-c'];

test('installKeyBar sends the tapped key as typed input', () => {
    const bar = fakeBar(ALL_KEYS);
    const term = fakeTerm();
    assert.equal(ui.installKeyBar(bar, () => term), true);
    bar.fire('click', bar.buttons.down);
    bar.fire('click', bar.buttons.enter);
    bar.fire('click', bar.buttons['shift-tab']);
    assert.deepEqual(term.sent, [['\x1b[B', true], ['\r', true], ['\x1b[Z', true]]);
});

test('installKeyBar keeps the focus in the terminal', () => {
    const bar = fakeBar(ALL_KEYS);
    ui.installKeyBar(bar, () => fakeTerm());
    assert.equal(bar.fire('pointerdown', bar.buttons.esc).prevented, true);
    assert.equal(bar.fire('mousedown', bar.buttons.esc).prevented, true);
    // A tap on the bar's gap is not a key: leave it alone.
    assert.equal(bar.fire('pointerdown', bar).prevented, false);
});

test('installKeyBar finds the key from a child of the button', () => {
    const bar = fakeBar(ALL_KEYS);
    const term = fakeTerm();
    ui.installKeyBar(bar, () => term);
    const label = { parentNode: bar.buttons.up };
    bar.fire('click', label);
    assert.deepEqual(term.sent, [['\x1b[A', true]]);
});

test('installKeyBar does nothing while there is no terminal yet', () => {
    const bar = fakeBar(ALL_KEYS);
    let term = null;
    ui.installKeyBar(bar, () => term, { now: () => 0, setTimeout: () => {} });
    bar.fire('click', bar.buttons['ctrl-c']);           // start page: no term
    assert.equal(bar.buttons['ctrl-c'].textContent, '^C');
    term = fakeTerm({ input: undefined });
    bar.fire('click', bar.buttons.esc);                 // term without input()
    term = fakeTerm();
    bar.fire('click', bar.buttons['ctrl-c']);           // guard was not used up
    assert.deepEqual(term.sent, [['\x03', true]]);
});

test('installKeyBar reads the terminal on every tap', () => {
    const bar = fakeBar(ALL_KEYS);
    const first = fakeTerm();
    const second = fakeTerm({ modes: { applicationCursorKeysMode: true } });
    let current = first;
    ui.installKeyBar(bar, () => current);
    bar.fire('click', bar.buttons.up);
    current = second;                                   // iframe reloaded, vim running
    bar.fire('click', bar.buttons.up);
    assert.deepEqual(first.sent, [['\x1b[A', true]]);
    assert.deepEqual(second.sent, [['\x1bOA', true]]);
});

test('installKeyBar guards Ctrl+C and shows wait until it is free again', () => {
    const bar = fakeBar(ALL_KEYS);
    const term = fakeTerm();
    const clock = { t: 0 };
    const timers = [];
    ui.installKeyBar(bar, () => term, {
        now: () => clock.t,
        setTimeout: (fn, ms) => timers.push([fn, ms]),
    });
    const ctrlC = bar.buttons['ctrl-c'];
    bar.fire('click', ctrlC);
    clock.t = 500;
    bar.fire('click', ctrlC);
    assert.deepEqual(term.sent, [['\x03', true]]);
    assert.equal(ctrlC.textContent, 'wait');
    assert.equal(ctrlC.classList.contains('key-wait'), true);
    assert.equal(timers.length, 1);
    assert.equal(timers[0][1], 2000);
    timers[0][0]();                                     // 2 s later
    assert.equal(ctrlC.textContent, '^C');
    assert.equal(ctrlC.classList.contains('key-wait'), false);
    clock.t = 2000;
    bar.fire('click', ctrlC);
    assert.equal(term.sent.length, 2);
});

test('installKeyBar installs once per bar', () => {
    const bar = fakeBar(ALL_KEYS);
    const term = fakeTerm();
    assert.equal(ui.installKeyBar(bar, () => term), true);
    assert.equal(ui.installKeyBar(bar, () => term), false);
    bar.fire('click', bar.buttons.esc);
    assert.deepEqual(term.sent, [['\x1b', true]]);
    assert.equal(ui.installKeyBar(null, () => term), false);
});
