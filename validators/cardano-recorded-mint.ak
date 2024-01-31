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
        expect [Input { output: Output { datum: InlineDatum(list_elem_datum), value: list_elem_value) }, .. }] =
          list.filter(
            inputs,
            fn(input) {
              input.output.address.payment_credential == ScriptCredential(own_policy)
            }
          )

        // Only 2 assets are allowed to be minted.
        expect (mint_quantity == 2)?

        // List element UTxO must be authentic.
        expect (beacon_policy, beacon_name, beacon_quantity) =
          get_single_asset_from_value(list_elem_value)

        expect (beacon_policy == own_policy)?
        expect (beacon_quantity == 1)?

        // New mint must be inserted after provided list element.
        expect (mint_name > beacon_name)?

        expect maybe_next: Datum = list_elem_datum

        when maybe_next is {
          None -> {
            True
          }
          Some(next) -> {
            (mint_name < next)?
          }
        }
      }
    }
  }
  fn spend(datum: Datum, _redeemer: Void, context: ScriptContext) -> Bool {
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
