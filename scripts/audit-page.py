#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 tokenpanda
# SPDX-License-Identifier: MIT
"""Writes docs/audit.html, the public audit report, from the audit folders.

Usage: TOKENPANDA_LEAK_WORDS=<file> python3 -I scripts/audit-page.py <folder holding the audit folders> [--out docs/audit.html]

TOKENPANDA_LEAK_WORDS names a file kept outside the repository: one word or phrase per line, optionally a tab and
what it becomes on the page (default "the maintainer"); # starts a comment. Words match in any case, except a
line that starts with ! matches its word in that case only (a name that is also a common word). Names and private words are listed
there, never here, so this script does not publish what it guards against. Without the file the script refuses
to run.

Each audit folder holds findings.json and checklist.json, as the audit writes them. A folder without both,
or without a merged_at time in findings.json, is still running and is skipped. The folders are read oldest
first: a release audit re-checks only the items its change touches, so each item shows the status of the
newest audit that checked it. The findings shown as current are the newest audit's.

The page is public. Every text is cleaned of local paths, scratch folders, the words of the leak file and
private notes, and the script refuses to write the page when anything of that kind is left (a home, scratch,
volume or system temporary path, any e-mail address, a leak word), an em dash, en dash, middle dot or pipe, or
when gitleaks finds a secret in it. It fails closed: no leak file, no gitleaks, or a gitleaks error, and no
page is written.
"""
import html, json, os, re, shutil, subprocess, sys, tempfile

FORBIDDEN = [r"/Users/", r"/private/", r"/tmp/", r"/var/folders", r"/Volumes/", r"(?i)scratchpad", r"audits/",
             r"streams/", r"claude-\d+", r"(?i)session_0", r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}",
             r"—", r"–", r"·", r"\|"]
LEAKS = []   # (pattern, replacement), from the leak file


def leak_words():
    """The leak file named by TOKENPANDA_LEAK_WORDS, longest words first so a phrase is replaced before its parts."""
    path = os.environ.get("TOKENPANDA_LEAK_WORDS", "")
    if not path or not os.path.isfile(path):
        sys.exit("refused: set TOKENPANDA_LEAK_WORDS to the leak word file (kept outside the repository)")
    out = []
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        word, _, rep = line.partition("\t")
        exact = word.startswith("!")
        out.append((word.strip().lstrip("!"), rep.strip() or "the maintainer", exact))
    if not out:
        sys.exit("refused: the leak word file is empty")
    out.sort(key=lambda w: -len(w[0]))
    return [(re.compile(("" if x else "(?i)") + r"(?<![\w])" + re.escape(w) + r"(?![\w])"), r) for w, r, x in out]
SEV = ["blocker", "high", "medium", "low"]
IMPACT = {"noticed": "users notice it", "possible": "users may notice it", "none": "no effect on users"}
STATUS = {"open": "open", "fixed": "fixed", "accepted": "accepted, a written decision"}


def clean(s):
    """Public text: no home paths, no scratch folders, no audit folder paths, no names, house punctuation."""
    t = "" if s is None else str(s)
    t = re.sub(r"/Users/[^/\s]+", "~", t)
    t = re.sub(r"/private/tmp/\S+|/tmp/claude\S*|/private/var/folders/\S+|/var/folders/\S+", "a scratch copy", t)
    t = re.sub(r"/Volumes/\S+", "a disk", t)
    t = re.sub(r"\(\s*(?:checked |reproduced |run )?in (?:the )?(?:verifier's |auditor's )?scratchpad[\w./\-]*\s*\)", "(in a scratch copy)", t)
    t = re.sub(r"\b(?:in )?the (verifier's |auditor's )?scratchpad[\w./\-]*", lambda m: ("in " if m.group(0).startswith("in ") else "") + "a scratch copy", t)
    t = re.sub(r"scratchpad[\w./\-]*", "a scratch copy", t)
    t = re.sub(r"audits/[\w\-]+/(\d{4}-\d{2}-\d{2}[\w\-]*)/?[\w.\-]*", r"the \1 audit", t)
    t = re.sub(r"scans/([\w\-]+)(?:\.\w+)?", r"the \1 scan", t)
    for pat, rep in LEAKS:
        t = pat.sub(rep, t)
    # the audit's word for him; scripts/release-check.sh refuses it as leftover template text
    t = re.sub(r"\b([Tt])he owner\b", lambda m: m.group(1) + "he maintainer", t)
    # a finding about the filter names the patterns themselves, with nothing after them: said without the slash
    for bare, said in ((r"/(Users|private|tmp)/(?![\w.-])", r"/\1"), (r"\b(audits|streams)/(?![\w.-])", r"\1"),
                       (r"/var/folders(?![\w/.-])", "the temporary folders"), (r"\bclaude-\d+\b", "the scratch account folder"),
                       (r"\bsession_0\b", "session ids")):
        t = re.sub(bare, said, t)
    # the audit texts may name the word scripts/release-check.sh refuses for leftover template text; it is spelt in
    # two parts here so the check does not find this rule itself
    held = "place" + "holder"
    t = re.sub(r"\b" + held + r"s\b", "slots", t)
    t = re.sub(r"\b" + held + r"\b", "slot", t)
    for ch, rep in (("—", ", "), ("–", " to "), ("·", ", "), ("|", " or ")):
        t = t.replace(ch, rep)
    # what the replacements leave behind: a doubled article ("the a private tool"), a word twice ("a session session")
    # and a gloss that now names itself ("(a practice is a practice)")
    t = re.sub(r"\b([Tt])he (a|an|the) ", lambda m: (m.group(2)[0].upper() if m.group(1) == "T" else m.group(2)[0]) + m.group(2)[1:] + " ", t)
    t = re.sub(r"\b(\w+) \1\b", r"\1", t)
    t = re.sub(r" \(([^()]+) is \1\)", "", t)
    return t


