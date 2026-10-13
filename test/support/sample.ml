open Elf
open Exec

let text_size = 16
let rodata_size = 8
let data_init = 0x100
let data_zero = 0x3000L
let bss_size = 0x2000L
let ro = { read = true; write = false; execute = false }
let rx = { read = true; write = false; execute = true }
let rw = { read = true; write = true; execute = false }

let addr ?(base = 0x40_0000L) name =
  let at k = Int64.add base (Int64.mul 0x10000L (Int64.of_int k)) in
  match name with
  | ".text" -> at 1
  | ".text.aux" -> at 2
  | ".rodata" -> at 3
  | ".data" -> at 4
  | ".bss.data" -> Int64.add (at 4) (Int64.of_int data_init)
  | ".bss" -> at 5
  | _ -> invalid_arg name

let spec ?(base = 0x40_0000L) ?(sections = true) ?symbols target =
  let symbols = Option.value symbols ~default:sections in
  let a = addr ~base in
  let section name align content = { name; addr = a name; align; content } in
  {
    target;
    entry = a ".text";
    headers = Mapped { vaddr = base; paddr = None };
    gnu_stack = Some rw;
    section_headers = sections;
    segments =
      [
        {
          perms = rx;
          paddr = None;
          sections = [ section ".text" 4L (Bytes (String.make text_size '\x01')) ];
        };
        {
          perms = rx;
          paddr = None;
          sections = [ section ".text.aux" 4L (Bytes "\x02\x02\x02\x02") ];
        };
        {
          perms = ro;
          paddr = None;
          sections = [ section ".rodata" 4L (Bytes "\x78\x56\x34\x12\000\000\000\000") ];
        };
        {
          perms = rw;
          paddr = None;
          sections =
            [
              section ".data" 4L (Bytes (String.init data_init (fun i -> Char.chr (i land 0xff))));
              section ".bss.data" 4L (Zero data_zero);
            ];
        };
        { perms = rw; paddr = None; sections = [ section ".bss" 4L (Zero bss_size) ] };
      ];
    symbols =
      (if symbols then
         [
           {
             name = "_start";
             value = a ".text";
             size = 16L;
             kind = `Func;
             binding = `Global;
             section = Some ".text";
           };
           {
             name = "aux";
             value = a ".text.aux";
             size = 4L;
             kind = `Func;
             binding = `Local;
             section = Some ".text.aux";
           };
           {
             name = "marker";
             value = a ".rodata";
             size = 4L;
             kind = `Object;
             binding = `Global;
             section = Some ".rodata";
           };
           {
             name = "abs_one";
             value = 1L;
             size = 0L;
             kind = `Notype;
             binding = `Weak;
             section = None;
           };
         ]
       else []);
  }
