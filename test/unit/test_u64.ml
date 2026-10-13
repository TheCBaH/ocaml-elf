[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

open Elf_test_support

let pp_opt ppf = function
  | None -> Format.pp_print_string ppf "None"
  | Some v -> Format.fprintf ppf "Some 0x%Lx" v

let pp_int_opt ppf = function
  | None -> Format.pp_print_string ppf "None"
  | Some v -> Format.fprintf ppf "Some %d" v

let eq_opt what expected actual = Check.equal ~pp:pp_opt what expected actual

let () =
  let open Elf.U64 in
  Check.run "u64"
    [
      Check.case "add" (fun () ->
          eq_opt "-1 + 1" None (add (-1L) 1L);
          eq_opt "0xffffffff + 1" (Some 0x1_0000_0000L) (add 0xffff_ffffL 1L);
          eq_opt "max + 0" (Some (-1L)) (add (-1L) 0L));
      Check.case "sub" (fun () ->
          eq_opt "0 - 1" None (sub 0L 1L);
          eq_opt "5 - 5" (Some 0L) (sub 5L 5L);
          eq_opt "2^63 - 1" (Some 0x7fff_ffff_ffff_ffffL) (sub 0x8000_0000_0000_0000L 1L));
      Check.case "mul" (fun () ->
          eq_opt "2^32 * 2^32" None (mul 0x1_0000_0000L 0x1_0000_0000L);
          eq_opt "0 * x" (Some 0L) (mul 0L (-1L));
          eq_opt "x * 0" (Some 0L) (mul (-1L) 0L);
          eq_opt "2^32 * 2^31" (Some 0x8000_0000_0000_0000L) (mul 0x1_0000_0000L 0x8000_0000L);
          eq_opt "max * 1" (Some (-1L)) (mul (-1L) 1L);
          eq_opt "max * 2" None (mul (-1L) 2L));
      Check.case "unsigned order" (fun () ->
          Check.equal ~pp:Format.pp_print_bool "lt" true
            (lt 0x7fff_ffff_ffff_ffffL 0x8000_0000_0000_0000L);
          Check.equal ~pp:Format.pp_print_bool "lt reflexive" false (lt 3L 3L);
          Check.equal ~pp:Format.pp_print_bool "le reflexive" true (le 3L 3L);
          Check.equal ~pp:(fun ppf -> Format.fprintf ppf "0x%Lx") "max" (-1L) (max 1L (-1L)));
      Check.case "align_up" (fun () ->
          eq_opt "-1 up 4096" None (align_up (-1L) 4096L);
          eq_opt "0x1001 up 0x1000" (Some 0x2000L) (align_up 0x1001L 0x1000L);
          eq_opt "0x1000 up 0x1000" (Some 0x1000L) (align_up 0x1000L 0x1000L);
          eq_opt "0 up 8" (Some 0L) (align_up 0L 8L));
      Check.case "align_down and is_aligned" (fun () ->
          Check.equal
            ~pp:(fun ppf -> Format.fprintf ppf "0x%Lx")
            "down" 0x1000L (align_down 0x1fffL 0x1000L);
          Check.equal ~pp:Format.pp_print_bool "aligned" true (is_aligned 0x2000L 0x1000L);
          Check.equal ~pp:Format.pp_print_bool "unaligned" false (is_aligned 0x2001L 0x1000L));
      Check.case "fits_bits" (fun () ->
          Check.equal ~pp:Format.pp_print_bool "32" true (fits_bits 32 0xffff_ffffL);
          Check.equal ~pp:Format.pp_print_bool "33" false (fits_bits 32 0x1_0000_0000L);
          Check.equal ~pp:Format.pp_print_bool "64" true (fits_bits 64 (-1L));
          Check.equal ~pp:Format.pp_print_bool "0" true (fits_bits 8 0L));
      Check.case "is_pow2 and rem" (fun () ->
          Check.equal ~pp:Format.pp_print_bool "0" false (is_pow2 0L);
          Check.equal ~pp:Format.pp_print_bool "2^63" true (is_pow2 0x8000_0000_0000_0000L);
          Check.equal ~pp:Format.pp_print_bool "6" false (is_pow2 6L);
          Check.equal ~pp:(fun ppf -> Format.fprintf ppf "0x%Lx") "rem" 1L (rem (-1L) 2L));
      Check.case "to_int and of_int" (fun () ->
          Check.equal ~pp:pp_int_opt "-1" None (to_int (-1L));
          Check.equal ~pp:pp_int_opt "max_int" (Some max_int) (to_int (Int64.of_int max_int));
          Check.equal ~pp:pp_int_opt "2^62" None (to_int 0x4000_0000_0000_0000L);
          Check.equal ~pp:(fun ppf -> Format.fprintf ppf "0x%Lx") "of_int" 5L (of_int 5));
    ]
