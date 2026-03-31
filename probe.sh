#!/bin/bash
# ============================================================================
# Graph Indexer Latency Probe
#
# 1. Pings a subgraph deployment through the gateway N times
# 2. Measures response time and block freshness per request
# 3. Recovers the attestation signer from each response
# 4. Looks up signers in the Horizon Indexer Performance subgraph
#
# Usage: ./probe.sh <DEPLOYMENT_HASH> [NUM_REQUESTS] [API_KEY]
# Example: ./probe.sh QmT329Bej8AwSLahmgnmi6fdYkj3rorYAcCes45gDv9aJ4 10
# ============================================================================

DEPLOYMENT="${1:-QmT329Bej8AwSLahmgnmi6fdYkj3rorYAcCes45gDv9aJ4}"
NUM_REQUESTS="${2:-10}"
API_KEY="${3:-7006f39fbab470711f44a5195b4d97c0}"
SUBGRAPH_URL="https://api.studio.thegraph.com/query/111767/graph-horizon-indexer-performance/version/latest"
GATEWAY="https://gateway.thegraph.com/api/${API_KEY}/deployments/id/${DEPLOYMENT}"

echo "============================================"
echo "Graph Indexer Latency Probe"
echo "============================================"
echo "Deployment: ${DEPLOYMENT}"
echo "Requests:   ${NUM_REQUESTS}"
echo "Gateway:    ${GATEWAY}"
echo ""

# Get chain head
ARB_HEAD=$(curl -s -X POST https://arb1.arbitrum.io/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | \
  python3 -c "import sys,json; print(int(json.load(sys.stdin)['result'],16))" 2>/dev/null)
echo "Arbitrum head: ${ARB_HEAD}"
echo ""

# ── Step 1: Probe the gateway ──
echo "── Step 1: Probing gateway ${NUM_REQUESTS} times ──"
echo ""
printf "%-4s %-10s %-8s %-68s\n" "#" "Latency" "Behind" "Attestation (r prefix)"
echo "--------------------------------------------------------------------------------------------"

RESULTS_FILE=$(mktemp)

for i in $(seq 1 $NUM_REQUESTS); do
  RESPONSE=$(curl -s -w "\n%{time_total}" \
    -X POST "${GATEWAY}" \
    -H "Content-Type: application/json" \
    -D /tmp/probe_headers_${i}.txt \
    -d '{"query": "{ _meta { block { number } } }"}' 2>/dev/null)

  LATENCY=$(echo "$RESPONSE" | tail -1)
  BODY=$(echo "$RESPONSE" | head -1)
  BLOCK=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('_meta',{}).get('block',{}).get('number','ERROR'))" 2>/dev/null)

  # Extract attestation
  ATT=$(grep -i "graph-attestation" /tmp/probe_headers_${i}.txt 2>/dev/null | sed 's/graph-attestation: //')
  R_VAL=$(echo "$ATT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('r','?')[:18])" 2>/dev/null || echo "?")

  if [ "$BLOCK" != "ERROR" ]; then
    BEHIND=$((ARB_HEAD - BLOCK))
    printf "%-4s %-10s %-8s %-68s\n" "$i" "${LATENCY}s" "${BEHIND}" "${R_VAL}..."
    echo "${i}|${LATENCY}|${BEHIND}|${ATT}" >> "$RESULTS_FILE"
  else
    printf "%-4s %-10s %-8s %-68s\n" "$i" "${LATENCY}s" "FAIL" "—"
  fi

  sleep 0.3
done

echo ""

# ── Step 2: Recover signers ──
echo "── Step 2: Recovering attestation signers ──"
echo ""

python3 << 'PYEOF'
import json, sys, os

try:
    from eth_keys import keys
    from web3 import Web3
except ImportError:
    print("  Install: pip install web3 eth-keys")
    sys.exit(1)

w3 = Web3()
results_file = os.environ.get("RESULTS_FILE", "/tmp/probe_results.txt")

# Read results
results = []
with open(sys.argv[1] if len(sys.argv) > 1 else results_file) as f:
    for line in f:
        parts = line.strip().split("|", 3)
        if len(parts) == 4:
            results.append({
                "num": parts[0],
                "latency": float(parts[1]),
                "behind": int(parts[2]),
                "attestation": parts[3]
            })

REQ_CID = None
DEPLOY_ID = None
signers = {}

for r in results:
    try:
        att = json.loads(r["attestation"])
        if REQ_CID is None:
            REQ_CID = att["requestCID"]
            DEPLOY_ID = att["subgraphDeploymentID"]

        msg_bytes = bytes.fromhex(REQ_CID[2:]) + bytes.fromhex(att["responseCID"][2:]) + bytes.fromhex(DEPLOY_ID[2:])
        msg_hash = w3.keccak(msg_bytes)

        sig = keys.Signature(vrs=(att["v"], int(att["r"], 16), int(att["s"], 16)))
        pubkey = sig.recover_public_key_from_msg_hash(msg_hash)
        addr = pubkey.to_checksum_address().lower()

        if addr not in signers:
            signers[addr] = {"latencies": [], "behinds": []}
        signers[addr]["latencies"].append(r["latency"])
        signers[addr]["behinds"].append(r["behind"])
    except Exception as e:
        pass

print(f"Recovered {len(signers)} unique signers from {len(results)} requests")
print()
print(f"{'Signer':<44} {'Reqs':>4} {'Avg(s)':>8} {'Min':>8} {'Max':>8} {'Avg Behind':>10}")
print("-" * 80)

