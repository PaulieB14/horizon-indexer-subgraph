import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  AllocationCreated,
  AllocationClosed,
  AllocationResized,
  IndexingRewardsCollected,
  QueryFeesCollected,
} from "../generated/SubgraphService/SubgraphService";
import { Allocation, RewardEvent, QueryFeeEvent } from "../generated/schema";
import { getOrCreateIndexer, getOrCreateGlobalStats, ZERO_BI } from "./helpers";

export function handleAllocationCreated(event: AllocationCreated): void {
  let indexer = getOrCreateIndexer(event.params.indexer);

  let alloc = new Allocation(event.params.allocationId);
  alloc.indexer = indexer.id;
  alloc.subgraphDeploymentID = event.params.subgraphDeploymentId;
  alloc.tokens = event.params.tokens;
  alloc.createdAtEpoch = event.params.currentEpoch;
  alloc.createdAt = event.block.timestamp;
  alloc.createdTx = event.transaction.hash;
  alloc.closedAtEpoch = null;
  alloc.closedAt = null;
  alloc.closedTx = null;
  alloc.status = "Active";
  alloc.rewardsEarned = ZERO_BI;
  alloc.queryFeesCollected = ZERO_BI;
  alloc.poi = null;
  alloc.save();

  indexer.allocationCount += 1;
  indexer.activeAllocationCount += 1;
  indexer.save();

  let stats = getOrCreateGlobalStats();
  stats.totalAllocations += 1;
  stats.totalActiveAllocations += 1;
  stats.save();
}

export function handleAllocationClosed(event: AllocationClosed): void {
  let alloc = Allocation.load(event.params.allocationId);
  if (alloc != null) {
    alloc.status = "Closed";
    alloc.closedAt = event.block.timestamp;
    alloc.closedTx = event.transaction.hash;
    alloc.save();

    let indexer = getOrCreateIndexer(event.params.indexer);
    indexer.activeAllocationCount -= 1;
    indexer.save();

    let stats = getOrCreateGlobalStats();
    stats.totalActiveAllocations -= 1;
    stats.save();
  }
}

export function handleAllocationResized(event: AllocationResized): void {
  let alloc = Allocation.load(event.params.allocationId);
  if (alloc != null) {
    alloc.tokens = event.params.newTokens;
    alloc.save();
  }
}

export function handleIndexingRewardsCollected(event: IndexingRewardsCollected): void {
  let id = event.transaction.hash.concatI32(event.logIndex.toI32());
  let reward = new RewardEvent(id);
  reward.indexer = event.params.indexer;
  reward.allocationID = event.params.allocationId;
  reward.subgraphDeploymentID = event.params.subgraphDeploymentId;
  reward.tokensRewards = event.params.tokensRewards;
  reward.tokensIndexerRewards = event.params.tokensIndexerRewards;
  reward.tokensDelegationRewards = event.params.tokensDelegationRewards;
  reward.epoch = event.params.currentEpoch;
  reward.timestamp = event.block.timestamp;
  reward.tx = event.transaction.hash;
  reward.save();

  let alloc = Allocation.load(event.params.allocationId);
  if (alloc != null) {
    alloc.rewardsEarned = alloc.rewardsEarned.plus(event.params.tokensRewards);
    alloc.save();
  }

  let indexer = getOrCreateIndexer(event.params.indexer);
  indexer.totalRewardsEarned = indexer.totalRewardsEarned.plus(event.params.tokensRewards);
  indexer.save();

  let stats = getOrCreateGlobalStats();
  stats.totalRewardsDistributed = stats.totalRewardsDistributed.plus(event.params.tokensRewards);
  stats.save();
}

export function handleQueryFeesCollected(event: QueryFeesCollected): void {
  let id = event.transaction.hash.concatI32(event.logIndex.toI32());
  let fee = new QueryFeeEvent(id);
  fee.indexer = event.params.serviceProvider;
  fee.allocationID = event.params.allocationId;
  fee.subgraphDeploymentID = event.params.subgraphDeploymentId;
  fee.tokensCollected = event.params.tokensCollected;
  fee.tokensCurators = event.params.tokensCurators;
  fee.timestamp = event.block.timestamp;
  fee.tx = event.transaction.hash;
  fee.save();

  let alloc = Allocation.load(event.params.allocationId);
  if (alloc != null) {
    alloc.queryFeesCollected = alloc.queryFeesCollected.plus(event.params.tokensCollected);
    alloc.save();
  }

  let indexer = getOrCreateIndexer(event.params.serviceProvider);
  indexer.totalQueryFeesCollected = indexer.totalQueryFeesCollected.plus(event.params.tokensCollected);
  indexer.save();

  let stats = getOrCreateGlobalStats();
  stats.totalQueryFeesCollected = stats.totalQueryFeesCollected.plus(event.params.tokensCollected);
  stats.save();
}
