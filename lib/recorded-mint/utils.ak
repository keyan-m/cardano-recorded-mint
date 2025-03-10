use aiken/builtin
use cardano/transaction.{Input, Output, OutputReference}

pub const root_asset_name = #""

pub const cip67_ref_label = #"000643b0"

pub const cip67_user_label = #"000de140"

pub const label_length = 4

// Copied over from the Fortuna repo:
// https://github.com/cardano-miners/fortuna/blob/32a5edf5b56c8d8a97c45eae254a70d1c66bd972/lib/fortuna/utils.ak#L6-L17
pub fn resolve_output_reference(
  inputs: List<Input>,
  output_ref: OutputReference,
) -> Output {
  expect [input, ..] = inputs
  if input.output_reference == output_ref {
    input.output
  } else {
    resolve_output_reference(builtin.tail_list(inputs), output_ref)
  }
}
