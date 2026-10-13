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

let sections out =
  List.filter_map
    (fun l ->
      let l = strip l in
      if starts_with ~prefix:"[" l && not (starts_with ~prefix:"[Nr]" l) then
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
    (lines out)

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

let symbols out =
  List.map
    (fun (table, ls) ->
      let syms =
        List.filter_map
          (fun l ->
            match tokens l with
            | num :: value :: size :: typ :: bind :: vis :: ndx :: rest
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
                    name = (match rest with n :: _ -> n | [] -> "");
                  }
            | _ -> None)
          ls
      in
      (table, syms))
    (blocks ~prefix:"Symbol table '" out)

let relocs out =
  List.map
    (fun (sect, ls) ->
      let rs =
        List.filter_map
          (fun l ->
            match tokens l with
            | offset :: info :: rtype :: rest
              when String.length offset >= 8
                   && String.for_all
                        (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
                        offset ->
                (* [sym value] [name [+|- addend]] *)
                let rest =
                  match rest with
                  | v :: r
                    when String.for_all (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false) v
                         && String.length v >= 8 ->
                      r
                  | r -> r
                in
                let sym_name, addend =
                  match rest with
                  | [] -> ("", None)
                  | [ n ] -> (n, None)
                  | [ n; "+"; a ] -> (n, Some (hex a))
                  | [ n; "-"; a ] -> (n, Some (Int64.neg (hex a)))
                  | [ "+"; a ] -> ("", Some (hex a))
                  | [ "-"; a ] -> ("", Some (Int64.neg (hex a)))
                  | _ -> failwith ("cannot parse relocation line: " ^ l)
                in
                Some { offset = hex offset; info = hex info; rtype; sym_name; addend }
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
