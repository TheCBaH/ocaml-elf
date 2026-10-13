(* Deterministic mutation fuzzing of the decoder: whatever the input, every accessor must return Ok
   or Error and never raise. ELF_FUZZ_N sets the mutations per corpus file (200 by default;
   `make fuzz` uses 100000). *)

open Elf_test_support
open Elf
module F = Fixture

let iterations =
  match Option.bind (Sys.getenv_opt "ELF_FUZZ_N") int_of_string_opt with Some n -> n | None -> 200

let edges =
  [|
    0L;
    1L;
    2L;
    3L;
    4L;
    7L;
    8L;
    0xffL;
    0x100L;
    0x7fffL;
    0x8000L;
    0xffffL;
    0x1_0000L;
    0xffffffL;
    0x7fff_ffffL;
    0x8000_0000L;
    0xffff_ffffL;
    0x1_0000_0000L;
    0x7fff_ffff_ffff_ffffL;
    0x8000_0000_0000_0000L;
    0xffff_ffff_ffff_fff0L;
    -1L;
  |]

let mutate rng bytes =
  let len = String.length bytes in
  let pick n = Random.State.int rng (max n 1) in
  match pick 4 with
  | 0 ->
      (* flip one byte *)
      if len = 0 then bytes else F.set_u8 (pick len) (pick 256) bytes
  | 1 -> F.truncate (pick (len + 1)) bytes
  | 2 ->
      (* a 16- or 32-bit field set to an edge value *)
      if len < 8 then bytes
      else
        let off = pick (len - 4) and v = edges.(pick (Array.length edges)) in
        if Random.State.bool rng then F.set_u16 off (Int64.to_int (Int64.logand v 0xffffL)) bytes
        else F.set_u32 off (Int64.logand v 0xffff_ffffL) bytes
  | _ ->
      (* a word-sized field set to an edge value, aligned the way real fields are *)
      if len < 16 then bytes
      else F.set_word (pick (len - 8) land lnot 3) edges.(pick (Array.length edges)) bytes

(* Every accessor, on every section and segment. *)
let decoded = ref 0

let exercise bytes =
  match Decode.of_string bytes with
  | Error _ -> ()
  | Ok d ->
      incr decoded;
      ignore (Decode.find_section d ".text");
      Array.iter
        (fun s ->
          ignore (Decode.section_data d s);
          ignore (Decode.symbols d s);
          ignore (Decode.relocations d s);
          ignore (Decode.notes d (`Section s));
          ignore (Decode.attributes d s);
          ignore (Decode.string_at d s 0L);
          ignore (Decode.string_at d s 0xffff_ffff_ffff_ffffL))
        d.sections;
      for i = -1 to d.phnum do
        ignore (Decode.segment_data d i);
        ignore (Decode.notes d (`Segment i))
      done

let corpus =
  List.concat_map
    (fun (cls, endian) -> [ F.minimal ~cls ~endian (); F.many_sections ~cls ~endian 40 ])
    [
      (Types.Elf32, Types.Little);
      (Types.Elf32, Types.Big);
      (Types.Elf64, Types.Little);
      (Types.Elf64, Types.Big);
    ]

let () =
  Check.run "fuzz"
    (List.mapi
       (fun i seed ->
         Check.case (Printf.sprintf "corpus file %d" i) (fun () ->
             let rng = Random.State.make [| 0x454c46; i |] in
             for n = 1 to iterations do
               (* up to three stacked mutations *)
               let rec stack k b = if k = 0 then b else stack (k - 1) (mutate rng b) in
               let bytes = stack (1 + Random.State.int rng 3) seed in
               match exercise bytes with
               | () -> ()
               | exception e ->
                   Check.failf "iteration %d: exception %s on an input of %d bytes" n
                     (Printexc.to_string e) (String.length bytes)
             done))
       corpus
    @ [
        Check.case "mutants still decode often enough to exercise the accessors" (fun () ->
            (* A fuzz loop that only produces rejected files proves nothing. *)
            if !decoded * 10 < iterations * List.length corpus then
              Check.failf "only %d of %d mutants decoded" !decoded (iterations * List.length corpus));
      ])
