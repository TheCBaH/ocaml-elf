[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

open Elf_test_support
open Elf

let ok what r = Check.ok ~pp_error:Strtab.pp_error what r

let () =
  Check.run "strtab"
    [
      Check.case "empty string is offset 0" (fun () ->
          let t = Strtab.create () in
          Check.equal ~pp:Format.pp_print_string "contents" "\000" (Strtab.contents t);
          Check.equal
            ~pp:(fun ppf -> Format.fprintf ppf "%Ld")
            "offset" 0L
            (ok "add" (Strtab.add t "")));
      Check.case "add is idempotent" (fun () ->
          let t = Strtab.create () in
          let a = ok "a" (Strtab.add t "a") in
          let b = ok "b" (Strtab.add t "bc") in
          let a' = ok "a again" (Strtab.add t "a") in
          Check.equal ~pp:(fun ppf -> Format.fprintf ppf "%Ld") "same offset" a a';
          Check.equal ~pp:(fun ppf -> Format.fprintf ppf "%Ld") "next offset" 3L b;
          Check.equal ~pp:Format.pp_print_string "contents" "\000a\000bc\000" (Strtab.contents t));
      Check.case "offsets decode through Decode.string_at" (fun () ->
          let t = Strtab.create () in
          let names = [ "alpha"; "beta"; ""; "alpha"; ".text"; "x" ] in
          let offs = List.map (fun n -> (n, ok n (Strtab.add t n))) names in
          let bytes =
            Fixture.build Types.Elf32 Types.Little
              [ Fixture.sect ".strtab" Const.sht_strtab (Strtab.contents t) ]
          in
          let d = Check.ok ~pp_error:Decode.pp_error "decode" (Decode.of_string bytes) in
          let strtab = Option.get (Decode.find_section d ".strtab") in
          List.iter
            (fun (n, off) ->
              Check.equal ~pp:Format.pp_print_string n n
                (Check.ok ~pp_error:Decode.pp_error "string_at" (Decode.string_at d strtab off)))
            offs);
      Check.case "NUL in a name is rejected" (fun () ->
          let t = Strtab.create () in
          Check.error
            ~pp:(fun ppf -> Format.fprintf ppf "%Ld")
            "nul"
            (function `Nul_in_name n -> n = "a\000b")
            (Strtab.add t "a\000b");
          Check.equal ~pp:Format.pp_print_string "unchanged" "\000" (Strtab.contents t));
    ]
