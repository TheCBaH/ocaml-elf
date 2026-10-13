[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

(* GNU-produced files (objects, static and dynamic executables, shared objects) checked in under
   test/fixtures with the readelf output recorded next to each one: Decode must agree with readelf
   on every field. Needs no toolchain; regenerate with tools/regen-fixtures.sh. *)

open Elf_test_support
open Elf
module C = Readelf_check

let archs =
  [
    ("x86-32", Target.X86_32);
    ("x86-64", Target.X86_64);
    ("arm", Target.Arm);
    ("aarch64", Target.Aarch64);
    ("riscv32", Target.Riscv32);
    ("riscv64", Target.Riscv64);
  ]

(* Every architecture has these; the note fixtures (an 8-aligned .note.gnu.property) exist only where
   GCC can emit the property: x86 with -fcf-protection and AArch64 with -mbranch-protection. *)
let files = [ "obj.o"; "static"; "dynamic"; "lib.so"; "group.o" ]
let note_files = [ "note.o"; "note-static" ]
let read path = Check.ok ~pp_error:Elf_unix.pp_error path (Elf_unix.read_file path)

let check_file (dir, arch) file =
  let path = Filename.concat (Filename.concat "../fixtures" dir) file in
  let data = read path and recorded = read (path ^ ".readelf") in
  let d = Check.ok ~pp_error:Decode.pp_error path (Decode.of_string data) in
  C.mismatches := [];
  C.check_header d recorded;
  C.check_sections arch d recorded;
  C.check_segments d recorded;
  C.check_symbols d recorded;
  C.check_relocs d recorded;
  C.check_notes d recorded;
  C.check_attributes arch d recorded;
  match !C.mismatches with
  | [] -> ()
  | l -> Check.failf "%s:\n  %s" path (String.concat "\n  " (List.rev l))

let () =
  Check.run "fixtures"
    (List.concat_map
       (fun ((dir, _) as a) ->
         let extra =
           List.filter
             (fun f -> Sys.file_exists (Filename.concat ("../fixtures/" ^ dir) f))
             note_files
         in
         List.map (fun f -> Check.case (dir ^ "/" ^ f) (fun () -> check_file a f)) (files @ extra))
       archs)

(* The edge cases are really in the files: a section group, and an 8-aligned property note. *)
let () =
  Check.run "fixtures: edge cases"
    [
      Check.case "section groups" (fun () ->
          List.iter
            (fun (dir, _) ->
              let d =
                Check.ok ~pp_error:Decode.pp_error dir
                  (Decode.of_string (read (Printf.sprintf "../fixtures/%s/group.o" dir)))
              in
              let groups =
                List.filter
                  (fun (s : Decode.section) -> s.shdr.sh_type = Const.sht_group)
                  (Array.to_list d.sections)
              in
              Check.equal ~pp:Format.pp_print_int (dir ^ " SHT_GROUP sections") 1
                (List.length groups))
            archs);
      Check.case "8-aligned .note.gnu.property" (fun () ->
          List.iter
            (fun dir ->
              let d =
                Check.ok ~pp_error:Decode.pp_error dir
                  (Decode.of_string (read (Printf.sprintf "../fixtures/%s/note.o" dir)))
              in
              match Decode.find_section d ".note.gnu.property" with
              | None -> Check.failf "%s: no .note.gnu.property" dir
              | Some s ->
                  Check.equal
                    ~pp:(fun ppf -> Format.fprintf ppf "%Ld")
                    (dir ^ " alignment") 8L s.shdr.sh_addralign;
                  let notes =
                    Check.ok ~pp_error:Decode.pp_error dir (Decode.notes d (`Section s))
                  in
                  Check.equal ~pp:Format.pp_print_int (dir ^ " notes") 1 (List.length notes))
            [ "x86-64"; "aarch64" ]);
    ]
