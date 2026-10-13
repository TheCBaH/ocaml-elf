open Err.Syntax

type value = Uleb of int64 | Ntbs of string | Uleb_ntbs of int64 * string
type scope = File | Section of int list | Symbol of int list

type subsection = {
  vendor : string;
  contents : [ `Parsed of (scope * (int * value) list) list | `Raw of string ];
}

type t = subsection list
type length_error = { offset : int; length : int }
type kind_error = { vendor : string; tag : int }

type error =
  [ `Bad_format_version of int
  | `Truncated_subsection
  | `Bad_subsection_length of length_error
  | `Uleb_overflow of int
  | `Unterminated_ntbs of int
  | `Nul_in_value of string
  | `Unknown_scope of int
  | `Bad_value_kind of kind_error
  | `Unknown_vendor of string
  | `Bad_tag of int
  | `Bad_index of int ]

let pp_error ppf : error -> unit = function
  | `Bad_format_version v -> Format.fprintf ppf "unsupported attribute format version 0x%02x" v
  | `Truncated_subsection -> Format.pp_print_string ppf "attribute data ends inside a subsection"
  | `Bad_subsection_length { offset; length } ->
      Format.fprintf ppf "attribute subsection at offset %d has invalid length %d" offset length
  | `Uleb_overflow o -> Format.fprintf ppf "ULEB128 at offset %d does not fit in 64 bits" o
  | `Unterminated_ntbs o ->
      Format.fprintf ppf "string at offset %d is not NUL-terminated within its subsection" o
  | `Nul_in_value s -> Format.fprintf ppf "attribute string %S contains a NUL byte" s
  | `Unknown_scope s -> Format.fprintf ppf "unknown attribute scope tag %d" s
  | `Bad_value_kind { vendor; tag } ->
      Format.fprintf ppf "value of tag %d has the wrong form for vendor %S" tag vendor
  | `Unknown_vendor v ->
      Format.fprintf ppf "cannot encode parsed attributes for vendor %S: its tags are not known" v
  | `Bad_tag t -> Format.fprintf ppf "attribute tag %d is negative" t
  | `Bad_index i -> Format.fprintf ppf "attribute index %d is not positive" i

let fail e = Err.fail ~pos:__POS__ ~pp_error e

let classify ~vendor ~tag =
  match vendor with
  | "riscv" -> Some (if tag land 1 = 0 then `Uleb else `Ntbs)
  | "aeabi" ->
      Some
        (if tag = 4 || tag = 5 || tag = 67 then `Ntbs
         else if tag = 32 then `Uleb_ntbs
         else if tag < 32 then `Uleb
         else if tag land 1 = 1 then `Ntbs
         else `Uleb)
  | _ -> None

let known vendor = classify ~vendor ~tag:0 <> None

(* {1 Decoding} *)

let scope_tag_file = 1
let scope_tag_section = 2
let scope_tag_symbol = 3

(* ULEB128 in [pos, limit); returns the value and the next position. *)
let read_uleb data pos limit =
  let rec go p shift acc =
    if shift >= 64 then fail (`Uleb_overflow pos)
    else if p >= limit then fail `Truncated_subsection
    else
      let b = Char.code data.[p] in
      let low = b land 0x7f in
      if shift = 63 && low > 1 then fail (`Uleb_overflow pos)
      else
        let acc = Int64.logor acc (Int64.shift_left (Int64.of_int low) shift) in
        if b land 0x80 = 0 then Ok (acc, p + 1) else go (p + 1) (shift + 7) acc
  in
  go pos 0 0L

let read_int data pos limit =
  let* v, next = read_uleb data pos limit in
  match U64.to_int v with Some i -> Ok (i, next) | None -> fail (`Uleb_overflow pos)

let read_ntbs data pos limit =
  match String.index_from_opt data pos '\000' with
  | Some stop when stop < limit -> Ok (String.sub data pos (stop - pos), stop + 1)
  | _ -> fail (`Unterminated_ntbs pos)

let read_u32 e data pos limit =
  if limit - pos < 4 then fail `Truncated_subsection else Ok (Codec.get_u32 e data pos)

let read_value ~kind data pos limit =
  match kind with
  | `Uleb ->
      let+ v, next = read_uleb data pos limit in
      (Uleb v, next)
  | `Ntbs ->
      let+ s, next = read_ntbs data pos limit in
      (Ntbs s, next)
  | `Uleb_ntbs ->
      let* v, p = read_uleb data pos limit in
      let+ s, next = read_ntbs data p limit in
      (Uleb_ntbs (v, s), next)

let rec read_attributes ~vendor data pos stop acc =
  if pos >= stop then Ok (List.rev acc)
  else
    let* tag, p = read_int data pos stop in
    match classify ~vendor ~tag with
    | None -> assert false (* only called for vendors whose tags are classified *)
    | Some kind ->
        let* v, next = read_value ~kind data p stop in
        read_attributes ~vendor data next stop ((tag, v) :: acc)

let rec read_indices data pos stop acc =
  let* i, p = read_int data pos stop in
  if i = 0 then Ok (List.rev acc, p) else read_indices data p stop (i :: acc)

