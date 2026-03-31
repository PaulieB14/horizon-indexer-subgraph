# Graph Horizon Indexer Performance

Indexes Graph Protocol Horizon staking events on Arbitrum — operator-to-indexer mappings, allocation lifecycle, per-allocation rewards and query fees, delegation tracking, with hourly and daily timeseries aggregations.

**Studio:** [graph-indexer-performance](https://thegraph.com/studio/subgraph/graph-indexer-performance)

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
  rewardDailyAggs(first: 7, orderBy: timestamp, orderDirection: desc) {
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
  queryFeeDailyAggs(first: 24, orderBy: timestamp, orderDirection: desc) {
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
  delegationDailyAggs(first: 7, orderBy: timestamp, orderDirection: desc) {
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

## Deploy

```bash
graph auth <deploy-key>
graph codegen && graph build
graph deploy graph-indexer-performance --version-label v0.0.x
```
