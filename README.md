# ZayTech &mdash; Public Security Site

A single-page, public-safe site combining:
- Your GIAC certifications
- Live(ish) aggregate stats from your self-hosted DShield honeypot
- A country filter that cross-references MITRE ATT&CK techniques
- Your written Attack Observation log

Same security model as before: **nothing here ever talks to your home
network live.** The JSON files in `data/` are the entire interface. You
regenerate them on a schedule (or edit by hand) and push the updated files;
the page itself only ever reads static JSON over HTTPS.

## Files

```
index.html                   the whole site (HTML/CSS/JS, no build step)
data/certifications.json     your GIAC cert list
data/honeypot_stats.json     aggregate stats + per-country MITRE breakdown
data/observations.json       your written Attack Observation entries
export_dashboard_data.sh     runs ON THE SIEM VM, regenerates honeypot_stats.json
```

## Publishing on GitHub Pages

Same steps as before if you've already got the `honeypot-watch` repo &mdash;
just replace its contents with this folder's files (or make a new repo, your
call).

1. **github.com → New repository** → public, no starter README.
2. **Add file → Upload files**, drag in `index.html`.
3. **Add file → Upload files**, drag in the `data/` folder (or create each
   file individually with **Add file → Create new file**, typing the path
   like `data/certifications.json` to auto-create the folder).
4. Repo **Settings → Pages → Source: Deploy from a branch → main → / (root)
   → Save**.
5. Wait ~1 minute, refresh that same Pages screen for your live URL.

## Updating your certifications

Edit `data/certifications.json`. Each entry:
```json
{ "acronym": "GXYZ", "name": "Full Certification Name", "domain": "category" }
```
`domain` isn&rsquo;t shown on the page yet but is there if you want to group/filter
by category later.

## Updating the honeypot stats + MITRE mapping

`honeypot_stats.json`'s `countries` array is what drives both the country
filter buttons and the MITRE ATT&CK panel. Each country needs:

```json
{
  "country": "Bulgaria",
  "code": "BG",
  "count": 12554,
  "unique_ips": 412,
  "techniques": [
    { "id": "T1110", "name": "Brute Force", "count": 9800 }
  ]
}
```

**Important caveat on the MITRE mapping:** Cowrie/iptables logs don&rsquo;t
natively tag events with ATT&CK technique IDs. The included
`export_dashboard_data.sh` ships with a **placeholder heuristic** (it splits
each country's traffic into Brute Force / Active Scanning / Exploit
Public-Facing Application by a fixed percentage) so the page has something
real to show immediately. For genuinely accurate per-technique counts,
you'd want to extend your Logstash pipeline with a `translate` filter that
maps specific Cowrie event types (e.g. `cowrie.login.failed` &rarr; T1110,
`cowrie.session.file_download` &rarr; T1105) to ATT&CK IDs, then aggregate
on that field instead of guessing. Until then, feel free to hand-edit the
`techniques` arrays directly with your own judgment as you analyze sessions
for each Attack Observation &mdash; that's arguably more honest than an
automated guess anyway.

## Updating Attack Observations

Same as before &mdash; edit `data/observations.json`, add new entries to the
**top** of the array:
```json
{
  "title": "Short descriptive title",
  "date": "Month Day, Year",
  "tags": ["tag-one", "tag-two"],
  "body": ["Paragraph one.", "Paragraph two."]
}
```

## Keeping data fresh automatically

See the original automation approach: clone the repo onto your SIEM VM,
have a nightly cron job run `export_dashboard_data.sh`, copy its output into
the cloned repo's `data/honeypot_stats.json`, then `git commit && git push`.
GitHub Pages redeploys within a minute or two of any push.

```bash
git clone https://github.com/<you>/<repo>.git ~/zaytech-site
```
```bash
#!/bin/bash
~/export_dashboard_data.sh
cp ~/dashboard-data/honeypot_stats.json ~/zaytech-site/data/honeypot_stats.json
cd ~/zaytech-site
git add data/honeypot_stats.json
git commit -m "nightly stats refresh" -q
git push -q
```
```bash
crontab -e
```
```
0 2 * * * /home/zaytech/nightly_push.sh >> /home/zaytech/push.log 2>&1
```

## What's intentionally left out

- No real GIAC badge artwork is embedded &mdash; those images are SANS/GIAC's
  copyrighted property hosted on their own site. The acronym-tile design
  here is original and doesn't reproduce their graphics.
- No raw session logs, internal IPs, or hostnames anywhere in this repo.
- The export script only runs `_count`/aggregation queries against
  Elasticsearch, never raw documents or system indices.
