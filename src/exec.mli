(** Static [ET_EXEC] executables from caller-chosen addresses.

    A {!spec} says exactly where every section lives; {!build} never moves anything. A segment is
    a run of sections at fixed addresses: its [vaddr] is the first section's address, its [filesz]
    runs to the end of the last [Bytes] section (gaps are zero-filled in the file) and its [memsz]
    to the end of the last section, so [filesz <= memsz] holds by construction.

    [paddr] defaults to [vaddr]. The two are distinct everywhere; the execution profile decides
    what [paddr] means. *)

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
  section : string option;  (** [None]: [SHN_ABS] *)
}

type spec = {
  target : Target.t;
  entry : int64;  (** required: there is no silent zero *)
  segments : segment list;
  headers : headers;  (** [Mapped] adds a read-only [PT_LOAD] over the headers and a [PT_PHDR] *)
  gnu_stack : perms option;  (** [PT_GNU_STACK] *)
  section_headers : bool;
  symbols : symbol list;  (** need [section_headers = true] *)
}

(** {1 Errors} *)

type region = [ `Headers | `Segment of int ]
type bad_alignment = { section : string; align : int64 }
type misaligned = { section : string; addr : int64; align : int64 }
type overlap = { segment : int; first : string; second : string }
type after_zero_fill = { segment : int; section : string }

type range_of = [ `Vaddr of int | `Paddr of int | `Headers_vaddr | `Headers_paddr ]
(** Which range failed: the virtual or physical range of a segment, or of the headers. *)

type range = { range : range_of; start : int64; length : int64 }
type shared_page = { first : region; second : region; page : int64 }
type physical_overlap = { first : region; second : region }
type misaligned_headers = { vaddr : int64; page : int64 }

type ram = { ram_start : int64; ram_size : int64 }
(** A physical RAM window. Under a system profile every segment and the mapped headers must lie
    inside it. *)

type outside_ram = { where : region; paddr : int64; length : int64; ram : ram }
type name_kind = [ `Section | `Symbol ]
type bad_name = { kind : name_kind; name : string }
type symbol_section = { symbol : string; section : string }
type symbol_index = { symbol : string; index : int }

type error =
  [ `Bad_alignment of bad_alignment  (** a section alignment is not a power of two *)
  | `Bad_page_size of int64  (** [max_page_size] is not a power of two *)
  | `Section_misaligned of misaligned  (** [addr mod align <> 0] *)
  | `Empty_segment of int
  | `Sections_overlap of overlap  (** out of order, or overlapping, within one segment *)
  | `Data_after_zero_fill of after_zero_fill  (** a [Bytes] section follows a [Zero] one *)
  | `Range_exceeds_class of range
    (** [start + length] is above 2{^32} for ELF32, or wraps 2{^64} *)
  | `Segments_share_page of shared_page
  | `Physical_overlap of physical_overlap
  | `Headers_misaligned of misaligned_headers
  | `Entry_not_executable of int64
    (** the entry is not inside the initialized part of an executable segment *)
  | `Outside_ram of outside_ram
  | `Duplicate_section of string
  | `Bad_name of bad_name  (** a NUL in a section or symbol name *)
  | `Unknown_symbol_section of symbol_section
  | `Symbols_without_sections
  | `Unsupported_symbol_section_index of symbol_index
    (** the symbol's section index needs [SHT_SYMTAB_SHNDX], which the builder does not write *)
  | `File_too_large of int64  (** the file would be too large to address on this platform *)
  | `Invalid_spec of error list  (** {!build} only: every problem {!validate} found *)
  | Encode.error
  | Strtab.error
  | Attributes.error ]

val pp_error : Format.formatter -> error -> unit

(** {1 Placement}

    {!place} chooses addresses for callers that do not choose their own. It reserves the header
    page at [base] when the headers are mapped, then gives each request a fresh page, in list
    order, aligned to the larger of the page size and the request's alignment. The program-header
    count comes from {!phdr_count}, the function {!build} uses, so the reservation cannot disagree
    with the output. *)

type request = { name : string; perms : perms; init_size : int64; zero_fill : int64; align : int64 }
type shape = { mapped_headers : bool; gnu_stack : bool; segments : int }

val phdr_count : Target.t -> shape -> int
(** [segments], plus 2 for mapped headers ([PT_PHDR] and the header [PT_LOAD]), plus 1 for
    [PT_GNU_STACK], plus 1 when the target has an attribute segment. *)

val headers_size : Target.t -> shape -> int64
(** The ELF header plus the program-header table: [e_ehsize + phnum * e_phentsize]. *)

val place :
  Target.t ->
  mapped_headers:bool ->
  gnu_stack:bool ->
  base:int64 ->
  request list ->
  (headers * (string * int64) list, error) Err.t
(** [base] must be a multiple of the target's page size ([`Headers_misaligned] otherwise). The
    result gives the headers and the address of each request, in request order. *)

(** {1 Validation and building} *)

type layout
(** A validated, normalized spec: segments sorted by address with their computed sizes. *)

val riscv_virt_ram : ram
(** QEMU's RISC-V [virt] machine started with [-m 128M]: [0x8000_0000, +128 MiB). *)

val arm_virt_ram : ram
(** QEMU's ARM and AArch64 [virt] machines with 128 MiB: [0x4000_0000, +128 MiB). QEMU's boot stub
    uses the first bytes, so images load above [0x4010_0000]. *)

val x86_pc_ram : ram
(** QEMU's [pc] machine with 128 MiB, above the legacy hole: [1 MiB, +127 MiB). *)

val validate : ?ram:ram -> spec -> (layout, error list) Err.t
(** Checks the whole spec and reports every problem, in the order: each segment, then the checks
    across segments, then names and symbols. With [ram], every segment's physical range and the
    mapped headers must also lie inside that window ([`Outside_ram]); [paddr] is the load address,
    so it is the [paddr] that is checked. *)

val build : ?ram:ram -> spec -> (string, error) Err.t
(** The ELF file. A spec that fails {!validate} gives [`Invalid_spec]. *)
