use aiken/collection/list
use aiken/primitive/bytearray
use cardano/address.{Script}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}
use recorded_mint/utils.{
  cip67_ref_label, get_single_asset_from_value, resolve_output_reference,
  validate_mint_labels,
}

pub type MintAction {
  Initiate
  NewMint
}

pub type Datum =
  Option<AssetName>

validator recorded_mint(utxo_ref: OutputReference) {
  mint(action: MintAction, own_policy: PolicyId, tx: Transaction) {
    let Transaction { inputs, outputs, mint, .. } = tx

    expect [mint_triplet] =
      mint
        |> assets.flatten

    let (mint_policy, mint_name, mint_quantity) = mint_triplet

    expect (mint_policy == own_policy)?

    when action is {
      Initiate -> {
        // To enforce a single initiation, the specified UTxO must be spent.
        expect
          list.any(inputs, fn(input) { input.output_reference == utxo_ref })?

        // Only a single, nameless token must be minted.
        expect (mint_name == #"")?
        expect (mint_quantity == 1)?

        // Only one UTxO must be produced at the script address.
        expect [
          Output {
            datum: InlineDatum(list_head_datum),
            value: list_head_value,
            ..
          },
        ] =
          list.filter(
            outputs,
            fn(output) {
              output.address.payment_credential == Script(own_policy)
            },
          )

        // Linked list must be empty at initiation.
        expect None: Datum = list_head_datum

        // List head UTxO must contain only one other asset apart from Lovelaces.
        let list_head_asset = get_single_asset_from_value(list_head_value)

        // List head's asset must match the minted asset.
        (list_head_asset == mint_triplet)?
      }
      NewMint -> {
        // A single UTxO must be getting spent from the spending endpoint.
        expect [_] =
          list.filter(
            inputs,
            fn(input) {
              input.output.address.payment_credential == Script(own_policy)
            },
          )
        True
      }
    }
  }

  spend(
    option_datum: Option<Datum>,
    _redeemer: Void,
    own_ref: OutputReference,
    tx: Transaction,
  ) {
    expect Some(datum) = option_datum

    let Transaction { inputs, outputs, mint, .. } = tx

    let Output { address: own_addr, value: own_value, .. } =
      resolve_output_reference(inputs, own_ref)

    expect Script(own_validator_hash) = own_addr.payment_credential

    let beacon_triplet = get_single_asset_from_value(own_value)

    // Spending UTxO must be authentic.
    let (beacon_policy, beacon_name, beacon_quantity) = beacon_triplet

    // The asset included in the UTxO getting spent must be prefixed with
    // CIP-67's `100` to ensure that it's never left the script. Or check that
    // the beacon is from list's head.
    expect
      (bytearray.take(beacon_name, 4) == cip67_ref_label || beacon_name == "")?

    expect (beacon_policy == own_validator_hash)?
    expect (beacon_quantity == 1)?

    expect [triplet0,
      triplet1] =
      mint
        |> assets.flatten

    // Distinguishes the asset triplet with CIP-67 reference label (100), and
    // also ensures the other triplet's token name does not start with `100`.
    let (script_asset_triplet, user_asset_triplet) =
      validate_mint_labels(triplet0, triplet1)

    let (script_mint_policy, script_mint_name, script_mint_quantity) =
      script_asset_triplet

    let (user_mint_policy, user_mint_name, user_mint_quantity) =
      user_asset_triplet

    // Only mints of this validator are allowed.
    expect (script_mint_policy == own_validator_hash)?
    expect (user_mint_policy == own_validator_hash)?

    // Apart from their labels, script and user assets must have equal token
    // names (user asset must have an arbitrary, 4 byte-long label other than
    // CIP-67's `100`).
    let script_asset_name = bytearray.drop(script_mint_name, 4)
    let user_asset_name = bytearray.drop(user_mint_name, 4)
    expect (script_asset_name == user_asset_name)?

    // Exactly 1 of each assets are allowed to be minted.
    expect (script_mint_quantity == 1)?
    expect (user_mint_quantity == 1)?

    // New mint must be inserted after provided list element (no need to
    // separate labels and names here).
    expect (bytearray.compare(script_mint_name, beacon_name) == Greater)?

    // New mint's token name must be lexicographically smaller than the
    // potential next element.
    let order_is_valid =
      when datum is {
        None -> True
        Some(next) -> (bytearray.compare(script_mint_name, next) == Less)?
      }

    // Exactly 2 outputs are expected to be produced at the script.
    expect [o0,
      o1] =
      list.filter(
        outputs,
        fn(output) {
          output.address.payment_credential == Script(own_validator_hash)
        },
      )

    expect Output { datum: InlineDatum(d0), value: v0, .. } = o0
    expect Output { datum: InlineDatum(d1), value: v1, .. } = o1

    // Input list element is expected to be reproduced at an index before the
    // new element, with unchanged assets (its Lovelace count is free to
    // change), and updated datum to point to the new mint as its successor.
    let v0_triplet = get_single_asset_from_value(v0)
    expect (v0_triplet == beacon_triplet)?
    expect Some(new_next): Datum = d0
    expect (new_next == script_mint_name)?

    // New list element is going to sit between the UTxO that is getting spent,
    // and the (possible) subsequent element. Therefore, the new element must
    // now point to that same (possible) subsequent element as its next.
    expect decoded_d1: Datum = d1
    expect (decoded_d1 == datum)?

    // Only 1 of the 2 minted tokens must be sent to the script. The other is
    // free to be sent anywhere else.
    let (p1, t1, q1) = get_single_asset_from_value(v1)
    expect (p1 == own_validator_hash)?
    expect (t1 == script_mint_name)?
    expect (q1 == 1)?

    order_is_valid?
  }

  else(_) {
    fail
  }
}
