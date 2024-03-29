# Generic Cardano Mint Script, with On-Chain Record of Mints

A Cardano validator written in [Aiken](https://aiken-lang.org) that allows
minting NFTs with on-chain guarantee than no single asset is minted more than
once.

The validator can further be extended to also support a hard cap for the total
number of NFTs that can be minted for a collection.


## How does it work?

The primary construct that allows an "unlimited" (in practice) list to be
stored on-chain, is a UTxO-based linked list.

To put it briefly, each element of this list is represented with a UTxO, where
its datum points to some sort of identifier in the possible next element.

This means that injecting a new element requires spending an existing UTxO,
such that the identifier of the new element is "greater than" the identifier of
the UTxO getting spent, and also smaller than the one it currently points to.

> [!NOTE]
> The logic for comparing the identifiers depends mostly on the type of the
> identifiers. Here for example, our identifiers are byte arrays and we're
> comparing them lexicographically.

You can find a more comprehensive description of an on-chain linked list (or
association list) at [Plutonomicon's repo](https://github.com/Plutonomicon/plutonomicon/blob/94d615c68eae8efd4c89098a83d9e236ae9171a9/assoc.md).


## Validator Logic

Thanks to Aiken and its easy interface for implementing multi-validators, a
single validator can be defined to handle both minting and spending of the
on-chain list's UTxOs.

By specifying the token names as the identifiers of the linked list elements,
we can define the logic in two endpoints.

### Initiation Mint

This endpoint is meant as the first transaction to be submitted to produce the
head of the on-chain list. The main requirements are:
- A single asset is getting minted with an empty name
- This single asset is produced at the script's address with a datum that
  points to no other list elements
- The specified UTxO (as a parameter) must be spent so that the on-chain list
  can be initiated only once


### New Mints (or List Injections)

The logic here is primarily handled by the spending endpoint of the
multi-validator. The minting endpoint only verifies that a single UTxO is
getting spent from the corresponding script address (therefore ensuring the
validation of its logic).

The high-level requirements are:
- Only 2 of the specified asset are getting minted: one to be included in the
  list UTxO (to prove authenticity), and one to be sent freely anywhere else
- Token name of the asset being sent to the script must comply with [CIP-67](https://github.com/cardano-foundation/CIPs/tree/7687f28447359cd2bdbc945b6acf651906e1583b/CIP-0067)'s `(100)`, while
  the user's token name must have any other 4 byte-long label.
- Apart from their CIP-67 labels, the two assets must share the same token
  name.
- The token name of the newly minted asset is lexicographically placed between
  that of the spending UTxO and its datum (i.e. the one it potentially points
  to as its next element)

As an added benefit, this implementation also works nicely with [CIP-68](https://github.com/cardano-foundation/CIPs/tree/7687f28447359cd2bdbc945b6acf651906e1583b/CIP-0068): NFTs
produced at the script address are already forced to have the reference token's
label `(100)`, while users/buyers can receive `(222)` tokens.


## Disclaimer

At its current stage, this is primarily intended as a proof of concept and not
meant to be used in production.
