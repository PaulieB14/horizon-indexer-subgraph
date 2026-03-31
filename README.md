# Graph Horizon Indexer Performance

Indexes Graph Protocol Horizon staking events on Arbitrum — operator-to-indexer mappings, allocation lifecycle, per-allocation rewards and query fees, delegation tracking, with hourly and daily timeseries aggregations.


## Contracts Indexed

| Contract | Address | Events |
|----------|---------|--------|
| HorizonStaking | `0x00669A4CF01450B64E8A2A20E9b1FCB71E61eF03` | `OperatorSet` |
| SubgraphService | `0xb2Bb92d0DE618878E438b55D5846cfecD9301105` | `AllocationCreated`, `AllocationClosed`, `AllocationResized`, `IndexingRewardsCollected`, `QueryFeesCollected` |
| StakingExtension | `0x3bE385576d7C282070Ad91BF94366de9f9ba3571` | `StakeDelegated`, `StakeDelegatedLocked`, `StakeDelegatedWithdrawn` |

## Example Queries

### Global stats
```graphql
{
  globalStats(id: "global") {
    totalIndexers
    totalOperators
    totalAllocations
    totalActiveAllocations
    totalRewardsDistributed
    totalQueryFeesCollected
  }
}
```

### Top indexers by rewards
```graphql
{
  indexers(first: 10, orderBy: totalRewardsEarned, orderDirection: desc) {
    id
    totalRewardsEarned
    totalQueryFeesCollected
    allocationCount
    activeAllocationCount
  }
}
```

### Specific indexer with top allocations
```graphql
{
  indexer(id: "0xedca8740873152ff30a2696add66d1ab41882beb") {
    id
    totalRewardsEarned
    totalQueryFeesCollected
    activeAllocationCount
    allocations(first: 5, orderBy: rewardsEarned, orderDirection: desc) {
      subgraphDeploymentID
      tokens
      rewardsEarned
      queryFeesCollected
      status
    }
  }
}
```

### Operator-to-indexer mapping (Horizon)
```graphql
{
  operators(where: { active: true }) {
    indexer { id }
    operator
    verifier
    setAt
  }
}
```

### Look up indexer by operator address
```graphql
{
  operators(where: { operator: "0x4561ec490d00b94eadb043e4f7b12e08bc24b55d", active: true }) {
    indexer { id }
    verifier
  }
}
```

### Allocations on a specific subgraph deployment
```graphql
{
  allocations(
    where: { subgraphDeploymentID: "0x45c636b73728d75a77b84c782e2a44624a294c1414326e59f12d60e0a6e58f51", status: "Active" }
    orderBy: tokens
    orderDirection: desc
  ) {
    indexer { id }
    tokens
    rewardsEarned
    queryFeesCollected
    createdAtEpoch
  }
}
```

### Daily reward aggregation per indexer
```graphql
{
  rewardDailyAggs(interval: day, first: 7) {
    timestamp
    indexer
    totalRewards
    totalIndexerRewards
    totalDelegationRewards
    rewardCount
  }
}
```

### Hourly query fee aggregation
```graphql
{
  queryFeeDailyAggs(interval: hour, first: 24) {
    timestamp
    indexer
    totalCollected
    totalCurators
    feeCount
  }
}
```

### Daily delegation events
```graphql
{
  delegationDailyAggs(interval: day, first: 7) {
    timestamp
    indexer
    totalTokens
    eventCount
  }
}
```

### Delegation history for an indexer
```graphql
{
  delegations(where: { indexer: "0xf92f430dd8567b0d466358c79594ab58d919a6d4" }, orderBy: tokens, orderDirection: desc, first: 20) {
    delegator
    tokens
    lockedTokens
    lockedUntil
    lastUpdatedAt
  }
}
```

### Recent reward events
```graphql
{
  rewardEvents(first: 10, orderBy: timestamp, orderDirection: desc) {
    indexer { id }
    subgraphDeploymentID
    tokensRewards
    tokensIndexerRewards
    tokensDelegationRewards
    epoch
    timestamp
  }
}
```

## Best Practices Applied

- **Pruning**: `indexerHints.prune: auto`
- **@derivedFrom**: operators, allocations, delegations arrays
- **Immutable entities**: RewardEvent, QueryFeeEvent with Bytes IDs
- **No eth_calls**: pure event-based indexing
- **Timeseries & Aggregations**: hourly/daily for rewards, fees, delegations

