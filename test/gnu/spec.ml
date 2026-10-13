open Elf

type variant = { base : int64; sections : bool; abi : string }
type kind = [ `User | `System ]
type control = [ `None | `Flip_rodata | `Dirty_zero_fill | `Illegal_instruction ]
type markers = { rodata : int32; data : int32; aux : int32; store : int32 }

type t = {
  arch : Target.arch;
  target : Target.t;
  variant : variant;
  text : int64;
  aux : int64;
  rodata : int64;
  data : int64;
  bss : int64;
  data_init : int;
  data_zero : int64;
  bss_size : int64;
  markers : markers;
  kind : kind;
  control : control;
  stack : int64;
  stack_size : int64;
}

let arch_of (t : Target.t) = t.arch

let make ?(kind = `User) ?(control = `None) target variant =
  let at k = Int64.add variant.base (Int64.mul 0x10000L (Int64.of_int k)) in
  {
    arch = arch_of target;
    target;
    variant;
    text = at 1;
    aux = at 2;
    rodata = at 3;
    data = at 4;
    bss = at 5;
    data_init = 0x100;
    data_zero = 0x3000L;
    bss_size = 0x2000L;
    kind;
    control;
    stack = at 6;
    stack_size = 0x1000L;
    (* Below 0x8000_0000, so a sign-extending 32-bit load cannot change a comparison. *)
    markers =
      { rodata = 0x1234_5678l; data = 0x2badf00dl; aux = 0x0a0b_0c0dl; store = 0x3c3c_3c3cl };
  }

let word endian v =
  let b = Bytes.create 4 in
  (match endian with
  | Types.Little -> Bytes.set_int32_le b 0 v
  | Types.Big -> Bytes.set_int32_be b 0 v);
  Bytes.to_string b

let symbols t ~text ~aux =
  let sym name value size kind section =
    { Exec.name; value; size = Int64.of_int size; kind; binding = `Global; section = Some section }
  in
  [
    sym "_start" t.text (String.length text) `Func ".text";
    sym "aux" t.aux (String.length aux) `Func ".text.aux";
    sym "rodata_marker" t.rodata 4 `Object ".rodata";
    sym "data_marker" t.data 4 `Object ".data";
  ]

let exec_spec t ~text ~aux =
  let control = t.control in
  let endian = t.target.endianness in
  let ro = { Exec.read = true; write = false; execute = false } in
  let rx = { ro with execute = true } in
  let rw = { ro with write = true } in
  let section name addr content = { Exec.name; addr; align = 4L; content } in
  let rodata_marker =
    if control = `Flip_rodata then Int32.logxor t.markers.rodata 0x0100_0000l else t.markers.rodata
  in
  let data = word endian t.markers.data ^ String.make (t.data_init - 4) '\000' in
  let mixed =
    let zero_at = Int64.add t.data (Int64.of_int t.data_init) in
    match control with
    | `Dirty_zero_fill ->
        (* The first word of the zero fill is initialized, non-zero data; the rest stays zero. *)
        [
          section ".data" t.data (Exec.Bytes data);
          section ".bss.dirty" zero_at (Exec.Bytes (word endian 1l));
          section ".bss.data" (Int64.add zero_at 4L) (Exec.Zero (Int64.sub t.data_zero 4L));
        ]
    | _ ->
        [
          section ".data" t.data (Exec.Bytes data);
          section ".bss.data" zero_at (Exec.Zero t.data_zero);
        ]
  in
  let stack_segments =
    match t.kind with
    | `User -> []
    | `System ->
        [
          {
            Exec.perms = rw;
            paddr = None;
            sections = [ section ".stack" t.stack (Exec.Zero t.stack_size) ];
          };
        ]
  in
  let main_segments : Exec.segment list =
    [
      { perms = rx; paddr = None; sections = [ section ".text" t.text (Exec.Bytes text) ] };
      { perms = rx; paddr = None; sections = [ section ".text.aux" t.aux (Exec.Bytes aux) ] };
      {
        perms = ro;
        paddr = None;
        sections =
          [
            section ".rodata" t.rodata (Exec.Bytes (word endian rodata_marker ^ "\000\000\000\000"));
          ];
      };
      { perms = rw; paddr = None; sections = mixed };
      { perms = rw; paddr = None; sections = [ section ".bss" t.bss (Exec.Zero t.bss_size) ] };
    ]
  in
  {
    Exec.target = t.target;
    entry = t.text;
    headers = Exec.Mapped { vaddr = t.variant.base; paddr = None };
    gnu_stack = (match t.kind with `User -> Some rw | `System -> None);
    section_headers = t.variant.sections;
    symbols = (if t.variant.sections then symbols t ~text ~aux else []);
    segments = main_segments @ stack_segments;
  }

let ram t =
  match (t.kind, t.arch) with
  | `System, (Target.Riscv32 | Target.Riscv64) -> Some Exec.riscv_virt_ram
  | _ -> None
