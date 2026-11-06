'use strict';

// What counts as one package name from another app's options or venv (n30).
// persist-install reads its first argument as the mode (--ha-cli, -p, ha,
// python ...), and a leading - would reach apk or pip as a flag; both rules
// start with a letter or digit. Same rules as APK_NAME_RE / PIP_SPEC_RE in
// run.sh (auto_install_packages), from unsnow-iac (08686e1e, 83c6997e, found
// in miczu71's fork, branch history/unsnow-full). In JavaScript `[]` is an
// empty class, so the `]` of the pip rule is escaped here;
// tests/test-package-names.sh holds both languages to the same verdicts.
// apk: name, version pin (git=2.47.0-r0), cmd:/so: provides, @repository tags.
const APK_NAME_RE = /^[A-Za-z0-9][A-Za-z0-9._+=<>~:@-]*$/;
// pip: name with extras and version specifiers (pandas[all], foo>=1,<2).
const PIP_SPEC_RE = /^[A-Za-z0-9][\]A-Za-z0-9._+=!~,<>[-]*$/;

const isApkName = (s) => typeof s === 'string' && APK_NAME_RE.test(s);
const isPipSpec = (s) => typeof s === 'string' && PIP_SPEC_RE.test(s);

module.exports = { isApkName, isPipSpec };
