# Honeypot Watch &mdash; Public Dashboard

A static, public-safe dashboard showing aggregate stats from a self-hosted
DShield honeypot, plus a running log of written attack observations.

**Nothing in this repo ever talks to your home network live.** The two
JSON files in `data/` are the entire interface between your real
Elasticsearch/SIEM and this public page. You regenerate them on a schedule
and push the updated files &mdash; the page itself just reads static JSON.

## What's in here

```
index.html                   the whole dashboard (HTML/CSS/JS, no build step)
data/honeypot_stats.json     aggregate stats, regenerated nightly
data/observations.json       your written Attack Observation entries
export_dashboard_data.sh     runs ON THE SIEM VM, writes honeypot_stats.json
```

## 1. Put this on GitHub Pages

1. On github.com, click **New repository**. Name it whatever you like
   (e.g. `honeypot-watch`). Public repo, no need for a README/license yet
   since this folder already has one.
2. On your own machine (or the SIEM VM), initialize and push this folder:
   ```bash
   cd honeypot-dashboard
   git init
   git add .
   git commit -m "Initial dashboard"
   git branch -M main
   git remote add origin https://github.com/<your-username>/honeypot-watch.git
   git push -u origin main
   ```
3. In the GitHub repo, go to **Settings &rarr; Pages**.
4. Under **Source**, choose **Deploy from a branch**.
5. Set branch to **main**, folder to **/ (root)**, click **Save**.
6. GitHub gives you a URL like `https://<your-username>.github.io/honeypot-watch/`
   within a minute or two. That's it &mdash; it's live and public.

## 2. Keep the data fresh

`export_dashboard_data.sh` is meant to run **on the SIEM VM**, where it has
local access to Elasticsearch. It writes a single sanitized JSON file with
only aggregate counts &mdash; no raw logs, no internal IPs, nothing that
identifies your home network.

Edit the credentials at the top of the script if needed, then test it:
```bash
chmod +x export_dashboard_data.sh
./export_dashboard_data.sh
cat ~/dashboard-data/honeypot_stats.json
```

### Getting the file from the SIEM VM into the GitHub repo

The simplest approach: a small cron job on the SIEM VM that regenerates the
file, then a second step that copies it into a local clone of the repo and
pushes. For example, set up a one-time SSH key/deploy key for the repo, clone
it onto the SIEM VM once:

```bash
git clone https://github.com/<your-username>/honeypot-watch.git ~/honeypot-watch
```

Then a wrapper script:
```bash
#!/bin/bash
~/export_dashboard_data.sh
cp ~/dashboard-data/honeypot_stats.json ~/honeypot-watch/data/honeypot_stats.json
cd ~/honeypot-watch
git add data/honeypot_stats.json
git commit -m "nightly stats refresh" --allow-empty-message -q
git push -q
```

Add that wrapper to a nightly cron job:
```bash
crontab -e
```
```
0 2 * * * /home/zaytech/nightly_dashboard_push.sh >> /home/zaytech/dashboard_push.log 2>&1
```

GitHub Pages automatically redeploys within a minute or two of any push to
`main`, so the public page updates itself every night with no manual work
after this is set up once.

## 3. Adding new Attack Observations

Edit `data/observations.json` and add a new object to the **top** of the
array (newest first):

```json
{
  "title": "Short descriptive title",
  "date": "Month Day, Year",
  "tags": ["tag-one", "tag-two"],
  "body": [
    "First paragraph.",
    "Second paragraph.",
    "As many paragraphs as you want \u2014 each string in this array becomes its own paragraph."
  ]
}
```

Commit and push that file (from the repo on your own machine, or however
you prefer) and the public log updates immediately.

## Notes on what's intentionally left out

- No login-protected admin view, no link back to the real Kibana, no
  internal IPs or hostnames anywhere in this repo or its data files.
- The export script only ever runs `_count` and `_search` aggregation
  queries against Elasticsearch &mdash; it never touches raw documents,
  session content, or system indices.
- If you ever want to stop publishing, deleting the repo or disabling
  Pages in Settings takes the page down immediately; nothing else needs
  to change on the SIEM side.
