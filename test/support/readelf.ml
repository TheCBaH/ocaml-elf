[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

type section = {
  nr : int;
  name : string;
  typ : string;
  addr : int64;
  off : int64;
  size : int64;
  es : int64;
  flags : string;
  lk : int;
  inf : int;
  al : int64;
}

type symbol = {
  num : int;
  value : int64;
  size : int64;
  typ : string;
  bind : string;
  vis : string;
  ndx : string;
  name : string;
}

type reloc = {
  offset : int64;
  info : int64;
  rtype : string;
  sym_name : string;
  addend : int64 option;
}

type segment = {
  ptype : string;
  p_offset : int64;
  vaddr : int64;
  paddr : int64;
  filesz : int64;
  memsz : int64;
  pflags : string;
  palign : int64;
}

let lines s = String.split_on_char '\n' s

let tokens line =
  String.split_on_char ' ' (String.map (fun c -> if c = '\t' then ' ' else c) line)
  |> List.filter (fun t -> t <> "")

let starts_with ~prefix s =
  String.length s >= String.length prefix && String.sub s 0 (String.length prefix) = prefix

let strip s = String.trim s

let hex s =
  let s = if starts_with ~prefix:"0x" s then String.sub s 2 (String.length s - 2) else s in
  Int64.of_string ("0x" ^ s)

(* Sizes are decimal, or hex with a 0x prefix when large. *)
let number s = if starts_with ~prefix:"0x" s then hex s else Int64.of_string s

let header out =
  List.filter_map
    (fun l ->
      match String.index_opt l ':' with
      | Some i when starts_with ~prefix:"  " l && String.length l > 2 && l.[2] <> ' ' ->
          let key = strip (String.sub l 0 i) in
          if key = "Magic" then None
          else Some (key, strip (String.sub l (i + 1) (String.length l - i - 1)))
      | _ -> None)
    (lines out)

(* A section whose name is too long for its column has the remaining fields on the next line. *)
let join_wrapped_rows ls =
  let is_bare_row l =
    let l = strip l in
    starts_with ~prefix:"[" l
    &&
    match String.index_opt l ']' with
    | Some i ->
        int_of_string_opt (strip (String.sub l 1 (i - 1))) <> None
        && List.length (tokens (String.sub l (i + 1) (String.length l - i - 1))) = 1
    | None -> false
  in
  let rec go = function
    | a :: b :: rest when is_bare_row a -> go ((a ^ " " ^ strip b) :: rest)
    | x :: rest -> x :: go rest
    | [] -> []
  in
  go ls

(* The lines of the "Section Headers:" table (other parts of -a list sections too, e.g. group
   members). *)
let section_block ls =
  let rec after = function
    | [] -> []
    | l :: rest -> if starts_with ~prefix:"Section Headers:" l then rest else after rest
  in
  let rec upto = function
    | [] -> []
    | l :: rest -> if starts_with ~prefix:"Key to Flags:" l then [] else l :: upto rest
  in
  upto (after ls)

let sections out =
  List.filter_map
    (fun l ->
      let l = strip l in
      let is_row =
        starts_with ~prefix:"[" l
        &&
        match String.index_opt l ']' with
        | Some i -> int_of_string_opt (strip (String.sub l 1 (i - 1))) <> None
        | None -> false
      in
      if is_row then
        match String.index_opt l ']' with
        | None -> None
        | Some i -> (
            let nr = int_of_string (strip (String.sub l 1 (i - 1))) in
            let toks = tokens (String.sub l (i + 1) (String.length l - i - 1)) in
            (* [name] type addr off size es [flags] lk inf al; the null section has no name. *)
            let name, toks =
              match toks with
              | "NULL" :: _ when List.length toks = 8 -> ("", toks)
              | n :: rest -> (n, rest)
              | [] -> ("", [])
            in
            match toks with
            | typ :: addr :: off :: size :: es :: rest ->
                let flags, lk, inf, al =
                  match rest with
                  | [ f; lk; inf; al ] -> (f, lk, inf, al)
                  | [ lk; inf; al ] -> ("", lk, inf, al)
                  | _ -> failwith ("cannot parse section line: " ^ l)
                in
                Some
                  {
                    nr;
                    name;
                    typ;
                    addr = hex addr;
                    off = hex off;
                    size = hex size;
                    es = hex es;
                    flags;
                    lk = int_of_string lk;
                    inf = int_of_string inf;
                    al = number al;
                  }
            | _ -> failwith ("cannot parse section line: " ^ l))
      else None)
    (join_wrapped_rows (section_block (lines out)))

(* Blocks introduced by a title line "<prefix> '<name>' ...": returns (name, following lines). *)
let blocks ~prefix out =
  let rec go acc cur = function
    | [] -> List.rev (match cur with Some (n, ls) -> (n, List.rev ls) :: acc | None -> acc)
    | l :: rest -> (
        if starts_with ~prefix l then
          let name =
            match (String.index_opt l '\'', String.rindex_opt l '\'') with
            | Some a, Some b when b > a -> String.sub l (a + 1) (b - a - 1)
            | _ -> ""
          in
          let acc = match cur with Some (n, ls) -> (n, List.rev ls) :: acc | None -> acc in
          go acc (Some (name, [])) rest
        else
          match cur with
          | Some (n, ls) -> go acc (Some (n, l :: ls)) rest
          | None -> go acc None rest)
  in
  go [] None (lines out)

(* The first [n] whitespace-separated tokens of [s], and what follows the separator after the nth
   verbatim: a symbol name may end in a space (RISC-V's ".L0 "), which tokenizing would lose. *)
let split_n n s =
  let len = String.length s in
  let rec skip_blank i =
    if i < len && (s.[i] = ' ' || s.[i] = '\t') then skip_blank (i + 1) else i
  in
  let rec token_end i = if i < len && s.[i] <> ' ' && s.[i] <> '\t' then token_end (i + 1) else i in
  let rec go k i acc =
    if k = 0 then (List.rev acc, if i < len then String.sub s (i + 1) (len - i - 1) else "")
    else
      let start = skip_blank i in
      if start >= len then (List.rev acc, "")
      else
        let stop = token_end start in
        go (k - 1) stop (String.sub s start (stop - start) :: acc)
  in
  go n 0 []

let symbols out =
  List.map
    (fun (table, ls) ->
      let syms =
        List.filter_map
          (fun l ->
            match split_n 7 l with
            | [ num; value; size; typ; bind; vis; ndx ], name
              when String.length num > 1
                   && num.[String.length num - 1] = ':'
                   && num.[0] >= '0'
                   && num.[0] <= '9' ->
                Some
                  {
                    num = int_of_string (String.sub num 0 (String.length num - 1));
                    value = hex value;
                    size = number size;
                    typ;
                    bind;
                    vis;
                    ndx;
                    name;
                  }
            | _ -> None)
          ls
      in
      (table, syms))
    (blocks ~prefix:"Symbol table '" out)

let is_hex_digits v =
  v <> "" && String.for_all (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false) v

(* The name and optional addend of "name + addend" / "name - addend", the name kept verbatim. *)
let name_and_addend r =
  let len = String.length r in
  let rec last_op i =
    if i < 0 then None
    else if
      i + 3 <= len
      && (String.sub r i 3 = " + " || String.sub r i 3 = " - ")
      && is_hex_digits (String.trim (String.sub r (i + 3) (len - i - 3)))
    then Some i
    else last_op (i - 1)
  in
  match last_op (len - 3) with
  | Some i ->
      let a = hex (String.trim (String.sub r (i + 3) (len - i - 3))) in
      (String.sub r 0 i, Some (if r.[i + 1] = '-' then Int64.neg a else a))
  | None -> (r, None)

let relocs out =
  List.map
    (fun (sect, ls) ->
      let rs =
        List.filter_map
          (fun l ->
            match split_n 3 l with
            | [ offset; info; rtype ], rest when String.length offset >= 8 && is_hex_digits offset
              ->
                let info_value = hex info in
                (* With no symbol (r_sym = 0) readelf omits the symbol columns and prints only the
                   addend, in hex and unsigned. *)
                let sym =
                  if String.length info >= 16 then Int64.shift_right_logical info_value 32
                  else Int64.shift_right_logical info_value 8
                in
                let rest = String.trim rest in
                let sym_name, addend =
                  if rest = "" then ("", None)
                  else if sym = 0L then ("", if is_hex_digits rest then Some (hex rest) else None)
                  else
                    (* drop the symbol's value column *)
                    let value, after = split_n 1 rest in
                    let after =
                      match value with
                      | [ v ] when is_hex_digits v && String.length v >= 8 -> after
                      | _ -> rest
                    in
                    let after =
                      (* one separator, not trailing characters of the name *)
                      let i = ref 0 in
                      while !i < String.length after && after.[!i] = ' ' do
                        incr i
                      done;
                      String.sub after !i (String.length after - !i)
                    in
                    name_and_addend after
                in
                Some { offset = hex offset; info = info_value; rtype; sym_name; addend }
            | _ -> None)
          ls
      in
      (sect, rs))
    (blocks ~prefix:"Relocation section '" out)

let segments out =
  let rec after_header = function
    | [] -> []
    | l :: rest -> if starts_with ~prefix:"  Type" l then rest else after_header rest
  in
  List.filter_map
    (fun l ->
      match tokens l with
      | ptype :: off :: va :: pa :: fsz :: msz :: rest
        when starts_with ~prefix:"0x" off && starts_with ~prefix:"0x" va && rest <> [] ->
          let rev = List.rev rest in
          let align = List.hd rev and flags = List.rev (List.tl rev) in
          Some
            {
              ptype;
              p_offset = hex off;
              vaddr = hex va;
              paddr = hex pa;
              filesz = hex fsz;
              memsz = hex msz;
              pflags = String.concat " " flags;
              palign = hex align;
            }
      | _ -> None)
    (after_header (lines out))

let attributes out =
  let rec after = function
    | [] -> []
    | l :: rest -> if strip l = "File Attributes" then rest else after rest
  in
  let rec take = function
    | l :: rest when starts_with ~prefix:"  Tag_" l -> l :: take rest
    | _ -> []
  in
  List.filter_map
    (fun l ->
      match String.index_opt l ':' with
      | Some i ->
          Some (strip (String.sub l 0 i), strip (String.sub l (i + 1) (String.length l - i - 1)))
      | None -> None)
    (take (after (lines out)))

let notes out =
  let rec go acc cur = function
    | [] -> List.rev (match cur with Some c -> c :: acc | None -> acc)
    | l :: rest -> (
        let prefix = "Displaying notes found in: " in
        if starts_with ~prefix l then
          let name = String.sub l (String.length prefix) (String.length l - String.length prefix) in
          let acc = match cur with Some c -> c :: acc | None -> acc in
          go acc (Some (strip name, [])) rest
        else
          match (cur, tokens l) with
          | Some (n, ns), owner :: size :: _ when starts_with ~prefix:"0x" size && owner <> "Owner"
            ->
              go acc (Some (n, (owner, hex size) :: ns)) rest
          | _ -> go acc cur rest)
  in
  List.map (fun (n, ns) -> (n, List.rev ns)) (go [] None (lines out))
