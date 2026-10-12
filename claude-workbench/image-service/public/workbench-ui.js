/**
 * Small panel helpers, loaded by index.html and testable in Node
 * (tests/test-workbench-ui.js).
 *
 * Shift+Enter: Claude Code's /terminal-setup cannot configure ttyd in a
 * browser, so Shift+Enter sent a plain CR and submitted. Claude Code treats
 * backslash + CR as "newline, don't submit" in any terminal (in bash it is a
 * line continuation), so Shift+Enter sends that instead (mattbsea's fork,
 * commit 6e44e41f). A capture listener on the ttyd frame's window runs before
 * xterm.js, like the Ctrl+V handler in index.html; ttyd's own key handler slot
 * stays untouched. term.input() is xterm.js 5.4 (bundled with ttyd 1.7.7): it
 * goes out exactly like typed keys, unlike term.paste(), which would wrap the
 * text in bracketed-paste markers.
 *
 * Phone key bar: Esc, arrows, Enter, Shift+Tab and a guarded Ctrl+C, sent the
 * same way (installKeyBar).
 */
(function (root, factory) {
    'use strict';
    var api = factory();
    if (typeof module === 'object' && module.exports) {
        module.exports = api;
    }
    if (root) {
        root.ClaudeWorkbenchUi = api;
    }
})(typeof self !== 'undefined' ? self : null, function () {
    'use strict';

    var INSTALL_FLAG = '__claudeShiftEnterInstalled';

    function isShiftEnter(e) {
        return e.type === 'keydown' && e.key === 'Enter' && e.shiftKey &&
            !e.ctrlKey && !e.altKey && !e.metaKey && !e.isComposing;
    }

    /** Install the Shift+Enter handler on the ttyd frame's window, once. */
    function installShiftEnter(win) {
        if (!win || win[INSTALL_FLAG]) return false;
        win[INSTALL_FLAG] = true;
        win.addEventListener('keydown', function (e) {
            if (!isShiftEnter(e)) return;
            var term = win.term;
            if (!term || typeof term.input !== 'function') return; // plain Enter then
            e.preventDefault();
            e.stopImmediatePropagation();
            term.input('\\\r', true);
        }, true);
        return true;
    }

    /**
     * Label for the auto-continue button from GET /auto-continue (null when
     * that failed). formatTime turns an ISO time into the viewer's HH:MM.
     */
    function autoContinueLabel(status, formatTime) {
        if (!status || typeof status.enabled !== 'boolean') {
            return { text: 'Auto-continue: ?', short: '?', on: false,
                title: 'Auto-continue after a usage limit: state unknown' };
        }
        if (!status.enabled) {
            return { text: 'Auto-continue: off', short: 'off', on: false,
                title: 'Auto-continue after a usage limit is off - click to switch it on' };
        }
        var next = (status.scheduled || [])[0];
        if (next) {
            var time = formatTime(next.at);
            return { text: 'Continue ' + time, short: time, on: true,
                title: 'Sends "continue" at ' + time + ' - click to switch auto-continue off' };
        }
        return { text: 'Auto-continue: on', short: 'on', on: true,
            title: 'Auto-continue after a usage limit is on - click to switch it off' };
    }

    // Phone key bar (index.html #key-bar): what each key sends, as xterm.js
    // would for the real key. Arrows follow the terminal's cursor-key mode
    // (DECCKM): full-screen programs switch to the SS3 form, so it is read on
    // every tap (mattbsea's fork, commit ed215953).
    var KEY_SEQUENCES = {
        'esc': '\x1b',
        'up': '\x1b[A',
        'down': '\x1b[B',
        'enter': '\r',
        'shift-tab': '\x1b[Z',
        'ctrl-c': '\x03'
    };
    var APP_CURSOR_SEQUENCES = { 'up': '\x1bOA', 'down': '\x1bOB' };

    function keySequence(name, term) {
        if (!Object.prototype.hasOwnProperty.call(KEY_SEQUENCES, name)) return null;
        var appCursor = !!(term && term.modes && term.modes.applicationCursorKeysMode === true);
        if (appCursor && Object.prototype.hasOwnProperty.call(APP_CURSOR_SEQUENCES, name)) {
            return APP_CURSOR_SEQUENCES[name];
        }
        return KEY_SEQUENCES[name];
    }

    /**
     * Two Ctrl+C in a row quit Claude Code, which ends the tmux session; on a
     * phone a double tap is easy. Lets one through per window, counted from
     * the last one let through.
     */
    function createCtrlCGuard(now, windowMs) {
        var clock = now || Date.now;
        var span = windowMs === undefined ? 2000 : windowMs;
        var lastSent = null;
        return function allow() {
            var t = clock();
            if (lastSent !== null && t - lastSent < span) return false;
            lastSent = t;
            return true;
        };
    }

    var KEYBAR_FLAG = '__claudeKeyBarInstalled';

    /**
     * Wire the phone key bar. getTerm is asked on every tap: the ttyd frame
     * reloads on reconnect and then has a new term. pointerdown and mousedown
     * are cancelled so the tap does not move the focus out of the terminal -
     * that would close the on-screen keyboard (and a tap with the keyboard
     * closed must not open it).
     */
    function installKeyBar(bar, getTerm, options) {
        if (!bar || bar[KEYBAR_FLAG]) return false;
        bar[KEYBAR_FLAG] = true;
        var opts = options || {};
        var windowMs = opts.ctrlCWindowMs === undefined ? 2000 : opts.ctrlCWindowMs;
        var allowCtrlC = createCtrlCGuard(opts.now, windowMs);
        var later = opts.setTimeout || function (fn, ms) { return setTimeout(fn, ms); };

        function keyButton(target) {
            for (var el = target; el && el !== bar; el = el.parentNode) {
                if (el.dataset && el.dataset.key) return el;
            }
            return null;
        }

        function keepFocus(e) {
            if (keyButton(e.target)) e.preventDefault();
        }
        bar.addEventListener('pointerdown', keepFocus);
        bar.addEventListener('mousedown', keepFocus);

        bar.addEventListener('click', function (e) {
            var button = keyButton(e.target);
            if (!button) return;
            var term = getTerm();
            if (!term || typeof term.input !== 'function') return; // start page
            var name = button.dataset.key;
            var seq = keySequence(name, term);
            if (seq === null) return;
            if (name === 'ctrl-c') {
                if (!allowCtrlC()) return;
                button.textContent = 'wait';
                button.classList.add('key-wait');
                later(function () {
                    button.textContent = '^C';
                    button.classList.remove('key-wait');
                }, windowMs);
            }
            term.input(seq, true);
        });
        return true;
    }

    return {
        isShiftEnter: isShiftEnter,
        installShiftEnter: installShiftEnter,
        autoContinueLabel: autoContinueLabel,
        keySequence: keySequence,
        createCtrlCGuard: createCtrlCGuard,
        installKeyBar: installKeyBar
    };
});
