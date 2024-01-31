use aiken/dict
use aiken/list
use aiken/transaction.{
  InlineDatum, Mint, Output, OutputReference, ScriptContext, Spend, Transaction,
}
use aiken/transaction/credential.{ScriptCredential}
use aiken/transaction/value.{AssetName, PolicyId, Value}


type MintAction {
    Initiate
    Mint
}

type Datum = Option<AssetName>
 
validator(utxo_ref: OutputReference) {
  fn mint(action: MintAction, ctx: ScriptContext) -> Bool {
    expect ScriptContext { transaction: tx, purpose: Mint(own_policy) } =
      ctx

    let Transaction { inputs, outputs, mint, .. } =
      tx

    expect [mint_triplet] =
      mint
        |> value.from_minted_value
        |> value.to_dict
        |> dict.to_list

    let (mint_policy, mint_name, mint_quantity) =
      mint_triplet

    expect (mint_policy == own_policy)?

    when action is {
      Initiate -> {
        // To enforce a single initiation, the specified UTxO must be spent.
        expect list.any(inputs, fn(input) {
          input.output_reference == utxo_ref
        })?

        // Only a single, nameless token must be minted.
        expect (mint_name == #"")?
        expect (mint_quantity == 1)?

        // Only one UTxO must be produced at the script address.
        expect [Output { datum: InlineDatum(list_head_datum), value: list_head_value, .. }] =
          list.filter(
            outputs,
            fn(output) {
              output.address.payment_credential == ScriptCredential(own_policy)
            }
          )

        // Linked list must be empty at initiation.
        expect None: Datum = list_head_datum

        // List head UTxO must contain only one other asset apart from Lovelaces.
        expect list_head_asset = get_single_asset_from_value(list_head_value)

        // List head's asset must match the minted asset.
        (list_head_asset == mint_triplet)?
      }
      Mint -> {
        // A single UTxO must be getting spent from the spending endpoint.
        expect [_] =
          list.filter(
            inputs,
            fn(input) {
              input.output.address.payment_credential == ScriptCredential(own_policy)
            }
          )
        True
      }
    }
  }
  fn spend(datum: Datum, _redeemer: Void, context: ScriptContext) -> Bool {
    expect ScriptContext { transaction: tx, purpose: Spend(own_ref) } =
      ctx

    let Transaction { inputs, outputs, mint, .. } =
      tx

    let Output { address: own_addr, value: own_value .. } =
      resolve_output_reference(inputs, own_ref)

    expect ScriptCredential(own_validator_hash) =
      own_addr.payment_credential

    let beacon_triplet =
      get_single_asset_from_value(own_value)

    // Spending UTxO must be authentic.
    let (beacon_policy, beacon_name, beacon_quantity) =
      beacon_triplet

    expect (beacon_policy == own_validator_hash)?
    expect (beacon_quantity == 1)?

    expect [mint_triplet] =
      mint
        |> value.from_minted_value
        |> value.to_dict
        |> dict.to_list

    let (mint_policy, mint_name, mint_quantity) =
      mint_triplet

    // New mint must be inserted after provided list element.
    expect (mint_name > beacon_name)?

    // Exactly 2 assets are allowed to be minted: one for the validator, one
    // for the user/buyer.
    expect (mint_quantity == 2)?

    let order_is_valid =
      when datum is {
        None -> {
          True
        }
        Some(next) -> {
          (mint_name < next)?
        }
      }

    // Exactly 2 outputs are expected to be produced at the script.
    expect [o0, o1] =
      list.filter(
        outputs,
        fn(output) {
          output.address.payment_credential == ScriptCredential(own_validator_hash)
        }
      )

    expect Output { datum: InlineDatum(d0), value: v0, .. } = o0
    expect Output { datum: InlineDatum(d1), value: v1, .. } = o1

    // Input list element is expected at an index before the new element, with
    // unchanged assets (its Lovelace count is free to change), and updated
    // datum to point to the new mint as its successor.
    let v0_triplet = get_single_asset_from_value(v0)
    expect (v0_triplet == beacon_triplet)?
    expect Some(beacon_name): Datum = d0

    // New list element's datum must be the same as the UTxO getting spent, as
    // it is getting injected in front of it in the linked list.
    let (p1, t1, q1) = get_single_asset_from_value(v1)
    expect (p1 == mint_policy)?
    expect (t1 == mint_name)?
    // Only 1 of the 2 minted tokens must be sent to the script. The other is
    // free to be sent anywhere else.
    expect (q1 == 1)?
    expect decoded_d1: Datum = d1
    (decoded_d1 == datum)?
  }
}

fn get_single_asset_from_value(v: Value) -> (PolicyId, AssetName, Int) {
  // A single asset was expected.
  expect [triplet] =
    v
      |> value.without_lovelace
      |> value.to_dict
      |> dict.to_list
  triplet
}

// Copied from:
// https://github.com/aiken-lang/fortuna
fn resolve_output_reference(
  inputs: List<Input>,
  output_ref: OutputReference
) -> Output {
  expect [input, ..inputs] = inputs

  if input.output_reference == output_ref {
    input.output
  } else {
    resolve_output_reference(inputs, output_ref)
  }
}
