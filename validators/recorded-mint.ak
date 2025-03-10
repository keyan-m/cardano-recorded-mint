use aiken/builtin
use aiken/collection/dict
use aiken/collection/list
use aiken/primitive/bytearray
use aiken_design_patterns/linked_list.{Key}
use cardano/address.{Address, Script}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{Input, Output, OutputReference, Transaction}
use recorded_mint/utils.{
  cip67_ref_label, cip67_user_label, label_length, resolve_output_reference,
  root_asset_name,
}

pub type MintAction {
  Initiate
  NewUser
}

pub type Datum =
  Option<AssetName>

validator recorded_mint(utxo_ref: OutputReference) {
  mint(action: MintAction, own_policy: PolicyId, tx: Transaction) {
    let Transaction { inputs, outputs, mint, .. } = tx

    when action is {
      Initiate -> {
        // Only one UTxO must be produced at the script address.
        expect [list_head_output] =
          list.filter(
            outputs,
            fn(output) {
              output.address.payment_credential == Script(own_policy)
            },
          )

        linked_list.init(
          // To enforce a single initiation, the specified UTxO must be spent.
          nonce_validated: list.any(
            inputs,
            fn(input) { input.output_reference == utxo_ref },
          ),
          produced_element_output: list_head_output,
          destination_address_validator: fn(_dest: Address) -> Bool {
            // Address of the produced UTxO is already validated through the
            // filter function.
            True
          },
          list_nft_policy_id: own_policy,
          root_data_validator: fn(underlying_data: Data) -> Bool {
            builtin.un_b_data(underlying_data) == #""
          },
          tx_mint: mint,
        )
          |> linked_list.run_root_with(root_asset_name)
      }
      NewUser -> {
        // A single UTxO must be getting spent from the spending endpoint.
        expect [anchor_element_input] =
          list.filter(
            inputs,
            fn(input) {
              input.output.address.payment_credential == Script(own_policy)
            },
          )

        // Exactly 2 outputs are expected to be produced at the script.
        expect [continued_anchor_element_output,
          new_element_output] =
          list.filter(
            outputs,
            fn(output) {
              output.address.payment_credential == Script(own_policy)
            },
          )

        linked_list.insert_ordered(
          list_nft_policy_id: own_policy,
          anchor_element_input: anchor_element_input,
          continued_anchor_element_output: continued_anchor_element_output,
          new_element_output: new_element_output,
          additional_validations: fn(
            _anchor_out_ref: OutputReference,
            _anchor_is_root: Bool,
            _anchor_asset_name: Key,
            _anchor_data: Data,
            new_asset_name: Key,
            _new_data: Data,
          ) -> Bool {
            // The asset name of the `222` NFT that presumably goes to the user
            // (relying on user's signature). Same as the `100` NFT that's goes
            // to the script, except the label is `222`.
            let new_user_nft_name =
              cip67_user_label
                |> bytearray.concat(bytearray.drop(new_asset_name, label_length))

            // Mint quantity of this user NFT.
            let user_nft_mint_qty =
              mint
                |> assets.quantity_of(own_policy, new_user_nft_name)

            // One must be minted.
            user_nft_mint_qty == 1
          },
          tx_mint: mint,
        )
          |> linked_list.run_eval_with(
              root_asset_name,
              cip67_ref_label,
              label_length,
            )
      }
    }
  }

  spend(
    _option_datum: Option<Datum>,
    _redeemer: Void,
    own_ref: OutputReference,
    tx: Transaction,
  ) {
    let Transaction { inputs, mint, .. } = tx

    expect Output {
      address: Address { payment_credential: Script(own_validator_hash), .. },
      ..
    } = resolve_output_reference(inputs, own_ref)

    // The only mint endpoint that allows two assets to be minted is the
    // `NewUser` redeemer.
    ( mint |> assets.tokens(own_validator_hash) |> dict.size ) == 2
  }

  else(_) {
    fail
  }
}
