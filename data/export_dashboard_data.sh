#!/bin/bash
# export_dashboard_data.sh
# Runs on the SIEM VM. Queries Elasticsearch (read-only) and writes a single
# sanitized JSON file safe for public consumption. No raw logs, no internal
# IPs, no system indices -- just aggregate counts.
#
# Intended to run nightly via cron, then the output file gets pushed to the
# GitHub repo backing the public dashboard.

set -e

ES_HOST="https://localhost:9200"
ES_USER="elastic"
ES_PASS="sans101"
OUT_FILE="$HOME/dashboard-data/honeypot_stats.json"

mkdir -p "$(dirname "$OUT_FILE")"

# --- Total events across cowrie indices (last 30 days) ---
TOTAL_EVENTS=$(curl -s -k -u "$ES_USER:$ES_PASS" \
  "$ES_HOST/cowrie*/_count" \
  -H "Content-Type: application/json" \
  -d '{"query":{"range":{"@timestamp":{"gte":"now-30d"}}}}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))")

# --- Unique attacker IPs (last 30 days) ---
UNIQUE_IPS=$(curl -s -k -u "$ES_USER:$ES_PASS" \
  "$ES_HOST/cowrie*/_search" \
  -H "Content-Type: application/json" \
  -d '{
    "size":0,
    "query":{"range":{"@timestamp":{"gte":"now-30d"}}},
    "aggs":{"unique_ips":{"cardinality":{"field":"related.ip"}}}
  }' | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['aggregations']['unique_ips']['value'])")

# --- Top countries (last 30 days) ---
TOP_COUNTRIES=$(curl -s -k -u "$ES_USER:$ES_PASS" \
  "$ES_HOST/cowrie*/_search" \
  -H "Content-Type: application/json" \
  -d '{
    "size":0,
    "query":{"range":{"@timestamp":{"gte":"now-30d"}}},
    "aggs":{"countries":{"terms":{"field":"source.geo.country_name","size":10}}}
  }' | python3 -c "
import sys, json
d = json.load(sys.stdin)
buckets = d.get('aggregations', {}).get('countries', {}).get('buckets', [])
print(json.dumps([{'country': b['key'], 'count': b['doc_count']} for b in buckets]))
")

# --- Activity over time, hourly buckets, last 7 days ---
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

# --- Log type split (honeypot vs iptables) ---
LOG_TYPE_SPLIT=$(curl -s -k -u "$ES_USER:$ES_PASS" \
  "$ES_HOST/cowrie*/_search" \
  -H "Content-Type: application/json" \
  -d '{
    "size":0,
    "query":{"range":{"@timestamp":{"gte":"now-30d"}}},
    "aggs":{"types":{"terms":{"field":"fileset.name","size":10}}}
  }' | python3 -c "
import sys, json
d = json.load(sys.stdin)
buckets = d.get('aggregations', {}).get('types', {}).get('buckets', [])
print(json.dumps([{'type': b['key'], 'count': b['doc_count']} for b in buckets]))
" 2>/dev/null || echo "[]")

# --- Top targeted ports (last 30 days) ---
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

# --- Assemble final JSON ---
python3 << PYEOF
import json
from datetime import datetime, timezone

data = {
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "total_events_30d": $TOTAL_EVENTS,
    "unique_ips_30d": $UNIQUE_IPS,
    "top_countries": $TOP_COUNTRIES,
    "activity_timeline_7d": $ACTIVITY_TIMELINE,
    "log_type_split": $LOG_TYPE_SPLIT,
    "top_ports": $TOP_PORTS
}

with open("$OUT_FILE", "w") as f:
    json.dump(data, f, indent=2)

print("Wrote $OUT_FILE")
PYEOF
