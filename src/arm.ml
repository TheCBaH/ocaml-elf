[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

type abi = { float_abi : [ `Hard | `Soft ]; attributes : Attributes.t option }

let flags a =
  Int64.logor Const.ef_arm_eabi_ver5
    (match a.float_abi with
    | `Hard -> Const.ef_arm_abi_float_hard
    | `Soft -> Const.ef_arm_abi_float_soft)

let hard_float = { float_abi = `Hard; attributes = None }
let soft_float = { float_abi = `Soft; attributes = None }

let armv7a_attributes =
  [
    {
      Attributes.vendor = "aeabi";
      contents =
        `Parsed
          [
            ( Attributes.File,
              [
                (5, Attributes.Ntbs "7-A");
                (6, Attributes.Uleb 10L);
                (7, Attributes.Uleb 65L);
                (8, Attributes.Uleb 1L);
                (9, Attributes.Uleb 2L);
              ] );
          ];
    };
  ]
