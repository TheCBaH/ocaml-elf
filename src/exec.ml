open Types
open Err.Syntax

(* A spec can have tens of thousands of sections or segments, and js_of_ocaml's stack is small, so
   the list functions used on them are the tail-recursive ones. *)
let map f l = List.rev (List.rev_map f l)

let mapi f l =
  let rec go i acc = function [] -> List.rev acc | x :: rest -> go (i + 1) (f i x :: acc) rest in
  go 0 [] l

let ( @ ) a b = List.rev_append (List.rev a) b

type perms = { read : bool; write : bool; execute : bool }
type content = Bytes of string | Zero of int64
type section = { name : string; addr : int64; align : int64; content : content }
type segment = { perms : perms; paddr : int64 option; sections : section list }
type headers = Unmapped | Mapped of { vaddr : int64; paddr : int64 option }

type symbol = {
  name : string;
  value : int64;
  size : int64;
  kind : [ `Notype | `Object | `Func ];
  binding : [ `Local | `Global | `Weak ];
  section : string option;
}

type spec = {
  target : Target.t;
  entry : int64;
  segments : segment list;
  headers : headers;
  gnu_stack : perms option;
  section_headers : bool;
  symbols : symbol list;
}

type region = [ `Headers | `Segment of int ]
type bad_alignment = { section : string; align : int64 }
type misaligned = { section : string; addr : int64; align : int64 }
type overlap = { segment : int; first : string; second : string }
type after_zero_fill = { segment : int; section : string }
type range_of = [ `Vaddr of int | `Paddr of int | `Headers_vaddr | `Headers_paddr ]
type range = { range : range_of; start : int64; length : int64 }
type shared_page = { first : region; second : region; page : int64 }
type physical_overlap = { first : region; second : region }
type misaligned_headers = { vaddr : int64; page : int64 }
type ram = { ram_start : int64; ram_size : int64 }
type outside_ram = { where : region; paddr : int64; length : int64; ram : ram }
type name_kind = [ `Section | `Symbol ]
type bad_name = { kind : name_kind; name : string }
type symbol_section = { symbol : string; section : string }
type symbol_index = { symbol : string; index : int }

