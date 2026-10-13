(** Build-attribute sections (format version ['A']), as used by [.riscv.attributes] and
    [.ARM.attributes].

    A section is a version byte followed by vendor subsections; each subsection is a [u32] length
    (counting itself), the vendor name as a NUL-terminated string, and, for vendors whose tag
    layout is known, scoped groups of [(tag, value)] attributes. A subsection of any other vendor
    is kept as [`Raw] bytes so decoding and encoding it again changes nothing. *)

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
    (** a ULEB128 wider than 64 bits, or a tag that is not a native int; offset *)
  | `Unterminated_ntbs of int  (** offset of the string *)
  | `Nul_in_value of string  (** encoding: a string value or vendor name contains NUL *)
  | `Unknown_scope of int
  | `Bad_value_kind of kind_error
    (** encoding: the value's form does not match what the vendor defines for the tag *)
  | `Unknown_vendor of string
    (** encoding: [`Parsed] contents for a vendor whose tag layout is not known *)
  | `Bad_tag of int  (** encoding: a negative tag *)
  | `Bad_index of int  (** encoding: a section or symbol index that is not positive *) ]

val pp_error : Format.formatter -> error -> unit

val classify : vendor:string -> tag:int -> [ `Uleb | `Ntbs | `Uleb_ntbs ] option
(** The value form a vendor defines for a tag: [riscv] has ULEB for even tags and NTBS for odd
    ones; [aeabi] has NTBS for tags 4, 5 and 67, ULEB+NTBS for 32, ULEB for other tags below 32,
    and above 32 NTBS for odd and ULEB for even tags. [None] for any other vendor. *)

val decode : Types.endianness -> string -> (t, error) Err.t
val encode : Types.endianness -> t -> (string, error) Err.t

val find : t -> vendor:string -> tag:int -> value option
(** The first File-scope attribute with this tag in the first [`Parsed] subsection of [vendor]
    that has one. *)
