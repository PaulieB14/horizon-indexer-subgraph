import { Bytes } from "@graphprotocol/graph-ts";
import { OperatorSet } from "../generated/HorizonStaking/HorizonStaking";
import { Operator } from "../generated/schema";
import { getOrCreateIndexer, getOrCreateGlobalStats } from "./helpers";

export function handleOperatorSet(event: OperatorSet): void {
  let indexer = getOrCreateIndexer(event.params.serviceProvider);

  let id = event.params.serviceProvider.toHexString()
    + "-" + event.params.verifier.toHexString()
    + "-" + event.params.operator.toHexString();

  let operator = Operator.load(id);
  if (operator == null) {
    operator = new Operator(id);
    operator.indexer = indexer.id;
    operator.operator = event.params.operator;
    operator.verifier = event.params.verifier;
    operator.active = event.params.allowed;
    operator.setAt = event.block.timestamp;
    operator.setTx = event.transaction.hash;
    operator.save();

    if (event.params.allowed) {
      let stats = getOrCreateGlobalStats();
      stats.totalOperators += 1;
      stats.save();
    }
  } else {
    let wasActive = operator.active;
    operator.active = event.params.allowed;
    operator.setAt = event.block.timestamp;
    operator.setTx = event.transaction.hash;
    operator.save();

    let stats = getOrCreateGlobalStats();
    if (!wasActive && event.params.allowed) {
      stats.totalOperators += 1;
    } else if (wasActive && !event.params.allowed) {
      stats.totalOperators -= 1;
    }
    stats.save();
  }
}
