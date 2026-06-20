#!/bin/bash
# export_dashboard_data.sh
# Runs on the SIEM VM. Queries Elasticsearch (read-only) and writes a single
# sanitized JSON file safe for public consumption. No raw logs, no internal
# IPs, no system indices -- just aggregate counts.
#
# NOTE: the per-country MITRE ATT&CK technique breakdown in "countries"
# requires that your Logstash/Cowrie pipeline tags events with a technique
# ID (e.g. via a translate filter mapping event types -> ATT&CK IDs). If you
# haven't set that mapping up yet, edit the "techniques" section below or
# leave it as a static/manual mapping you update by hand periodically --
# the dashboard will render whatever is in the JSON either way.
#
# Intended to run nightly via cron, then the output file gets pushed to the
# GitHub repo backing the public dashboard.

set -e

ES_HOST="https://localhost:9200"
ES_USER="elastic"
ES_PASS="sans101"
OUT_FILE="$HOME/dashboard-data/honeypot_stats.json"

mkdir -p "$(dirname "$OUT_FILE")"

TOTAL_EVENTS=$(curl -s -k -u "$ES_USER:$ES_PASS" \
  "$ES_HOST/cowrie*/_count" \
  -H "Content-Type: application/json" \
  -d '{"query":{"range":{"@timestamp":{"gte":"now-30d"}}}}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))")

UNIQUE_IPS=$(curl -s -k -u "$ES_USER:$ES_PASS" \
  "$ES_HOST/cowrie*/_search" \
  -H "Content-Type: application/json" \
  -d '{
    "size":0,
    "query":{"range":{"@timestamp":{"gte":"now-30d"}}},
    "aggs":{"unique_ips":{"cardinality":{"field":"related.ip"}}}
  }' | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['aggregations']['unique_ips']['value'])")

# Per-country counts + unique IPs (last 30 days)
COUNTRIES_RAW=$(curl -s -k -u "$ES_USER:$ES_PASS" \
  "$ES_HOST/cowrie*/_search" \
  -H "Content-Type: application/json" \
  -d '{
    "size":0,
    "query":{"range":{"@timestamp":{"gte":"now-30d"}}},
    "aggs":{
      "countries":{
        "terms":{"field":"source.geo.country_name","size":15},
        "aggs":{
          "unique_ips":{"cardinality":{"field":"source.ip"}},
          "country_code":{"terms":{"field":"source.geo.country_iso_code","size":1}}
        }
      }
    }
  }')

ACTIVITY_TIMELINE=$(curl -s -k -u "$ES_USER:$ES_PASS" \
  "$ES_HOST/cowrie*/_search" \
  -H "Content-Type: application/json" \
  -d '{
    "size":0,
    "query":{"range":{"@timestamp":{"gte":"now-7d"}}},
    "aggs":{"over_time":{"date_histogram":{"field":"@timestamp","fixed_interval":"3h"}}}
  }' | python3 -c "
import sys, json
d = json.load(sys.stdin)
buckets = d.get('aggregations', {}).get('over_time', {}).get('buckets', [])
print(json.dumps([{'time': b['key_as_string'], 'count': b['doc_count']} for b in buckets]))
")

TOP_PORTS=$(curl -s -k -u "$ES_USER:$ES_PASS" \
  "$ES_HOST/cowrie*/_search" \
  -H "Content-Type: application/json" \
  -d '{
    "size":0,
    "query":{"range":{"@timestamp":{"gte":"now-30d"}}},
    "aggs":{"ports":{"terms":{"field":"destination.port","size":10}}}
  }' | python3 -c "
import sys, json
d = json.load(sys.stdin)
buckets = d.get('aggregations', {}).get('ports', {}).get('buckets', [])
print(json.dumps([{'port': b['key'], 'count': b['doc_count']} for b in buckets]))
" 2>/dev/null || echo "[]")

# Build the countries array with a placeholder technique mapping.
# Replace this logic with a real lookup once your pipeline tags ATT&CK IDs.
python3 << PYEOF
import json
from datetime import datetime, timezone

countries_raw = json.loads('''$COUNTRIES_RAW''')
buckets = countries_raw.get("aggregations", {}).get("countries", {}).get("buckets", [])

# crude heuristic placeholder: bucket by doc_count to pick a plausible technique mix.
# swap this out for a real translate-filter-based tag if/when your pipeline supports it.
def guess_techniques(count):
    return [
        {"id": "T1110", "name": "Brute Force", "count": int(count * 0.55)},
        {"id": "T1595", "name": "Active Scanning", "count": int(count * 0.30)},
        {"id": "T1190", "name": "Exploit Public-Facing Application", "count": int(count * 0.15)},
    ]

countries = []
for b in buckets:
    code_buckets = b.get("country_code", {}).get("buckets", [])
    code = code_buckets[0]["key"] if code_buckets else "??"
    countries.append({
        "country": b["key"],
        "code": code,
        "count": b["doc_count"],
        "unique_ips": b.get("unique_ips", {}).get("value", 0),
        "techniques": guess_techniques(b["doc_count"])
    })

data = {
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "total_events_30d": $TOTAL_EVENTS,
    "unique_ips_30d": $UNIQUE_IPS,
    "activity_timeline_7d": $ACTIVITY_TIMELINE,
    "top_ports": $TOP_PORTS,
    "countries": countries
}

with open("$OUT_FILE", "w") as f:
    json.dump(data, f, indent=2)

print("Wrote $OUT_FILE")
PYEOF
