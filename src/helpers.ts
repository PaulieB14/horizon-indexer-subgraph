import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import { Indexer, GlobalStats } from "../generated/schema";

export let ZERO_BI = BigInt.fromI32(0);
export let ONE_BI = BigInt.fromI32(1);

export function getOrCreateIndexer(address: Bytes): Indexer {
  let indexer = Indexer.load(address);
  if (indexer == null) {
    indexer = new Indexer(address);
    indexer.totalStaked = ZERO_BI;
    indexer.totalDelegated = ZERO_BI;
    indexer.totalRewardsEarned = ZERO_BI;
    indexer.totalQueryFeesCollected = ZERO_BI;
    indexer.allocationCount = 0;
    indexer.activeAllocationCount = 0;
    indexer.registeredAt = ZERO_BI;
    indexer.url = null;
    indexer.save();

    let stats = getOrCreateGlobalStats();
    stats.totalIndexers += 1;
    stats.save();
  }
  return indexer;
}

export function getOrCreateGlobalStats(): GlobalStats {
  let stats = GlobalStats.load("global");
  if (stats == null) {
    stats = new GlobalStats("global");
    stats.totalIndexers = 0;
    stats.totalOperators = 0;
    stats.totalAllocations = 0;
    stats.totalActiveAllocations = 0;
    stats.totalRewardsDistributed = ZERO_BI;
    stats.totalQueryFeesCollected = ZERO_BI;
    stats.save();
  }
  return stats;
}
