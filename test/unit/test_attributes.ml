open Elf_test_support
open Elf
open Attributes

let pp_any ppf _ = Format.pp_print_string ppf "<value>"
let ok what r = Check.ok ~pp_error what r
let fails what (pred : error -> bool) (r : (_, error) Err.t) = Check.error ~pp:pp_any what pred r

let of_hex h =
  String.init
    (String.length h / 2)
    (fun i -> Char.chr (int_of_string ("0x" ^ String.sub h (2 * i) 2)))

(* Little-endian assembly helpers, written independently of the encoder. *)
let u32 n = String.init 4 (fun i -> Char.chr ((n lsr (8 * i)) land 0xff))
let group tag body = String.make 1 (Char.chr tag) ^ u32 (5 + String.length body) ^ body

let sub vendor body =
  u32 (4 + String.length vendor + 1 + String.length body) ^ vendor ^ "\000" ^ body

let section subs = "A" ^ String.concat "" subs

(* [readelf -x .riscv.attributes] of an empty .text assembled with
   riscv64-linux-gnu-as 2.44 -march=rv32imafd -mabi=ilp32d. *)
let gas_rv32imafd =
  of_hex
    (String.concat ""
       (String.split_on_char ' '
          "41490000 00726973 63760001 3f000000 05727633 32693270 305f6d32 70305f61 3270305f \
           66327030 5f643270 305f7a6d 6d756c31 70305f7a 61616d6f 3170305f 7a616c72 73633170 3000"))

let gas_arch = "rv32i2p0_m2p0_a2p0_f2p0_d2p0_zmmul1p0_zaamo1p0_zalrsc1p0"

