type abi = { float_abi : [ `Hard | `Soft ]; attributes : Attributes.t option }

let flags a =
  Int64.logor Const.ef_arm_eabi_ver5
    (match a.float_abi with
    | `Hard -> Const.ef_arm_abi_float_hard
    | `Soft -> Const.ef_arm_abi_float_soft)

let hard_float = { float_abi = `Hard; attributes = None }
let soft_float = { float_abi = `Soft; attributes = None }
