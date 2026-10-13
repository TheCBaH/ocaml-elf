type arch = Elf.Target.arch

type tools = {
  as_ : string list;
  ld : string list;
  objdump : string;
  readelf : string;
  qemu_user : string;
  qemu_system : string option;
}

let quote = Filename.quote
let have prog = Sys.command ("command -v " ^ quote prog ^ " >/dev/null 2>&1") = 0

let read_file path =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let run argv =
  let out = Filename.temp_file "elf_gnu" ".out" and err = Filename.temp_file "elf_gnu" ".err" in
  let cmd = String.concat " " (List.map quote argv) ^ " >" ^ quote out ^ " 2>" ^ quote err in
  let status = Sys.command cmd in
  let stdout = read_file out and stderr = read_file err in
  Sys.remove out;
  Sys.remove err;
  (status, stdout, stderr)

let spec (arch : arch) =
  let gnu prefix ~as_flags ~ld_flags ~qemu ~system =
    {
      as_ = (prefix ^ "as") :: as_flags;
      ld = (prefix ^ "ld") :: ld_flags;
      objdump = prefix ^ "objdump";
      readelf = prefix ^ "readelf";
      qemu_user = qemu;
      qemu_system = system;
    }
  in
  match arch with
  | X86_32 ->
      gnu "i686-linux-gnu-" ~as_flags:[ "--32" ] ~ld_flags:[ "-m"; "elf_i386" ] ~qemu:"qemu-i386"
        ~system:(Some "qemu-system-i386")
  | X86_64 ->
      gnu "x86_64-linux-gnu-" ~as_flags:[ "--64" ] ~ld_flags:[ "-m"; "elf_x86_64" ]
        ~qemu:"qemu-x86_64" ~system:(Some "qemu-system-x86_64")
  | Arm ->
      gnu "arm-linux-gnueabihf-" ~as_flags:[ "-march=armv7-a" ] ~ld_flags:[] ~qemu:"qemu-arm"
        ~system:(Some "qemu-system-arm")
  | Aarch64 ->
      gnu "aarch64-linux-gnu-" ~as_flags:[] ~ld_flags:[] ~qemu:"qemu-aarch64"
        ~system:(Some "qemu-system-aarch64")
  | Riscv32 ->
      gnu "riscv64-linux-gnu-"
        ~as_flags:[ "-march=rv32imafd"; "-mabi=ilp32d" ]
        ~ld_flags:[ "-m"; "elf32lriscv" ] ~qemu:"qemu-riscv32" ~system:(Some "qemu-system-riscv32")
  | Riscv64 ->
      gnu "riscv64-linux-gnu-"
        ~as_flags:[ "-march=rv64imafd"; "-mabi=lp64d" ]
        ~ld_flags:[ "-m"; "elf64lriscv" ] ~qemu:"qemu-riscv64" ~system:(Some "qemu-system-riscv64")

let find arch =
  let t = spec arch in
  let needed = [ List.hd t.as_; List.hd t.ld; t.objdump; t.readelf ] in
  match List.find_opt (fun p -> not (have p)) needed with
  | Some p -> Error (`Missing p)
  | None -> Ok t

let skip_or_fail tool =
  if Sys.getenv_opt "ELF_REQUIRE_TOOLCHAIN" = Some "1" then (
    Printf.printf "MISSING %s\n%!" tool;
    exit 1)
  else Printf.printf "SKIP %s\n%!" tool

let artifacts name =
  let dir = "gnu-artifacts" in
  if not (Sys.file_exists dir) then Sys.mkdir dir 0o755;
  let d = Filename.concat dir name in
  if not (Sys.file_exists d) then Sys.mkdir d 0o755;
  d