let sample =
  [
    {
      vendor = "aeabi";
      contents =
        `Parsed
          [
            ( File,
              [ (5, Ntbs "Cortex-A15"); (6, Uleb 10L); (32, Uleb_ntbs (3L, "xyz")); (68, Uleb 1L) ]
            );
            (Section [ 1; 2; 300 ], [ (7, Uleb 0x1_0000_0000L) ]);
            (Symbol [ 3 ], [ (8, Uleb (-1L)) ]);
          ];
    };
    {
      vendor = "riscv";
      contents = `Parsed [ (File, [ (4, Uleb 16L); (5, Ntbs "rv64i2p1"); (6, Uleb 1L) ]) ];
    };
    { vendor = "gnu"; contents = `Raw "\001\002\000\003" };
  ]

let () =
  Check.run "attributes"
    [
      Check.case "round trip, both byte orders" (fun () ->
          List.iter
            (fun e ->
              let bytes = ok "encode" (encode e sample) in
              Check.equal ~pp:pp_any "decode" sample (ok "decode" (decode e bytes));
              Check.bytes_equal "re-encode" bytes
                (ok "encode again" (encode e (ok "d" (decode e bytes)))))
            [ Types.Little; Types.Big ]);
      Check.case "matches GAS output" (fun () ->
          let t = ok "decode" (decode Types.Little gas_rv32imafd) in
          Check.equal ~pp:pp_any "contents"
            [ { vendor = "riscv"; contents = `Parsed [ (File, [ (5, Ntbs gas_arch) ]) ] } ]
            t;
          Check.bytes_equal "encode" gas_rv32imafd (ok "encode" (encode Types.Little t));
          Check.equal ~pp:pp_any "find" (Some (Ntbs gas_arch)) (find t ~vendor:"riscv" ~tag:5);
          Check.equal ~pp:pp_any "find missing" None (find t ~vendor:"riscv" ~tag:4);
          Check.equal ~pp:pp_any "find other vendor" None (find t ~vendor:"aeabi" ~tag:5));
      Check.case "ARMv7-A attributes match GAS output" (fun () ->
          (* [readelf -x .ARM.attributes] of an empty .text assembled with
             arm-linux-gnueabihf-as 2.44 -march=armv7-a. *)
          let gas =
            of_hex
              (String.concat ""
                 (String.split_on_char ' '
                    "411c0000 00616561 62690001 12000000 05372d41 00060a07 41080109 02"))
          in
          Check.bytes_equal "encode" gas (ok "encode" (encode Types.Little Arm.armv7a_attributes));
          Check.equal ~pp:pp_any "decode" Arm.armv7a_attributes
            (ok "decode" (decode Types.Little gas)));
      Check.case "hand-assembled layout" (fun () ->
          let bytes = ok "encode" (encode Types.Little [ List.nth sample 1 ]) in
          let expected =
            section [ sub "riscv" (group 1 ("\004\016" ^ "\005rv64i2p1\000" ^ "\006\001")) ]
          in
          Check.bytes_equal "bytes" expected bytes);
      Check.case "unknown vendor is kept raw" (fun () ->
          let bytes = section [ sub "other" "\xff\x00\x01 junk" ] in
          let t = ok "decode" (decode Types.Little bytes) in
          Check.equal ~pp:pp_any "raw"
            [ { vendor = "other"; contents = `Raw "\xff\x00\x01 junk" } ]
            t;
          Check.bytes_equal "round trip" bytes (ok "encode" (encode Types.Little t)));
      Check.case "ULEB limits" (fun () ->
          let with_uleb u = section [ sub "riscv" (group 1 ("\004" ^ u)) ] in
          fails "10 continuation bytes"
            (function `Uleb_overflow _ -> true | _ -> false)
            (decode Types.Little (with_uleb (String.make 10 '\x80')));
          fails "10th byte too large"
            (function `Uleb_overflow _ -> true | _ -> false)
            (decode Types.Little (with_uleb (String.make 9 '\xff' ^ "\x02")));
          let t = ok "max" (decode Types.Little (with_uleb (String.make 9 '\xff' ^ "\x01"))) in
          Check.equal ~pp:pp_any "u64 max" (Some (Uleb (-1L))) (find t ~vendor:"riscv" ~tag:4);
          fails "truncated"
            (function `Truncated_subsection -> true | _ -> false)
            (decode Types.Little (with_uleb "\x80")));
      Check.case "decode errors" (fun () ->
          let d = decode Types.Little in
          fails "version" (function `Bad_format_version 0x42 -> true | _ -> false) (d "B");
          fails "empty" (function `Truncated_subsection -> true | _ -> false) (d "");
          fails "short length field"
            (function `Truncated_subsection -> true | _ -> false)
            (d "A\001\000");
          fails "length below minimum"
            (function `Bad_subsection_length { offset = 1; length = 3 } -> true | _ -> false)
            (d ("A" ^ u32 3 ^ "x\000"));
          fails "length past the end"
            (function `Bad_subsection_length { offset = 1; length = 100 } -> true | _ -> false)
            (d ("A" ^ u32 100 ^ "riscv\000"));
          fails "vendor not terminated"
            (function `Unterminated_ntbs 5 -> true | _ -> false)
            (d ("A" ^ u32 9 ^ "riscv"));
          fails "value not terminated"
            (function `Unterminated_ntbs _ -> true | _ -> false)
            (d (section [ sub "riscv" (group 1 "\005abc") ]));
          fails "unknown scope"
            (function `Unknown_scope 9 -> true | _ -> false)
            (d (section [ sub "riscv" (group 9 "") ]));
          fails "group length too small"
            (function `Bad_subsection_length _ -> true | _ -> false)
            (d (section [ sub "riscv" ("\001" ^ u32 2) ]));
          fails "group length past subsection"
            (function `Bad_subsection_length _ -> true | _ -> false)
            (d (section [ sub "riscv" ("\001" ^ u32 99) ]));
          fails "truncated group"
            (function `Truncated_subsection -> true | _ -> false)
            (d (section [ sub "riscv" "\001\000" ]));
          fails "unterminated index list"
            (function `Truncated_subsection -> true | _ -> false)
            (d (section [ sub "riscv" (group 2 "\001\002") ])));
      Check.case "encode errors" (fun () ->
          let e subs = encode Types.Little subs in
          let one vendor attrs = [ { vendor; contents = `Parsed [ (File, attrs) ] } ] in
          fails "NUL in value"
            (function `Nul_in_value "a\000b" -> true | _ -> false)
            (e (one "riscv" [ (5, Ntbs "a\000b") ]));
          fails "NUL in vendor"
            (function `Nul_in_value _ -> true | _ -> false)
            (e [ { vendor = "a\000"; contents = `Raw "" } ]);
          fails "wrong form"
            (function `Bad_value_kind { vendor = "riscv"; tag = 4 } -> true | _ -> false)
            (e (one "riscv" [ (4, Ntbs "x") ]));
          fails "wrong form, aeabi"
            (function `Bad_value_kind { vendor = "aeabi"; tag = 32 } -> true | _ -> false)
            (e (one "aeabi" [ (32, Uleb 1L) ]));
          fails "unknown vendor"
            (function `Unknown_vendor "nope" -> true | _ -> false)
            (e (one "nope" []));
          fails "negative tag"
            (function `Bad_tag -1 -> true | _ -> false)
            (e (one "riscv" [ (-1, Uleb 0L) ]));
          fails "zero index"
            (function `Bad_index 0 -> true | _ -> false)
            (e [ { vendor = "riscv"; contents = `Parsed [ (Section [ 0 ], []) ] } ]));
      Check.case "classify" (fun () ->
          let kind v t = classify ~vendor:v ~tag:t in
          let pp ppf = function
            | None -> Format.pp_print_string ppf "none"
            | Some `Uleb -> Format.pp_print_string ppf "uleb"
            | Some `Ntbs -> Format.pp_print_string ppf "ntbs"
            | Some `Uleb_ntbs -> Format.pp_print_string ppf "uleb+ntbs"
          in
          List.iter
            (fun (v, t, k) -> Check.equal ~pp (Printf.sprintf "%s %d" v t) k (kind v t))
            [
              ("riscv", 4, Some `Uleb);
              ("riscv", 5, Some `Ntbs);
              ("riscv", 6, Some `Uleb);
              ("riscv", 8, Some `Uleb);
              ("riscv", 9, Some `Ntbs);
              ("aeabi", 4, Some `Ntbs);
              ("aeabi", 5, Some `Ntbs);
              ("aeabi", 6, Some `Uleb);
              ("aeabi", 32, Some `Uleb_ntbs);
              ("aeabi", 33, Some `Ntbs);
              ("aeabi", 34, Some `Uleb);
              ("aeabi", 67, Some `Ntbs);
              ("aeabi", 68, Some `Uleb);
              ("gnu", 4, None);
            ]);
    ]