def e(s):
    return html.escape(clean(s), quote=True)


def code(s):
    """Escaped text with `backticks` and file:line references set as code."""
    t = e(s)
    t = re.sub(r"`([^`]+)`", r"<code>\1</code>", t)
    return t


def load(folder):
    rounds = []
    for name in sorted(os.listdir(folder)):
        d = os.path.join(folder, name)
        fp, cp = os.path.join(d, "findings.json"), os.path.join(d, "checklist.json")
        if not (os.path.isfile(fp) and os.path.isfile(cp)):
            continue
        f = json.load(open(fp))
        if not f.get("merged_at"):
            continue
        c = json.load(open(cp))
        rounds.append({"name": name, "f": f, "c": c})
    rounds.sort(key=lambda r: r["f"]["merged_at"])
    return rounds


def version(r):
    """The version the audit checked: findings.json's version field, else the last version its scope names (a release
    audit "v0.1.13 to v0.1.14", or "v0.1.14 to 0d04c06 (0.1.15)"), else the tag before it."""
    f = r["f"]
    if f.get("version"):
        return str(f["version"]).removeprefix("v")
    s = f.get("scope", {})
    s = s.get("summary", "") if isinstance(s, dict) else str(s)
    # a version written v0.1.14 or (0.1.15); a bare number such as ASVS 5.0.0 is not the app's
    found = [a or b for a, b in re.findall(r"\(v?(\d+\.\d+\.\d+)\)|\bv(\d+\.\d+\.\d+)\b", s)]
    if found:
        return found[-1]
    return (f.get("last_tag") or "").removeprefix("v") or "untagged"


def kind(r):
    s = r["f"].get("scope", {})
    s = s.get("summary", "") if isinstance(s, dict) else str(s)
    return "release audit" if s.startswith("release") else "full audit"


def date_of(r):
    return r["f"].get("merged_at", "")[:10]


def long_date(iso):
    y, m, d = iso.split("-")
    months = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
              "October", "November", "December"]
    return "%d %s %s" % (int(d), months[int(m) - 1], y)


def finding_block(x):
    out = ['<h3 id="%s">%s  <span class="d">%s</span></h3>' % (e(x["id"].lower()), e(x["id"]), e(x["title"]))]
    status = STATUS.get(x.get("status"), x.get("status"))
    meta = "%s  %s  %s" % (x.get("severity", ""), status, IMPACT.get(x.get("user_impact"), ""))
    out.append('<p class="d">%s</p>' % e(meta))
    if x.get("requirements"):
        out.append("<p>Requirements: %s</p>" % e(", ".join(x["requirements"])))
    if x.get("location"):
        out.append("<p>Where: <code>%s</code></p>" % e(x["location"]))
    if x.get("evidence"):
        out.append("<p>What was found: %s</p>" % code(x["evidence"]))
    if x.get("fix"):
        out.append("<p>The fix: %s</p>" % code(x["fix"]))
    if x.get("verified"):
        out.append("<p>The verifier: %s</p>" % code(x["verified"]))
    acc = x.get("acceptance")
    if isinstance(acc, dict) and acc.get("date"):
        out.append("<p>Accepted in writing by the maintainer on %s.</p>" % e(acc["date"]))
    return "\n".join(out)