## Latency Probe

`probe.sh` measures gateway response time and identifies which indexers served each query.

### How it works

1. **Ping the gateway N times** for a specific subgraph deployment
2. **Measure** response time (ms) and block freshness (blocks behind chain head)
3. **Recover the attestation signer** from the `graph-attestation` response header using ecrecover
4. **Look up the signer** in this subgraph's `operators` entity to identify the indexer

### Usage

```bash
# Requires: pip install web3 eth-keys

# Probe the Graph Network subgraph 10 times
./probe.sh QmT329Bej8AwSLahmgnmi6fdYkj3rorYAcCes45gDv9aJ4 10

# Probe any deployment with custom API key
./probe.sh <DEPLOYMENT_HASH> <NUM_REQUESTS> <API_KEY>
```

### Example output

```
── Step 1: Probing gateway 10 times ──

#    Latency    Behind   Attestation (r prefix)
--------------------------------------------------------------------------------------------
1    0.528s     -3       0xfe34cffb83664bc2...
2    0.295s     -1       0x74c3dc3a54853a79...
3    0.209s     0        0x2cd7957a3eaff577...

── Step 2: Recovering attestation signers ──

Recovered 10 unique signers from 10 requests

Signer                                       Reqs  Avg(s)      Min      Max   Behind
----------------------------------------------------------------------------
0x4561Ec490D00b94EADb043E4f7b12e08Bc24b55D      1    0.528    0.528    0.528       -3
0x9fF82FE1D41BC0DBa77b75e2B05b726261885761      1    0.200    0.200    0.200        0

── Step 3: Looking up signers in Horizon Indexer Performance subgraph ──

  MATCH: 0x80984fe34dae1b... -> Pinax (0xedca8740873152...)
  ????: 0x4561ec490d00b9... = not found (attestation-only signing key)
```

### How to interpret results

| Metric | What it means |
|--------|--------------|
| **Latency** | Gateway round-trip time including indexer query execution |
| **Behind** | Blocks behind chain head — lower is fresher (negative = ahead of RPC) |
| **MATCH** | Signer is a registered Horizon operator — indexer identified |
| **SELF** | Signer address IS the indexer (self-operated) |
| **????** | Attestation signing key derived per-allocation — not a registered operator |

### Why some signers don't match

Attestation signing keys are derived from the indexer's mnemonic + allocation parameters (epoch, deployment, index) using BIP39 derivation. Each allocation gets a unique signing key. These keys are NOT the same as Horizon operators — they're generated locally by the indexer-agent software.

Signers that DO match a Horizon operator are confirmed identities. Unmatched signers can still be correlated by:
- Checking which indexers have active allocations on the deployment
- Comparing allocation size with gateway selection frequency
- Using query fee revenue as a proxy for selection rate (more fees = gateway picks them more = likely better latency)

### Manual probe (without script)

```bash
# 1. Get chain head
HEAD=$(curl -s https://arb1.arbitrum.io/rpc \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | \
  python3 -c "import sys,json; print(int(json.load(sys.stdin)['result'],16))")

# 2. Query subgraph through gateway
DEPLOYMENT="QmT329Bej8AwSLahmgnmi6fdYkj3rorYAcCes45gDv9aJ4"
API_KEY="your-key"

RESULT=$(curl -s -w "\n%{time_total}" \
  "https://gateway.thegraph.com/api/${API_KEY}/deployments/id/${DEPLOYMENT}" \
  -d '{"query":"{ _meta { block { number } } }"}')

BLOCK=$(echo "$RESULT" | head -1 | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['_meta']['block']['number'])")
LATENCY=$(echo "$RESULT" | tail -1)

echo "Block: $BLOCK | Behind: $((HEAD - BLOCK)) | Response: ${LATENCY}s"

# 3. Check who's allocated (via this subgraph)
curl -s "https://api.studio.thegraph.com/query/111767/graph-horizon-indexer-performance/version/latest" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ allocations(where: {subgraphDeploymentID: \"0x45c636b73728d75a77b84c782e2a44624a294c1414326e59f12d60e0a6e58f51\", status: \"Active\"}, orderBy: tokens, orderDirection: desc, first: 10) { indexer { id } tokens rewardsEarned queryFeesCollected } }"}'
```

## Deploy

```bash
graph auth <deploy-key>
graph codegen && graph build
graph deploy graph-horizon-indexer-performance --version-label v0.0.x
```