let read_scope_group e ~vendor data pos stop =
  let* scope_tag, p = read_int data pos stop in
  let* length = read_u32 e data p stop in
  let body = p + 4 in
  let bad () =
    fail
      (`Bad_subsection_length
         { offset = pos; length = Option.value (U64.to_int length) ~default:max_int })
  in
  match U64.to_int length with
  | None -> bad ()
  | Some length when length < body - pos || length > stop - pos -> bad ()
  | Some length ->
      let group_end = pos + length in
      let* scope, attrs_at =
        if scope_tag = scope_tag_file then Ok (File, body)
        else if scope_tag = scope_tag_section then
          let+ idx, q = read_indices data body group_end [] in
          (Section idx, q)
        else if scope_tag = scope_tag_symbol then
          let+ idx, q = read_indices data body group_end [] in
          (Symbol idx, q)
        else fail (`Unknown_scope scope_tag)
      in
      let+ attrs = read_attributes ~vendor data attrs_at group_end [] in
      ((scope, attrs), group_end)

let rec read_scope_groups e ~vendor data pos stop acc =
  if pos >= stop then Ok (List.rev acc)
  else
    let* group, next = read_scope_group e ~vendor data pos stop in
    read_scope_groups e ~vendor data next stop (group :: acc)

let read_subsection e data pos len =
  let* length = read_u32 e data pos len in
  match U64.to_int length with
  | Some l when l >= 5 && l <= len - pos ->
      let stop = pos + l in
      let* vendor, body = read_ntbs data (pos + 4) stop in
      let+ contents =
        if known vendor then
          let+ groups = read_scope_groups e ~vendor data body stop [] in
          `Parsed groups
        else Ok (`Raw (String.sub data body (stop - body)))
      in
      ({ vendor; contents }, stop)
  | _ ->
      fail
        (`Bad_subsection_length
           { offset = pos; length = Option.value (U64.to_int length) ~default:max_int })

let decode e data =
  let len = String.length data in
  if len = 0 then fail `Truncated_subsection
  else if data.[0] <> 'A' then fail (`Bad_format_version (Char.code data.[0]))
  else
    let rec go pos acc =
      if pos = len then Ok (List.rev acc)
      else
        let* sub, next = read_subsection e data pos len in
        go next (sub :: acc)
    in
    go 1 []

(* {1 Encoding} *)

let add_uleb buf v =
  let rec go v =
    let low = Int64.to_int (Int64.logand v 0x7fL) in
    let rest = Int64.shift_right_logical v 7 in
    if rest = 0L then Buffer.add_char buf (Char.chr low)
    else begin
      Buffer.add_char buf (Char.chr (low lor 0x80));
      go rest
    end
  in
  go v

let add_u32 e buf v =
  let b = Bytes.create 4 in
  Codec.set_u32 e b 0 (Int64.of_int v);
  Buffer.add_bytes buf b

let add_ntbs buf s =
  if String.contains s '\000' then fail (`Nul_in_value s)
  else begin
    Buffer.add_string buf s;
    Buffer.add_char buf '\000';
    Ok ()
  end

let add_tag buf tag =
  if tag < 0 then fail (`Bad_tag tag)
  else begin
    add_uleb buf (Int64.of_int tag);
    Ok ()
  end

let add_attribute ~vendor buf (tag, v) =
  let* () = add_tag buf tag in
  let mismatch () = fail (`Bad_value_kind { vendor; tag }) in
  match (classify ~vendor ~tag, v) with
  | Some `Uleb, Uleb n ->
      add_uleb buf n;
      Ok ()
  | Some `Ntbs, Ntbs s -> add_ntbs buf s
  | Some `Uleb_ntbs, Uleb_ntbs (n, s) ->
      add_uleb buf n;
      add_ntbs buf s
  | _ -> mismatch ()

let add_scope_group e ~vendor buf (scope, attrs) =
  let body = Buffer.create 32 in
  let scope_tag, indices =
    match scope with
    | File -> (scope_tag_file, [])
    | Section l -> (scope_tag_section, l)
    | Symbol l -> (scope_tag_symbol, l)
  in
  let* () =
    Err.List.iter
      (fun i ->
        if i <= 0 then fail (`Bad_index i)
        else begin
          add_uleb body (Int64.of_int i);
          Ok ()
        end)
      indices
  in
  if scope <> File then add_uleb body 0L;
  let* () = Err.List.iter (add_attribute ~vendor body) attrs in
  let head = Buffer.create 8 in
  add_uleb head (Int64.of_int scope_tag);
  add_u32 e head (Buffer.length head + 4 + Buffer.length body);
  Buffer.add_buffer buf head;
  Buffer.add_buffer buf body;
  Ok ()

let add_subsection e buf { vendor; contents } =
  let body = Buffer.create 64 in
  let* () = add_ntbs body vendor in
  let* () =
    match contents with
    | `Raw bytes ->
        Buffer.add_string body bytes;
        Ok ()
    | `Parsed groups ->
        if known vendor then Err.List.iter (add_scope_group e ~vendor body) groups
        else fail (`Unknown_vendor vendor)
  in
  add_u32 e buf (4 + Buffer.length body);
  Buffer.add_buffer buf body;
  Ok ()

let encode e t =
  let buf = Buffer.create 128 in
  Buffer.add_char buf 'A';
  let+ () = Err.List.iter (add_subsection e buf) t in
  Buffer.contents buf

let find t ~vendor ~tag =
  let in_group (scope, attrs) = if scope = File then List.assoc_opt tag attrs else None in
  let rec go = function
    | [] -> None
    | { vendor = v; contents = `Parsed groups } :: rest when v = vendor -> (
        match List.find_map in_group groups with Some _ as r -> r | None -> go rest)
    | _ :: rest -> go rest
  in
  go t
