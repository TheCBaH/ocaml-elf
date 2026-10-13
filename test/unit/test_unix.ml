open Elf_test_support

let ok what r = Check.ok ~pp_error:Elf_unix.pp_error what r

let with_temp_dir f =
  let dir = Filename.temp_file "elf_unix" "" in
  Sys.remove dir;
  Sys.mkdir dir 0o755;
  Fun.protect
    ~finally:(fun () ->
      Array.iter (fun n -> Sys.remove (Filename.concat dir n)) (Sys.readdir dir);
      Sys.rmdir dir)
    (fun () -> f dir)

let is_io op (e : Elf_unix.error) = match e with `Io { op = o; _ } -> o = op

let () =
  Check.run "unix"
    [
      Check.case "write then read" (fun () ->
          with_temp_dir (fun dir ->
              let path = Filename.concat dir "f.bin" in
              let data = String.init 256 Char.chr ^ "\000tail" in
              ok "write" (Elf_unix.write_file path data);
              Check.bytes_equal "round trip" data (ok "read" (Elf_unix.read_file path));
              ok "overwrite" (Elf_unix.write_file path "x");
              Check.bytes_equal "truncated" "x" (ok "read" (Elf_unix.read_file path))));
      Check.case "executable bit" (fun () ->
          with_temp_dir (fun dir ->
              let path = Filename.concat dir "prog" in
              ok "write" (Elf_unix.write_executable path "\x7fELF");
              Check.equal ~pp:Format.pp_print_int "mode" 0o755 (Unix.stat path).st_perm;
              let plain = Filename.concat dir "plain" in
              ok "write" (Elf_unix.write_file ~perm:0o600 plain "x");
              Check.equal ~pp:Format.pp_print_int "plain mode" 0
                ((Unix.stat plain).st_perm land 0o111)));
      Check.case "errors" (fun () ->
          with_temp_dir (fun dir ->
              let pp ppf _ = Format.pp_print_string ppf "<value>" in
              Check.error ~pp "read missing" (is_io `Read)
                (Elf_unix.read_file (Filename.concat dir "nope"));
              Check.error ~pp "write into missing directory" (is_io `Write)
                (Elf_unix.write_file (Filename.concat dir "no/such/f") "x");
              Check.error ~pp "executable into missing directory" (is_io `Write)
                (Elf_unix.write_executable (Filename.concat dir "no/such/f") "x")));
    ]
