[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

type xlen = Rv32 | Rv64
type float_abi = Soft | Single | Double | Quad

type abi = {
  xlen : xlen;
  float_abi : float_abi;
  rvc : bool;
  rve : bool;
  tso : bool;
  arch : string;
  stack_align : int;
  unaligned_access : bool option;
}

let flags a =
  let bit b v = if b then v else 0L in
  let float_bits =
    match a.float_abi with
    | Soft -> Const.ef_riscv_float_abi_soft
    | Single -> Const.ef_riscv_float_abi_single
    | Double -> Const.ef_riscv_float_abi_double
    | Quad -> Const.ef_riscv_float_abi_quad
  in
  List.fold_left Int64.logor float_bits
    [ bit a.rvc Const.ef_riscv_rvc; bit a.rve Const.ef_riscv_rve; bit a.tso Const.ef_riscv_tso ]

let attributes a =
  let attrs =
    [ (4, Attributes.Uleb (Int64.of_int a.stack_align)); (5, Attributes.Ntbs a.arch) ]
    @
    match a.unaligned_access with
    | None -> []
    | Some b -> [ (6, Attributes.Uleb (if b then 1L else 0L)) ]
  in
  [ { Attributes.vendor = "riscv"; contents = `Parsed [ (Attributes.File, attrs) ] } ]

let single_order = "mafdqlcbkjtpvh"
let category_order = "iemafdqlcbkjtpvh"
let rank order c = match String.index_opt order c with Some i -> i | None -> String.length order

let isa_string xlen ~base:(b, bv) exts =
  let sort_key (name, _) =
    match if name = "" then 'x' else name.[0] with
    | 'z' -> (1, rank category_order (if String.length name > 1 then name.[1] else 'z'), name)
    | 's' -> (2, 0, name)
    | 'x' -> (3, 0, name)
    | c -> (0, rank single_order c, name)
  in
  let ordered = List.sort (fun a b -> compare (sort_key a) (sort_key b)) exts in
  let version (major, minor) = Printf.sprintf "%dp%d" major minor in
  let part (name, v) = name ^ version v in
  let base_name = match b with `I -> "i" | `E -> "e" in
  String.concat "_"
    (((match xlen with Rv32 -> "rv32" | Rv64 -> "rv64") ^ base_name ^ version bv)
    :: List.map part ordered)

let profile xlen float_abi arch =
  {
    xlen;
    float_abi;
    rvc = false;
    rve = false;
    tso = false;
    arch;
    stack_align = 16;
    unaligned_access = None;
  }

let rv32imafd_ilp32d =
  profile Rv32 Double "rv32i2p0_m2p0_a2p0_f2p0_d2p0_zmmul1p0_zaamo1p0_zalrsc1p0"

let rv32im_ilp32 = profile Rv32 Soft "rv32i2p0_m2p0_zmmul1p0"
let rv64imafd_lp64d = profile Rv64 Double "rv64i2p0_m2p0_a2p0_f2p0_d2p0_zmmul1p0_zaamo1p0_zalrsc1p0"
let rv64im_lp64 = profile Rv64 Soft "rv64i2p0_m2p0_zmmul1p0"
