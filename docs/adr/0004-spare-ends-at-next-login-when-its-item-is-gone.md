# A Spare whose item has gone is withdrawn at the owner's next login, unless it has a Claim

BFF can tell when a Spare's item has left its owner's bags and bank: `C_Item.IsItemGUIDInInventory` turns false (retail results in `docs/research/bag-items.md`, #67). Withdrawing it at that moment would be wrong in two cases. A sold item can be bought back with the same GUID until the owner logs out. And mailing the item to the winning claimer is the normal way to pass it on, so a missing item may mean it was delivered and the owner hasn't clicked Give yet. We considered withdrawing straight away, and only warning the owner. So BFF waits until the owner's next login: buyback is empty by then. If the item is still gone, a Spare with no Claim is withdrawn, as if the owner had withdrawn it. One with a Claim is not ended automatically. BFF asks the owner whether they mailed it to the claimer (Give) or not (withdraw).

## Consequences

- Until the owner's next login, the Crew may see an offer whose item is already gone. The owner's own tab notes that the item has left their bags.
- Equipping counts as leaving: the item may now be bound, so it can't be passed on.
- Only the owner's client can check its own bags, so it is the only one that ever withdraws a Spare for this reason. The withdrawal reaches the Crew the same way a manual one does (ADR 0001).
- The check runs only after the first `BAG_UPDATE_DELAYED` of a session. Before that, the bags read as empty and every item would look gone.