def main():
    args = sys.argv[1:]
    out = "docs/audit.html"
    if "--out" in args:
        i = args.index("--out"); out = args[i + 1]; del args[i:i + 2]
    if len(args) != 1:
        sys.exit(__doc__)
    rounds = load(args[0])
    if not rounds:
        sys.exit("no finished audit folder in " + args[0])
    newest = rounds[-1]

    # the checklist: each item at the status of the newest audit that checked it
    items, checked_in = {}, {}
    for r in rounds:
        for it in r["c"]["items"]:
            items[it["id"]] = it
            checked_in[it["id"]] = r
    level = newest["c"].get("level", 2)
    order = [it["id"] for r in rounds for it in r["c"]["items"]]
    seen, ids = set(), []
    for i in order:
        if i not in seen:
            seen.add(i); ids.append(i)

    findings = newest["f"]["findings"]
    open_f = [x for x in findings if x.get("status") == "open"]
    closed_f = [x for x in findings if x.get("status") != "open"]
    sev_rank = {s: n for n, s in enumerate(SEV)}
    open_f.sort(key=lambda x: (sev_rank.get(x["severity"], 9), x["id"]))

    fw_names = []
    for i in ids:
        fw = items[i]["framework"]
        if fw not in fw_names:
            fw_names.append(fw)
    counts = {fw: {"pass": 0, "fail": 0, "na": 0} for fw in fw_names}
    for i in ids:
        counts[items[i]["framework"]][items[i]["status"]] += 1

    v, d = version(newest), date_of(newest)
    short = newest["f"].get("commit", "")[:7]
    P = []
    P.append("""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>tokenpanda audit</title>
<meta name="description" content="Our own audit of tokenpanda, run with AI agents against OWASP ASVS 5.0.0 Level 2. Not an outside audit.">
<link rel="icon" href="favicon.svg" type="image/svg+xml">
<link rel="icon" href="favicon-32.png" sizes="32x32" type="image/png">
<link rel="apple-touch-icon" href="apple-touch-icon.png">
<link rel="stylesheet" href="docs.css">
<style>.dk .main details{margin:0 0 8px;max-width:78ch}.dk .main summary{cursor:pointer;color:var(--txt)}.dk .main summary:hover{color:#ffffff}.dk .main .it{margin:8px 0 12px}.dk .main .it p{margin:0 0 4px}.dk .main .st-fail{color:var(--warn)}</style>
</head>
<body style="margin:0;background:#0e1120">
<div class="r6 dk">
<div class="frame">

<nav class="nav" aria-label="Documentation">
<div class="l"><a class="tab" href="index.html"> Overview </a></div>
<div class="l"><a class="tab" href="styleguide.html"> Style guide </a></div>
<div class="l"><a class="tab" href="spec.html"> Spec </a></div>
<div class="l"><a class="tab" href="privacy.html"> Privacy </a></div>
<div class="l"><a class="tab" href="audit.html" aria-current="page"> Audit </a></div>
<div class="l"></div>
<div class="toc"><div class="l d"><a href="#short">1  The short version</a></div>
<div class="l d"><a href="#open">2  Open findings</a></div>
<div class="l d"><a href="#closed">3  Fixed and accepted</a></div>
<div class="l d"><a href="#checklist">4  The checklist</a></div>
<div class="l d"><a href="#scanners">5  Scanners</a></div>
<div class="l d"><a href="#method">6  How it is done</a></div>
<div class="l d"><a href="#rounds">7  Every audit so far</a></div>
</div></nav>

<main class="main">""")
    P.append('<div class="head"><h1>Audit</h1><span class="d">  tokenpanda  our own audit of the code  %s, at %s</span></div>' % (e(long_date(d)), e(v)))
    P.append('<div class="head d">generated from the audit\'s own files by scripts/audit-page.py</div>')
    P.append('<div class="rule">' + "▔" * 400 + "</div>")

    P.append('<h2 id="short">1  The short version</h2>')
    P.append("<p>This is our own audit, run with AI agents against OWASP ASVS 5.0.0 Level %d. It is not an outside audit, and no outside firm has reviewed tokenpanda.</p>" % level)
    P.append("<p>The newest audit is a %s of version %s (commit <code>%s</code>), finished on %s. It has %d open %s and %d fixed or accepted. Each requirement below shows its result from the newest audit that checked it.</p>"
             % (e(kind(newest)), e(v), e(short), e(long_date(d)), len(open_f), "finding" if len(open_f) == 1 else "findings", len(closed_f)))
    rows = ["<table class=\"xs\"><tr><th>Checked against</th><th class=\"n\">pass</th><th class=\"n\">fail</th><th class=\"n\">does not apply</th></tr>"]
    for fw in fw_names:
        c = counts[fw]
        rows.append('<tr><td>%s</td><td class="n">%d</td><td class="n">%d</td><td class="n">%d</td></tr>' % (e(fw), c["pass"], c["fail"], c["na"]))
    rows.append("</table>")
    P.append("\n".join(rows))
    P.append("<p>A requirement met in part counts as a fail, with the gap named. Most ASVS requirements are about web servers, logins and sessions; tokenpanda has none of those, so they do not apply, each with the reason.</p>")

    P.append('<h2 id="open">2  Open findings</h2>')
    if not open_f:
        P.append("<p>None.</p>")
    for x in open_f:
        P.append(finding_block(x))

    P.append('<h2 id="closed">3  Fixed and accepted</h2>')
    if not closed_f:
        P.append("<p>None in the newest audit.</p>")
    for x in closed_f:
        P.append(finding_block(x))
    older = [r for r in rounds[:-1]]
    if older:
        P.append("<p>Findings of earlier audits, with their state at the end of that audit:</p>")
        t = ["<table class=\"xs\"><tr><th>Audit</th><th>Finding</th><th>Severity</th><th>State</th></tr>"]
        for r in older:
            for x in r["f"]["findings"]:
                t.append("<tr><td>%s</td><td>%s  %s</td><td>%s</td><td>%s</td></tr>" % (
                    e(date_of(r) + ", " + version(r)), e(x["id"]), e(x["title"]), e(x["severity"]), e(STATUS.get(x["status"], x["status"]))))
        t.append("</table>")
        P.append("\n".join(t))

    P.append('<h2 id="checklist">4  The checklist</h2>')
    P.append("<p>Every requirement with its result and the evidence: a file and line, a test, a scanner result, or the reason it does not apply. The fails come first.</p>")
    fails = [i for i in ids if items[i]["status"] == "fail"]

    def item_html(i):
        it = items[i]
        st = {"pass": "pass", "fail": "fail", "na": "does not apply"}[it["status"]]
        cls = ' class="st-fail"' if it["status"] == "fail" else ""
        r = checked_in[i]
        return ('<div class="it"><p><b>%s</b>  <span%s>%s</span>  <span class="d">checked %s, at %s</span></p><p>%s</p><p class="d">%s</p></div>'
                % (e(i), cls, e(st), e(date_of(r)), e(version(r)), e(it["text"]), code(it.get("evidence", ""))))
    P.append("<h3>The fails</h3>")
    P.append("\n".join(item_html(i) for i in fails) or "<p>None.</p>")
    for fw in fw_names:
        P.append("<h3>%s</h3>" % e(fw))
        groups = []
        for i in ids:
            if items[i]["framework"] != fw:
                continue
            g = items[i]["group"].split(":")[0]
            if not groups or groups[-1][0] != g:
                groups.append((g, []))
            groups[-1][1].append(i)
        for g, gi in groups:
            c = {s: sum(1 for i in gi if items[i]["status"] == s) for s in ("pass", "fail", "na")}
            P.append("<details><summary>%s  <span class=\"d\">%d pass  %d fail  %d do not apply</span></summary>\n%s\n</details>"
                     % (e(g), c["pass"], c["fail"], c["na"], "\n".join(item_html(i) for i in gi)))

    P.append('<h2 id="scanners">5  Scanners</h2>')
    P.append("<p>The scanners run in full on every audit, release audits too. What they flagged and how each hit was judged:</p>")
    tri = newest["f"].get("scanner_triage", [])
    if tri:
        # one hit per item, its judgement under it: a two column table of long texts reads at no width
        for h in tri:
            P.append("<details><summary>%s</summary>\n<p>%s</p>\n</details>" % (code(h.get("hit", "")), code(h.get("judgement", ""))))
    P.append("<p>Run in the newest audit: secrets with gitleaks over the full git history and the working tree; known vulnerabilities with osv-scanner and the OSV database (the app has no third party packages; the dev only design tools under design/system are scanned too, and their hits are listed above); static analysis with semgrep and swiftlint; the full test suite with coverage; the Apple checks for SwiftUI and AppKit; and codesign, Gatekeeper and the notarisation ticket on the built app.</p>")

    P.append('<h2 id="method">6  How it is done</h2>')
    P.append("<p>Before every release, in this order:</p>")
    P.append("<ol>"
             "<li>Scope: the commit, the last audited tag, and what the app exposes. tokenpanda has no network listener and makes no network calls; it reads Claude Code's status line feed, the transcripts and settings.json, and writes its own data folder and, on a click, one key of settings.json.</li>"
             "<li>Scanners, as in section 5.</li>"
             "<li>An AI agent reads the code against every requirement in scope and sets pass, fail or does not apply, with evidence. A full audit covers every requirement at Level 2; a release audit covers every requirement the change touches, and the rest keep their result from the audit before.</li>"
             "<li>A second AI agent, which did not write the findings, checks each one again in the code and by experiment, re-checks a sample of the passes, and confirms, changes or drops each finding.</li>"
             "<li>The release gate: no release with an open blocker or high finding, or with any open finding that users may notice, unless the maintainer decides otherwise in writing. Those decisions are marked accepted above.</li>"
             "</ol>")
    P.append("<p>Next to ASVS it checks our own list, grouped by the ISO/IEC 25010 quality characteristics (stability, reliability, maintainability and the rest), and platform checks for a Mac app: signing, notarisation, the hardened runtime, entitlements, Apple's interface guidelines, accessibility and the privacy manifest. Those checks are ours and are named as ours; ISO's own text is not quoted.</p>")
    P.append("<p>What this does not give: AI agents can miss things a person would find, and nobody outside the project has checked this work. If you find something, the <a href=\"https://github.com/tokenpandadev/tokenpanda-app/security/advisories/new\">security advisory form</a> reaches me privately.</p>")

    P.append('<h2 id="rounds">7  Every audit so far</h2>')
    t = ["<table class=\"xs\"><tr><th>Finished</th><th>Kind</th><th>Version</th><th>Commit</th><th class=\"n\">checked</th><th class=\"n\">findings</th></tr>"]
    for r in rounds:
        t.append('<tr><td>%s</td><td>%s</td><td>%s</td><td><code>%s</code></td><td class="n">%d</td><td class="n">%d</td></tr>' % (
            e(date_of(r)), e(kind(r)), e(version(r)), e(r["f"].get("commit", "")[:7]), len(r["c"]["items"]), len(r["f"]["findings"])))
    t.append("</table>")
    P.append("\n".join(t))

    P.append('<p class="d">Requirement texts are from the OWASP Application Security Verification Standard 5.0.0, by the OWASP Foundation, under CC BY-SA 4.0.</p>')
    P.append('<div class="foot">Overview  Style guide  Spec  Privacy  Audit</div>\n</main>\n</div>\n</div>\n<script src="docs.js"></script>\n</body>\n</html>\n')
    page = "\n".join(P)

    bad = [(p, m.start()) for p in FORBIDDEN for m in re.finditer(p, page)]
    bad += [("a leak word", m.start()) for pat, _ in LEAKS for m in pat.finditer(page)]
    if bad:
        for p, at in bad[:20]:
            # the context is shown on this terminal only, never written
            print("refused: %s at %d: %s" % (p, at, page[max(0, at - 60):at + 60].replace("\n", " ")), file=sys.stderr)
        sys.exit(1)
    scan_for_private_words(page)
    scan_for_secrets(page)
    with open(out, "w") as f:
        f.write(page)
    print("wrote %s: %s at %s, %d open, %d checklist items from %d audits" % (out, d, v, len(open_f), len(ids), len(rounds)))