type error =
  [ `Bad_alignment of bad_alignment
  | `Bad_page_size of int64
  | `Section_misaligned of misaligned
  | `Empty_segment of int
  | `Sections_overlap of overlap
  | `Data_after_zero_fill of after_zero_fill
  | `Range_exceeds_class of range
  | `Segments_share_page of shared_page
  | `Physical_overlap of physical_overlap
  | `Headers_misaligned of misaligned_headers
  | `Entry_not_executable of int64
  | `Outside_ram of outside_ram
  | `Duplicate_section of string
  | `Bad_name of bad_name
  | `Unknown_symbol_section of symbol_section
  | `Symbols_without_sections
  | `Unsupported_symbol_section_index of symbol_index
  | `File_too_large of int64
  | `Invalid_spec of error list
  | Encode.error
  | Strtab.error
  | Attributes.error ]

let pp_region ppf = function
  | `Headers -> Format.pp_print_string ppf "the headers"
  | `Segment i -> Format.fprintf ppf "segment %d" i

let pp_range_of ppf = function
  | `Vaddr i -> Format.fprintf ppf "virtual range of segment %d" i
  | `Paddr i -> Format.fprintf ppf "physical range of segment %d" i
  | `Headers_vaddr -> Format.pp_print_string ppf "virtual range of the headers"
  | `Headers_paddr -> Format.pp_print_string ppf "physical range of the headers"

let rec pp_error ppf : error -> unit = function
  | `Bad_alignment { section; align } ->
      Format.fprintf ppf "section %S: alignment %a is not a power of two" section U64.pp align
  | `Bad_page_size p -> Format.fprintf ppf "page size %a is not a power of two" U64.pp p
  | `Section_misaligned { section; addr; align } ->
      Format.fprintf ppf "section %S at %a is not aligned to %a" section U64.pp addr U64.pp align
  | `Empty_segment i -> Format.fprintf ppf "segment %d has no sections" i
  | `Sections_overlap { segment; first; second } ->
      Format.fprintf ppf "segment %d: section %S overlaps or precedes section %S" segment second
        first
  | `Data_after_zero_fill { segment; section } ->
      Format.fprintf ppf "segment %d: initialized section %S follows a zero-fill section" segment
        section
  | `Range_exceeds_class { range; start; length } ->
      Format.fprintf ppf "%a: %a + %a is outside the address space of the target class" pp_range_of
        range U64.pp start U64.pp length
  | `Segments_share_page { first; second; page } ->
      Format.fprintf ppf "%a and %a share the page at %a" pp_region first pp_region second U64.pp
        page
  | `Physical_overlap { first; second } ->
      Format.fprintf ppf "%a and %a overlap in physical memory" pp_region first pp_region second
  | `Headers_misaligned { vaddr; page } ->
      Format.fprintf ppf "headers at %a are not aligned to the %a page size" U64.pp vaddr U64.pp
        page
  | `Entry_not_executable e ->
      Format.fprintf ppf
        "entry point %a is not inside the initialized part of an executable segment" U64.pp e
  | `Outside_ram { where; paddr; length; ram } ->
      Format.fprintf ppf "%a at physical %a + %a lies outside RAM [%a, +%a)" pp_region where U64.pp
        paddr U64.pp length U64.pp ram.ram_start U64.pp ram.ram_size
  | `Duplicate_section n -> Format.fprintf ppf "section name %S is used twice" n
  | `Bad_name { kind; name } ->
      Format.fprintf ppf "%s name %S contains a NUL byte"
        (match kind with `Section -> "section" | `Symbol -> "symbol")
        name
  | `Unknown_symbol_section { symbol; section } ->
      Format.fprintf ppf "symbol %S refers to the unknown section %S" symbol section
  | `Symbols_without_sections ->
      Format.pp_print_string ppf "symbols need section headers, but section_headers is false"
  | `Unsupported_symbol_section_index { symbol; index } ->
      Format.fprintf ppf
        "symbol %S: section index %d needs SHT_SYMTAB_SHNDX, which the builder does not write"
        symbol index
  | `File_too_large n ->
      Format.fprintf ppf "the file would need %a bytes, more than this platform can address" U64.pp
        n
  | `Invalid_spec errs ->
      Format.fprintf ppf "@[<v>invalid executable spec:@,%a@]"
        (Format.pp_print_list (fun ppf e -> Format.fprintf ppf "- @[%a@]" pp_error e))
        errs
  | #Encode.error as e -> Encode.pp_error ppf e
  | #Strtab.error as e -> Strtab.pp_error ppf e
  | #Attributes.error as e -> Attributes.pp_error ppf e

let fail e = Err.fail ~pos:__POS__ ~pp_error e

(* {1 Shape of the file} *)

type request = { name : string; perms : perms; init_size : int64; zero_fill : int64; align : int64 }
type shape = { mapped_headers : bool; gnu_stack : bool; segments : int }

let attribute_segment (t : Target.t) =
  match t.attributes with Some { segment_type = Some ty; _ } -> Some ty | _ -> None

let phdr_count t s =
  s.segments
  + (if s.mapped_headers then 2 else 0)
  + (if s.gnu_stack then 1 else 0)
  + if attribute_segment t <> None then 1 else 0

let headers_size (t : Target.t) s =
  Int64.of_int (Codec.ehdr_size t.elf_class + (phdr_count t s * Codec.phdr_size t.elf_class))

(* {1 Geometry} *)

let two_32 = 0x1_0000_0000L
let size_of : content -> int64 = function Bytes b -> Int64.of_int (String.length b) | Zero n -> n

(* Total size of a segment's sections, saturating; for diagnostics only. *)
let total_size (seg : segment) =
  List.fold_left
    (fun acc (s : section) -> Option.value (U64.add acc (size_of s.content)) ~default:(-1L))
    0L seg.sections

let section_end (s : section) = U64.add s.addr (size_of s.content)

(* The addresses a segment spans. [None] when a section end overflows or the sections are not
   ascending; the checks that detect those problems report them separately. *)
type extent = { vaddr : int64; filesz : int64; memsz : int64; align : int64 }

let extent ~page (seg : segment) =
  match seg.sections with
  | [] -> None
  | first :: _ -> (
      let rec ends last_end last_data = function
        | [] -> Some (last_end, last_data)
        | (s : section) :: rest -> (
            match section_end s with
            | None -> None
            | Some e ->
                let last_data = match s.content with Bytes _ -> e | Zero _ -> last_data in
                ends e last_data rest)
      in
      match ends first.addr first.addr seg.sections with
      | None -> None
      | Some (last_end, last_data) -> (
          match (U64.sub last_end first.addr, U64.sub last_data first.addr) with
          | Some memsz, Some filesz ->
              let align =
                List.fold_left (fun a (s : section) -> U64.max a s.align) page seg.sections
              in
              Some { vaddr = first.addr; filesz; memsz; align }
          | _ -> None))

let fits_class (t : Target.t) ~start ~length =
  match U64.add start length with
  | None -> false
  | Some stop -> (
      match t.elf_class with Elf32 -> U64.le stop two_32 && U64.lt start two_32 | Elf64 -> true)

(* Page range occupied by [start, start + length); empty ranges occupy nothing. *)
let pages ~page ~start ~length =
  if length = 0L then None
  else
    let stop = match U64.add start length with Some s -> s | None -> -1L in
    let hi = match U64.align_up stop page with Some a -> a | None -> -1L in
    Some (U64.align_down start page, hi)

(* {1 Validation} *)

type load = { index : int; seg : segment; ext : extent; paddr : int64 }

type layout = {
  spec : spec;
  loads : load list;  (** sorted by [vaddr] *)
  shape : shape;
  hsize : int64;
}

let is_pow2 = U64.is_pow2

let segment_checks (t : Target.t) i seg =
  let page = t.max_page_size in
  let checks = ref [] in
  let add f = checks := f :: !checks in
  if seg.sections = [] then add (fun () -> fail (`Empty_segment i));
  List.iter
    (fun (s : section) ->
      if not (is_pow2 s.align) then
        add (fun () -> fail (`Bad_alignment { section = s.name; align = s.align }))
      else if not (U64.is_aligned s.addr s.align) then
        add (fun () ->
            fail (`Section_misaligned { section = s.name; addr = s.addr; align = s.align })))
    seg.sections;
  (* Ascending, non-overlapping. *)
  let rec pairs = function
    | a :: (b :: _ as rest) ->
        (match section_end a with
        | Some e when U64.le e b.addr -> ()
        | _ ->
            add (fun () ->
                fail (`Sections_overlap { segment = i; first = a.name; second = b.name })));
        pairs rest
    | _ -> ()
  in
  pairs seg.sections;
  (* No initialized data after zero fill. *)
  ignore
    (List.fold_left
       (fun seen_zero (s : section) ->
         match s.content with
         | Zero _ -> true
         | Bytes _ ->
             if seen_zero then
               add (fun () -> fail (`Data_after_zero_fill { segment = i; section = s.name }));
             seen_zero)
       false seg.sections);
  (* Ranges must fit the class. *)
  (match extent ~page seg with
  | None -> (
      (* An overflowing section end is the one way a non-empty segment has no extent. *)
      match seg.sections with
      | [] -> ()
      | first :: _ ->
          let overflow = List.exists (fun s -> section_end s = None) seg.sections in
          if overflow then
            add (fun () ->
                fail
                  (`Range_exceeds_class
                     { range = `Vaddr i; start = first.addr; length = total_size seg })))
  | Some e -> (
      if not (fits_class t ~start:e.vaddr ~length:e.memsz) then
        add (fun () ->
            fail (`Range_exceeds_class { range = `Vaddr i; start = e.vaddr; length = e.memsz }));
      match seg.paddr with
      | Some p when not (fits_class t ~start:p ~length:e.memsz) ->
          add (fun () ->
              fail (`Range_exceeds_class { range = `Paddr i; start = p; length = e.memsz }))
      | _ -> ()));
  List.rev !checks

let header_name_checks (spec : spec) =
  let checks = ref [] in
  let add f = checks := f :: !checks in
  let all_sections = List.concat_map (fun s -> s.sections) spec.segments in
  let section_names = Hashtbl.create 64 in
  List.iter (fun (s : section) -> Hashtbl.replace section_names s.name ()) all_sections;
  List.iter
    (fun (s : section) ->
      if String.contains s.name '\000' then
        add (fun () -> fail (`Bad_name { kind = `Section; name = s.name })))
    all_sections;
  (* Names the builder emits itself cannot be reused. *)
  let reserved =
    if spec.section_headers then
      [ ".symtab"; ".strtab"; ".shstrtab" ]
      @ match spec.target.attributes with Some a -> [ a.section_name ] | None -> []
    else []
  in
  let seen = Hashtbl.create 64 in
  List.iter (fun n -> Hashtbl.replace seen n ()) reserved;
  List.iter
    (fun (s : section) ->
      if Hashtbl.mem seen s.name then add (fun () -> fail (`Duplicate_section s.name))
      else Hashtbl.replace seen s.name ())
    all_sections;
  List.iter
    (fun (y : symbol) ->
      if String.contains y.name '\000' then
        add (fun () -> fail (`Bad_name { kind = `Symbol; name = y.name }));
      match y.section with
      | Some n when not (Hashtbl.mem section_names n) ->
          add (fun () -> fail (`Unknown_symbol_section { symbol = y.name; section = n }))
      | _ -> ())
    spec.symbols;
  if spec.symbols <> [] && not spec.section_headers then
    add (fun () -> fail `Symbols_without_sections);
  List.rev !checks

let cross_checks ?ram (spec : spec) shape hsize loads =
  let t = spec.target in
  let page = t.max_page_size in
  let checks = ref [] in
  let add f = checks := f :: !checks in
  if not (is_pow2 page) then add (fun () -> fail (`Bad_page_size page));
  let usable = is_pow2 page in
  (* The headers are a region like any segment. *)
  let header_region =
    match spec.headers with
    | Unmapped -> None
    | Mapped { vaddr; paddr } ->
        if usable && not (U64.is_aligned vaddr page) then
          add (fun () -> fail (`Headers_misaligned { vaddr; page }));
        if not (fits_class t ~start:vaddr ~length:hsize) then
          add (fun () ->
              fail (`Range_exceeds_class { range = `Headers_vaddr; start = vaddr; length = hsize }));
        let paddr = Option.value paddr ~default:vaddr in
        (match spec.headers with
        | Mapped { paddr = Some p; _ } when not (fits_class t ~start:p ~length:hsize) ->
            add (fun () ->
                fail (`Range_exceeds_class { range = `Headers_paddr; start = p; length = hsize }))
        | _ -> ());
        Some (vaddr, paddr)
  in
  let regions =
    (match header_region with Some (v, p) -> [ (`Headers, v, p, hsize) ] | None -> [])
    @ map (fun l -> (`Segment l.index, l.ext.vaddr, l.paddr, l.ext.memsz)) loads
  in
  (* Pages: sort by start, and compare each region with the furthest one so far. *)
  if usable then begin
    let spans =
      List.filter_map
        (fun (r, v, _, len) ->
          Option.map (fun (lo, hi) -> (r, lo, hi)) (pages ~page ~start:v ~length:len))
        regions
    in
    let sorted = List.stable_sort (fun (_, a, _) (_, b, _) -> U64.compare a b) spans in
    ignore
      (List.fold_left
         (fun far (r, lo, hi) ->
           (match far with
           | Some (fr, fhi) when U64.lt lo fhi ->
               add (fun () -> fail (`Segments_share_page { first = fr; second = r; page = lo }))
           | _ -> ());
           match far with Some (_, fhi) when U64.le hi fhi -> far | _ -> Some (r, hi))
         None sorted)
  end;
  (* Physical ranges overlap exactly, not by page: sort by start and compare each region with the
     furthest-reaching one so far. *)
  let physical =
    List.stable_sort
      (fun (_, a, _) (_, b, _) -> U64.compare a b)
      (List.filter_map
         (fun (r, _, p, len) ->
           if len = 0L then None
           else Some (r, p, match U64.add p len with Some e -> e | None -> -1L))
         regions)
  in
  ignore
    (List.fold_left
       (fun far (r, lo, hi) ->
         (match far with
         | Some (fr, fhi) when U64.lt lo fhi ->
             add (fun () -> fail (`Physical_overlap { first = fr; second = r }))
         | _ -> ());
         match far with Some (_, fhi) when U64.le hi fhi -> far | _ -> Some (r, hi))
       None physical);
  (* Under a system profile, everything must be loadable into RAM. *)
  (match ram with
  | None -> ()
  | Some r ->
      List.iter
        (fun (where, _, paddr, length) ->
          let inside =
            length = 0L
            || U64.le r.ram_start paddr
               &&
               match (U64.add paddr length, U64.add r.ram_start r.ram_size) with
               | Some stop, Some ram_stop -> U64.le stop ram_stop
               | _ -> false
          in
          if not inside then add (fun () -> fail (`Outside_ram { where; paddr; length; ram = r })))
        regions);
  (* The entry must be code that is present in the file. *)
  let executable =
    List.exists
      (fun l ->
        l.seg.perms.execute && U64.le l.ext.vaddr spec.entry
        && U64.lt spec.entry (Option.value (U64.add l.ext.vaddr l.ext.filesz) ~default:(-1L)))
      loads
  in
  if not executable then add (fun () -> fail (`Entry_not_executable spec.entry));
  ignore shape;
  List.rev !checks

let riscv_virt_ram = { ram_start = 0x8000_0000L; ram_size = 0x800_0000L }

let validate ?ram (spec : spec) =
  let t = spec.target in
  let page = t.max_page_size in
  let shape =
    {
      mapped_headers = spec.headers <> Unmapped;
      gnu_stack = spec.gnu_stack <> None;
      segments = List.length spec.segments;
    }
  in
  let hsize = headers_size t shape in
  let indexed = mapi (fun i s -> (i, s)) spec.segments in
  let loads =
    List.filter_map
      (fun (index, seg) ->
        Option.map
          (fun ext -> { index; seg; ext; paddr = Option.value seg.paddr ~default:ext.vaddr })
          (extent ~page seg))
      indexed
  in
  let sorted = List.stable_sort (fun a b -> U64.compare a.ext.vaddr b.ext.vaddr) loads in
  let checks =
    List.concat_map (fun (i, seg) -> segment_checks t i seg) indexed
    @ cross_checks ?ram spec shape hsize sorted
    @ header_name_checks spec
  in
  let r = Err.Accum.iter (fun f -> f ()) checks in
  match Err.Accum.fold_errors (fun errs -> map Err.Error.kind errs) r with
  | Ok () -> Ok { spec; loads = sorted; shape; hsize }
  | Error e -> Error e

(* {1 Placement} *)

let place (t : Target.t) ~mapped_headers ~gnu_stack ~base requests =
  let page = t.max_page_size in
  let shape = { mapped_headers; gnu_stack; segments = List.length requests } in
  let range_error i start length =
    fail (`Range_exceeds_class { range = `Vaddr i; start; length })
  in
  let* () =
    if is_pow2 page && U64.is_aligned base page then Ok ()
    else if not (is_pow2 page) then fail (`Bad_page_size page)
    else fail (`Headers_misaligned { vaddr = base; page })
  in
  let* cursor, headers =
    if mapped_headers then
      let size = headers_size t shape in
      match U64.add base size with
      | None -> range_error 0 base size
      | Some stop -> (
          match U64.align_up stop page with
          | None -> range_error 0 base size
          | Some c -> Ok (c, Mapped { vaddr = base; paddr = None }))
    else Ok (base, Unmapped)
  in
  let rec go i cursor acc = function
    | [] -> Ok (List.rev acc)
    | (r : request) :: rest -> (
        if not (is_pow2 r.align) then fail (`Bad_alignment { section = r.name; align = r.align })
        else
          let size = U64.add r.init_size r.zero_fill in
          let place =
            match size with
            | None -> None
            | Some size ->
                Option.bind
                  (U64.align_up cursor (U64.max page r.align))
                  (fun vaddr ->
                    Option.bind (U64.add vaddr size) (fun stop ->
                        Option.map (fun next -> (vaddr, size, next)) (U64.align_up stop page)))
          in
          match place with
          | None -> range_error i cursor (Option.value size ~default:(-1L))
          | Some (vaddr, size, next) ->
              if fits_class t ~start:vaddr ~length:size then
                go (i + 1) next ((r.name, vaddr) :: acc) rest
              else range_error i vaddr size)
  in
  let+ addrs = go 0 cursor [] requests in
  (headers, addrs)

(* {1 Building} *)

let lift r = (r :> (_, error) Err.t)

let perm_flags (p : perms) =
  List.fold_left Int64.logor 0L
    [
      (if p.read then Const.pf_r else 0L);
      (if p.write then Const.pf_w else 0L);
      (if p.execute then Const.pf_x else 0L);
    ]

let section_flags (p : perms) =
  List.fold_left Int64.logor Const.shf_alloc
    [ (if p.write then Const.shf_write else 0L); (if p.execute then Const.shf_execinstr else 0L) ]

type built_section = {
  b_name : string;
  b_type : int64;
  b_flags : int64;
  b_addr : int64;
  b_offset : int64;
  b_size : int64;
  b_link : int64;
  b_info : int64;
  b_align : int64;
  b_entsize : int64;
}

let assemble l =
  let spec = l.spec in
  let t = spec.target in
  let cls = t.elf_class and endian = t.endianness in
  let ident = Target.ident t in
  let word = Int64.of_int (Codec.word_size cls) in
  let page = t.max_page_size in
  let ehsize = Codec.ehdr_size cls and phentsize = Codec.phdr_size cls in
  let shentsize = Codec.shdr_size cls in
  let phnum = phdr_count t l.shape in
  Err.Escape.with_escape (fun esc ->
      let get r = Err.Escape.or_throw esc (lift r) in
      let too_large n = Err.Escape.throw esc ~pos:__POS__ ~pp_error (`File_too_large n) in
      let add a b = match U64.add a b with Some v -> v | None -> too_large (-1L) in
      let align_up v a = match U64.align_up v a with Some v -> v | None -> too_large (-1L) in
      (* Loadable segments in file order: each starts at the lowest offset >= the current end that
         is congruent to its address modulo its alignment. A segment with no file bytes takes the
         highest congruent offset <= the current end, so it never points past the file. *)
      let off = ref (Int64.of_int (ehsize + (phnum * phentsize))) in
      let placed =
        map
          (fun ld ->
            let a = ld.ext.align in
            let r = U64.rem ld.ext.vaddr a in
            let cand = add (U64.align_down !off a) r in
            let p_offset =
              if ld.ext.filesz <> 0L then if U64.lt cand !off then add cand a else cand
              else if U64.le cand !off then cand
              else if U64.le a (U64.align_down !off a) then Int64.sub cand a
              else cand
            in
            off := if ld.ext.filesz <> 0L then add p_offset ld.ext.filesz else U64.max !off p_offset;
            (ld, p_offset))
          l.loads
      in
      let attr_data =
        match t.attributes with
        | None -> None
        | Some a -> Some (a, get (Attributes.encode endian a.contents))
      in
      let attr_off = !off in
      (match attr_data with
      | Some (_, d) -> off := add !off (Int64.of_int (String.length d))
      | None -> ());
      (* Section table. *)
      let spec_sections =
        List.concat_map
          (fun (ld, p_offset) ->
            map
              (fun (s : section) ->
                let file_off = add p_offset (Int64.sub s.addr ld.ext.vaddr) in
                {
                  b_name = s.name;
                  b_type =
                    (match s.content with
                    | Bytes _ -> Const.sht_progbits
                    | Zero _ -> Const.sht_nobits);
                  b_flags = section_flags ld.seg.perms;
                  b_addr = s.addr;
                  b_offset = file_off;
                  b_size = size_of s.content;
                  b_link = 0L;
                  b_info = 0L;
                  b_align = s.align;
                  b_entsize = 0L;
                })
              ld.seg.sections)
          placed
      in
      let attr_section =
        match attr_data with
        | Some (a, d) when spec.section_headers ->
            [
              {
                b_name = a.section_name;
                b_type = a.section_type;
                b_flags = 0L;
                b_addr = 0L;
                b_offset = attr_off;
                b_size = Int64.of_int (String.length d);
                b_link = 0L;
                b_info = 0L;
                b_align = 1L;
                b_entsize = 0L;
              };
            ]
        | _ -> []
      in
      let fixed_sections = spec_sections @ attr_section in
      let section_index = Hashtbl.create 64 in
      List.iteri
        (fun i (s : built_section) ->
          if not (Hashtbl.mem section_index s.b_name) then Hashtbl.add section_index s.b_name (i + 1))
        fixed_sections;
      let index_of name = Hashtbl.find_opt section_index name in
      let symtab_index = List.length fixed_sections + 1 in
      let strtab_index = symtab_index + 1 and shstrtab_index = symtab_index + 2 in
      let shnum = if spec.section_headers then shstrtab_index + 1 else 0 in
      (* Symbols: locals first. *)
      let strtab = Strtab.create () in
      let symbols_bytes, first_global =
        if not spec.section_headers then ("", 0)
        else begin
          let local, other = List.partition (fun (y : symbol) -> y.binding = `Local) spec.symbols in
          let ordered = local @ other in
          let b = Bytes.make ((1 + List.length ordered) * Codec.sym_size cls) '\000' in
          List.iteri
            (fun i (y : symbol) ->
              let index = i + 1 in
              let shndx =
                match y.section with
                | None -> Const.shn_abs
                | Some n -> (
                    match index_of n with
                    | Some ix ->
                        if ix >= Const.shn_loreserve then
                          get
                            (Err.fail ~pos:__POS__ ~pp_error
                               (`Unsupported_symbol_section_index { symbol = y.name; index = ix }))
                        else ix
                    | None -> assert false (* validate rejects unknown symbol sections *))
              in
              let st_name = get (Strtab.add strtab y.name) in
              let typ =
                match y.kind with
                | `Notype -> Const.stt_notype
                | `Object -> Const.stt_object
                | `Func -> Const.stt_func
              in
              let bind =
                match y.binding with
                | `Local -> Const.stb_local
                | `Global -> Const.stb_global
                | `Weak -> Const.stb_weak
              in
              get
                (Encode.write_sym ident b
                   (index * Codec.sym_size cls)
                   ~index
                   {
                     st_name;
                     st_info = st_info ~bind ~typ;
                     st_other = 0;
                     st_shndx = shndx;
                     st_value = y.value;
                     st_size = y.size;
                   }))
            ordered;
          (Bytes.to_string b, 1 + List.length local)
        end
      in
      let symtab_off = align_up !off word in
      off := add symtab_off (Int64.of_int (String.length symbols_bytes));
      let strtab_data = Strtab.contents strtab in
      let strtab_off = !off in
      off := add !off (Int64.of_int (String.length strtab_data));
      (* Section names. *)
      let shstrtab = Strtab.create () in
      let all_names =
        map (fun s -> s.b_name) fixed_sections @ [ ".symtab"; ".strtab"; ".shstrtab" ]
      in
      let name_offsets = map (fun n -> get (Strtab.add shstrtab n)) all_names in
      let shstrtab_data = Strtab.contents shstrtab in
      let shstrtab_off = !off in
      off := add !off (Int64.of_int (String.length shstrtab_data));
      let shoff = if spec.section_headers then align_up !off word else 0L in
      let total =
        if spec.section_headers then add shoff (Int64.of_int (shnum * shentsize)) else !off
      in
      (* Files are built in memory; refuse what Bytes cannot hold, and anything over 2 GiB. *)
      let total_int =
        match U64.to_int total with
        | Some n when n <= Sys.max_string_length && U64.le total 0x7fff_ffffL -> n
        | _ -> too_large total
      in
      let b = Bytes.make total_int '\000' in
      let int v = match U64.to_int v with Some n -> n | None -> too_large v in
      (* Payloads. *)
      List.iter
        (fun (ld, p_offset) ->
          List.iter
            (fun (s : section) ->
              match s.content with
              | Bytes data ->
                  Bytes.blit_string data 0 b
                    (int (add p_offset (Int64.sub s.addr ld.ext.vaddr)))
                    (String.length data)
              | Zero _ -> ())
            ld.seg.sections)
        placed;
      (match attr_data with
      | Some (_, d) -> Bytes.blit_string d 0 b (int attr_off) (String.length d)
      | None -> ());
      Bytes.blit_string symbols_bytes 0 b (int symtab_off) (String.length symbols_bytes);
      Bytes.blit_string strtab_data 0 b (int strtab_off) (String.length strtab_data);
      Bytes.blit_string shstrtab_data 0 b (int shstrtab_off) (String.length shstrtab_data);
      (* Section headers. *)
      let extended_shnum = shnum >= Const.shn_loreserve in
      let extended_shstrndx = shstrtab_index >= Const.shn_loreserve in
      let extended_phnum = phnum >= Const.pn_xnum in
      if spec.section_headers then begin
        let put index (s : built_section) name =
          get
            (Encode.write_shdr ident b
               (int shoff + (index * shentsize))
               ~index
               {
                 sh_name = name;
                 sh_type = s.b_type;
                 sh_flags = s.b_flags;
                 sh_addr = s.b_addr;
                 sh_offset = s.b_offset;
                 sh_size = s.b_size;
                 sh_link = s.b_link;
                 sh_info = s.b_info;
                 sh_addralign = s.b_align;
                 sh_entsize = s.b_entsize;
               })
        in
        let null =
          {
            b_name = "";
            b_type = Const.sht_null;
            b_flags = 0L;
            b_addr = 0L;
            b_offset = 0L;
            b_size = (if extended_shnum then Int64.of_int shnum else 0L);
            b_link = (if extended_shstrndx then Int64.of_int shstrtab_index else 0L);
            b_info = (if extended_phnum then Int64.of_int phnum else 0L);
            b_align = 0L;
            b_entsize = 0L;
          }
        in
        put 0 null 0L;
        let names = ref name_offsets in
        let next_name () =
          match !names with
          | n :: rest ->
              names := rest;
              n
          | [] -> assert false
        in
        List.iteri (fun i s -> put (i + 1) s (next_name ())) fixed_sections;
        put symtab_index
          {
            b_name = ".symtab";
            b_type = Const.sht_symtab;
            b_flags = 0L;
            b_addr = 0L;
            b_offset = symtab_off;
            b_size = Int64.of_int (String.length symbols_bytes);
            b_link = Int64.of_int strtab_index;
            b_info = Int64.of_int first_global;
            b_align = word;
            b_entsize = Int64.of_int (Codec.sym_size cls);
          }
          (next_name ());
        put strtab_index
          {
            b_name = ".strtab";
            b_type = Const.sht_strtab;
            b_flags = 0L;
            b_addr = 0L;
            b_offset = strtab_off;
            b_size = Int64.of_int (String.length strtab_data);
            b_link = 0L;
            b_info = 0L;
            b_align = 1L;
            b_entsize = 0L;
          }
          (next_name ());
        put shstrtab_index
          {
            b_name = ".shstrtab";
            b_type = Const.sht_strtab;
            b_flags = 0L;
            b_addr = 0L;
            b_offset = shstrtab_off;
            b_size = Int64.of_int (String.length shstrtab_data);
            b_link = 0L;
            b_info = 0L;
            b_align = 1L;
            b_entsize = 0L;
          }
          (next_name ())
      end
      else if extended_phnum then
        get
          (Err.fail ~pos:__POS__ ~pp_error
             (`Field_overflow
                {
                  Encode.record = `Header;
                  field = "e_phnum";
                  value = Int64.of_int phnum;
                  bits = 16;
                  signed = false;
                }));
      (* Program headers: PT_PHDR, the PT_LOADs by address (headers included), PT_GNU_STACK, then
         the attribute segment. *)
      let phdr p_type p_flags p_offset p_vaddr p_paddr p_filesz p_memsz p_align =
        { p_type; p_flags; p_offset; p_vaddr; p_paddr; p_filesz; p_memsz; p_align }
      in
      let load_of (ld, p_offset) =
        ( ld.ext.vaddr,
          phdr Const.pt_load (perm_flags ld.seg.perms) p_offset ld.ext.vaddr ld.paddr ld.ext.filesz
            ld.ext.memsz ld.ext.align )
      in
      let header_phdrs, header_loads =
        match spec.headers with
        | Unmapped -> ([], [])
        | Mapped { vaddr; paddr } ->
            let paddr = Option.value paddr ~default:vaddr in
            let phsize = Int64.of_int (phnum * phentsize) in
            let eh = Int64.of_int ehsize in
            ( [ phdr Const.pt_phdr Const.pf_r eh (add vaddr eh) (add paddr eh) phsize phsize word ],
              [ (vaddr, phdr Const.pt_load Const.pf_r 0L vaddr paddr l.hsize l.hsize page) ] )
      in
      let loads =
        List.stable_sort (fun (a, _) (b, _) -> U64.compare a b) (header_loads @ map load_of placed)
      in
      let stack =
        match spec.gnu_stack with
        | None -> []
        | Some p -> [ phdr Const.pt_gnu_stack (perm_flags p) 0L 0L 0L 0L 0L 16L ]
      in
      let attribute =
        match (attr_data, attribute_segment t) with
        | Some (_, d), Some ty ->
            let n = Int64.of_int (String.length d) in
            [ phdr ty Const.pf_r attr_off 0L 0L n n 1L ]
        | _ -> []
      in
      let all_phdrs = header_phdrs @ map snd loads @ stack @ attribute in
      assert (List.length all_phdrs = phnum);
      List.iteri
        (fun index p -> get (Encode.write_phdr ident b (ehsize + (index * phentsize)) ~index p))
        all_phdrs;
      get
        (Encode.write_header b
           {
             ident;
             e_type = Const.et_exec;
             e_machine = t.machine;
             e_version = Int64.of_int Const.ev_current;
             e_entry = spec.entry;
             e_phoff = (if phnum = 0 then 0L else Int64.of_int ehsize);
             e_shoff = shoff;
             e_flags = t.flags;
             e_ehsize = ehsize;
             e_phentsize = phentsize;
             e_phnum = (if extended_phnum && spec.section_headers then Const.pn_xnum else phnum);
             e_shentsize = shentsize;
             e_shnum = (if extended_shnum then 0 else shnum);
             e_shstrndx =
               (if not spec.section_headers then 0
                else if extended_shstrndx then Const.shn_xindex
                else shstrtab_index);
           });
      Bytes.to_string b)

let build ?ram spec =
  match
    Err.map_error ~pos:__POS__ ~pp_error
      (fun errs -> (`Invalid_spec errs : error))
      (validate ?ram spec)
  with
  | Error _ as e -> e
  | Ok l -> assemble l
