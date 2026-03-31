import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  StakeDelegated,
  StakeDelegatedLocked,
  StakeDelegatedWithdrawn,
} from "../generated/StakingExtension/StakingExtension";
import { Delegation } from "../generated/schema";
import { getOrCreateIndexer, ZERO_BI } from "./helpers";

function getOrCreateDelegation(indexer: Bytes, delegator: Bytes, timestamp: BigInt): Delegation {
  let id = indexer.toHexString() + "-" + delegator.toHexString();
  let delegation = Delegation.load(id);
  if (delegation == null) {
    delegation = new Delegation(id);
    delegation.indexer = indexer;
    delegation.delegator = delegator;
    delegation.tokens = ZERO_BI;
    delegation.shares = ZERO_BI;
    delegation.lockedTokens = ZERO_BI;
    delegation.lockedUntil = ZERO_BI;
    delegation.createdAt = timestamp;
    delegation.lastUpdatedAt = timestamp;
  }
  return delegation;
}

export function handleStakeDelegated(event: StakeDelegated): void {
  let indexer = getOrCreateIndexer(event.params.indexer);
  let delegation = getOrCreateDelegation(event.params.indexer, event.params.delegator, event.block.timestamp);

  delegation.tokens = delegation.tokens.plus(event.params.tokens);
  delegation.shares = delegation.shares.plus(event.params.shares);
  delegation.lastUpdatedAt = event.block.timestamp;
  delegation.save();

  indexer.totalDelegated = indexer.totalDelegated.plus(event.params.tokens);
  indexer.save();
}

export function handleStakeDelegatedLocked(event: StakeDelegatedLocked): void {
  let indexer = getOrCreateIndexer(event.params.indexer);
  let delegation = getOrCreateDelegation(event.params.indexer, event.params.delegator, event.block.timestamp);

  delegation.lockedTokens = delegation.lockedTokens.plus(event.params.tokens);
  delegation.lockedUntil = event.params.until;
  delegation.lastUpdatedAt = event.block.timestamp;
  delegation.save();
}

export function handleStakeDelegatedWithdrawn(event: StakeDelegatedWithdrawn): void {
  let indexer = getOrCreateIndexer(event.params.indexer);
  let delegation = getOrCreateDelegation(event.params.indexer, event.params.delegator, event.block.timestamp);

  delegation.tokens = delegation.tokens.minus(event.params.tokens);
  delegation.lockedTokens = ZERO_BI;
  delegation.lastUpdatedAt = event.block.timestamp;
  delegation.save();

  indexer.totalDelegated = indexer.totalDelegated.minus(event.params.tokens);
  indexer.save();
}