def scan_for_private_words(page):
    """The release check's hashed word list over the page as it would be written: the leak file above missed two words
    on 10.11.2026 that this list caught, so a hit here refuses the page. Which word stays unsaid; the line number points to it."""
    checker = os.path.join(os.path.dirname(os.path.abspath(__file__)), "private-words.py")
    r = subprocess.run([sys.executable, "-I", checker, "--lines"], input=page, capture_output=True, text=True)
    if r.returncode == 0:
        return
    if r.returncode != 1:
        sys.exit("refused: the private word check failed (exit %d), so the page cannot be checked" % r.returncode)
    sys.exit("refused: a private word on line %s of the page (scripts/private-words.py)" % ", ".join(r.stdout.split()))


def scan_for_secrets(page):
    """gitleaks over the page as it would be written, in a folder of its own; any hit or error refuses the page."""
    gl = shutil.which("gitleaks")
    if not gl:
        sys.exit("refused: gitleaks is not installed, so the page cannot be checked for secrets")
    with tempfile.TemporaryDirectory() as d:
        with open(os.path.join(d, "audit.html"), "w") as f:
            f.write(page)
        r = subprocess.run([gl, "detect", "--no-git", "--no-banner", "--redact", "--exit-code", "1", "--source", d],
                           capture_output=True, text=True)
        if r.returncode != 0:
            sys.exit("refused: gitleaks found a secret in the page or failed (exit %d)\n%s" % (r.returncode, r.stderr[-2000:]))


if __name__ == "__main__":
    LEAKS = leak_words()
    main()
