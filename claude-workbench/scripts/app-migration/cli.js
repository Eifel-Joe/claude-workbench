#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const readline = require('node:readline/promises');
const { migrationPaths } = require('./paths');
const { createClient } = require('./supervisor');
const { detect } = require('./detect');
const { apply } = require('./apply');
const { ITEMS, render, parseInput, renderSummary } = require('./dialog');

// Runs during the app's start: bounded, so a stuck Supervisor cannot hold it up.
const DETECT_TIMEOUT_MS = 10000;

// Lines starting with "WARNING:" are logged as warnings by run.sh.
async function runDetect() {
  const p = migrationPaths();
  try {
    const r = await detect(createClient({ timeoutMs: DETECT_TIMEOUT_MS }), p);
    // Decided (n33): from here an offer file alone says whether a takeover can
    // still come, so the status line and the plugin may write to ~/.claude.
    fs.rmSync(p.undecided, { force: true });
    console.log(r.offered
      ? `App migration: offering data from ${r.offer.name} ${r.offer.version} (${r.offer.slug})`
      : `App migration: nothing to offer (${r.reason})`);
  } catch (e) {
    // An offer from an earlier start may point at an app that is gone now.
    fs.rmSync(p.offer, { force: true });
    // p.undecided stays (run.sh created it): an old app may still be there,
    // and files the status line or the plugin wrote now would keep its files
    // out of a takeover offered on a later start (n33).
    console.log(`WARNING: App migration: detection failed, skipping (${e.message}); `
      + 'status line and Home Assistant plugin wait for the next start');
  }
}

async function runDialog() {
  const p = migrationPaths();
  if (!fs.existsSync(p.offer)) return;
  const offer = JSON.parse(fs.readFileSync(p.offer, 'utf8'));
  let rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  let selected = [...ITEMS];
  let notice;
  try {
    for (;;) {
      process.stdout.write('\x1b[2J\x1b[H' + render(offer, selected, notice));
      const r = parseInput(await rl.question('  > '), selected);
      selected = r.selected;
      notice = r.action === 'invalid' ? 'Type 1–6 to toggle, Enter to take over, s or n.' : undefined;
      if (r.action === 'later') return;
      if (r.action === 'never') {
        fs.writeFileSync(p.state, 'never\n');
        fs.rmSync(p.offer, { force: true });
        return;
      }
      if (r.action === 'apply') {
        // Close readline first: it keeps the terminal in raw mode, where Ctrl+C
        // is a keypress, not a SIGINT for persist-install/tar. A fresh
        // interface asks for the final Enter.
        rl.close();
        rl = null;
        console.log('\n  Creating a backup of the old app and taking over, this can take a few minutes...\n');
        const result = await apply(createClient(), p, offer, selected);
        console.log(renderSummary(result));
        rl = readline.createInterface({ input: process.stdin, output: process.stdout });
        await rl.question('  Press Enter to continue ');
        return;
      }
    }
  } finally {
    if (rl) rl.close();
  }
}

const mode = process.argv[2];
const job = mode === 'detect' ? runDetect() : mode === 'dialog' ? runDialog() : Promise.resolve();
// The dialog sits in front of Claude/the session picker: never block them.
job.catch((e) => console.log(`App migration: ${e.message}`)).finally(() => process.exit(0));