for addr, data in sorted(signers.items(), key=lambda x: -len(x[1]["latencies"])):
    lats = data["latencies"]
    behs = data["behinds"]
    avg_lat = sum(lats) / len(lats)
    avg_beh = sum(behs) / len(behs)
    print(f"{addr:<44} {len(lats):>4} {avg_lat:>8.3f} {min(lats):>8.3f} {max(lats):>8.3f} {avg_beh:>10.0f}")

# Save signers for step 3
with open("/tmp/probe_signers.json", "w") as f:
    json.dump(list(signers.keys()), f)

PYEOF
python3 -c "
import json, sys, os
try:
    from eth_keys import keys
    from web3 import Web3
except:
    print('  Need: pip install web3 eth-keys'); sys.exit(1)

w3 = Web3()
results = []
with open('$RESULTS_FILE') as f:
    for line in f:
        parts = line.strip().split('|', 3)
        if len(parts) == 4:
            results.append({'num': parts[0], 'latency': float(parts[1]), 'behind': int(parts[2]), 'att': parts[3]})

REQ_CID = DEPLOY_ID = None
signers = {}
for r in results:
    try:
        att = json.loads(r['att'])
        if not REQ_CID: REQ_CID = att['requestCID']; DEPLOY_ID = att['subgraphDeploymentID']
        msg = bytes.fromhex(REQ_CID[2:]) + bytes.fromhex(att['responseCID'][2:]) + bytes.fromhex(DEPLOY_ID[2:])
        msg_hash = w3.keccak(msg)
        sig = keys.Signature(vrs=(att['v'], int(att['r'], 16), int(att['s'], 16)))
        addr = sig.recover_public_key_from_msg_hash(msg_hash).to_checksum_address().lower()
        if addr not in signers: signers[addr] = {'lats': [], 'behs': []}
        signers[addr]['lats'].append(r['latency'])
        signers[addr]['behs'].append(r['behind'])
    except: pass

print(f'Recovered {len(signers)} unique signers from {len(results)} requests\n')
print(f'{\"Signer\":<44} {\"Reqs\":>4} {\"Avg(s)\":>8} {\"Min\":>8} {\"Max\":>8} {\"Behind\":>8}')
print('-' * 76)
for addr, d in sorted(signers.items(), key=lambda x: -len(x[1]['lats'])):
    l = d['lats']; b = d['behs']
    print(f'{addr:<44} {len(l):>4} {sum(l)/len(l):>8.3f} {min(l):>8.3f} {max(l):>8.3f} {sum(b)/len(b):>8.0f}')
json.dump(list(signers.keys()), open('/tmp/probe_signers.json','w'))
"

echo ""

# ── Step 3: Look up in Horizon subgraph ──
echo "── Step 3: Looking up signers in Horizon Indexer Performance subgraph ──"
echo ""

python3 << PYLOOKUP
import json, sys
try:
    import httpx
except:
    import urllib.request
    class httpx:
        @staticmethod
        def post(url, json=None, **kw):
            import urllib.request, json as j
            req = urllib.request.Request(url, data=j.dumps(json).encode(), headers={"Content-Type": "application/json"})
            resp = urllib.request.urlopen(req)
            class R:
                def json(self): return j.loads(resp.read())
            return R()

signers = json.load(open("/tmp/probe_signers.json"))
url = "${SUBGRAPH_URL}"

NAMES = {
    "0xedca8740873152ff30a2696add66d1ab41882beb": "Pinax",
    "0xf92f430dd8567b0d466358c79594ab58d919a6d4": "Ellipfra",
    "0x326c584e0f0eab1f1f83c93cc6ae1acc0feba0bc": "Graphtronauts",
    "0x35917c0eb91d2e69e0dba93bd73b65e26c5c2dde": "StreamingFast",
    "0x2f09092aacd80163d56b42e7ec0ee57f637d5cee": "P2P",
    "0x38f412c8d6346ab66f3e26b4406f8b6713d34eac": "GraphOps",
}

# Check if any signer is a registered Horizon operator
for signer in signers:
    query = '{ operators(where: {operator: "' + signer + '", active: true}) { indexer { id } verifier } }'
    try:
        r = httpx.post(url, json={"query": query})
        data = r.json()
        ops = data.get("data", {}).get("operators", [])
        if ops:
            for o in ops:
                idx = o["indexer"]["id"]
                name = NAMES.get(idx, idx[:20] + "...")
                print(f"  MATCH: {signer[:16]}... -> {name} ({idx})")
        else:
            # Check if signer IS an indexer
            query2 = '{ indexer(id: "' + signer + '") { id activeAllocationCount totalRewardsEarned } }'
            r2 = httpx.post(url, json={"query": query2})
            idx = r2.json().get("data", {}).get("indexer")
            if idx:
                name = NAMES.get(signer, signer[:20] + "...")
                print(f"  SELF:  {signer[:16]}... = {name} (self-operated)")
            else:
                print(f"  ????:  {signer[:16]}... = not found (attestation-only signing key)")
    except Exception as e:
        print(f"  ERROR: {signer[:16]}... - {e}")

print()
print("Note: Attestation signing keys are derived per-allocation from the indexer's")
print("mnemonic. They may not match Horizon operators if the indexer uses a separate")
print("signing configuration. Operators that DO match are confirmed indexer identities.")
PYLOOKUP

# Cleanup
rm -f "$RESULTS_FILE" /tmp/probe_headers_*.txt /tmp/probe_signers.json

echo ""
echo "============================================"
echo "Done. To see which indexers are allocated to"
echo "this deployment, query the subgraph:"
echo ""
echo "  { allocations(where: {"
echo "      subgraphDeploymentID: \"0x...\","
echo "      status: \"Active\""
echo "    }, orderBy: tokens, orderDirection: desc) {"
echo "      indexer { id } tokens rewardsEarned"
echo "    }"
echo "  }"
echo "============================================"
