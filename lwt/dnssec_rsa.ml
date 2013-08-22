(*
 * Copyright (c) 2011 Charalampos Rotsos <cr409@cl.cam.ac.uk>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open Dns.Packet
open Printf

module C = Cryptokit
open C.RSA

type rsa_key

external new_rsa_key : unit -> rsa_key = "ocaml_ssl_new_rsa_key"
external free_rsa_key : rsa_key -> unit = "ocaml_ssl_free_rsa_key"

external rsa_get_size : rsa_key -> int = "ocaml_ssl_rsa_get_size"
external rsa_get_n : rsa_key -> string = "ocaml_ssl_rsa_get_n"
external rsa_set_n : rsa_key -> string -> unit = "ocaml_ssl_rsa_set_n"
external rsa_get_e : rsa_key -> string = "ocaml_ssl_rsa_get_e"
external rsa_set_e : rsa_key -> string -> unit = "ocaml_ssl_rsa_set_e"
external rsa_get_d : rsa_key -> string = "ocaml_ssl_rsa_get_d"
external rsa_set_d : rsa_key -> string -> unit = "ocaml_ssl_rsa_set_d"
external rsa_get_p : rsa_key -> string = "ocaml_ssl_rsa_get_p"
external rsa_set_p : rsa_key -> string -> unit = "ocaml_ssl_rsa_set_p"
external rsa_get_q : rsa_key -> string = "ocaml_ssl_rsa_get_q"
external rsa_set_q : rsa_key -> string -> unit = "ocaml_ssl_rsa_set_q"
external rsa_get_dp : rsa_key -> string = "ocaml_ssl_rsa_get_dp"
external rsa_set_dp : rsa_key -> string -> unit = "ocaml_ssl_rsa_set_dp"
external rsa_get_dq : rsa_key -> string = "ocaml_ssl_rsa_get_dq"
external rsa_set_dq : rsa_key -> string -> unit = "ocaml_ssl_rsa_set_dq"
external rsa_get_qinv : rsa_key -> string = "ocaml_ssl_rsa_get_qinv"
external rsa_set_qinv : rsa_key -> string -> unit = 
  "ocaml_ssl_rsa_set_qinv"

external rsa_write_privkey :  string -> rsa_key -> unit = 
  "ocaml_ssl_rsa_write_privkey"
external rsa_write_pubkey :  string -> rsa_key -> unit = 
  "ocaml_ssl_rsa_write_pubkey"


external rsa_sign_msg : rsa_key -> string -> int -> string = 
  "ocaml_ssl_sign_msg"
external rsa_verify_msg : rsa_key -> string -> string -> int -> bool = 
  "ocaml_ssl_verify_msg"


let hex_of_string s = 
  let ret = ref "" in 
  String.iter 
    (fun x -> 
       ret := !ret ^ (Printf.sprintf "%02x" (Char.code x)) ) s;
  !ret

let from_hex s = C.transform_string (C.Hexa.decode()) s
let to_hex s = C.transform_string (C.Hexa.encode()) s

let new_rsa_key_from_param param =
  let ret = new_rsa_key () in 
    rsa_set_n ret (hex_of_string param.n); 
    rsa_set_e ret (hex_of_string param.e); 
    rsa_set_d ret (hex_of_string param.d); 
    rsa_set_p ret (hex_of_string param.p); 
    rsa_set_q ret (hex_of_string param.q); 
    rsa_set_dp ret (hex_of_string param.dp); 
    rsa_set_dq ret (hex_of_string param.dq); 
    rsa_set_qinv ret (hex_of_string param.qinv);
    ret

let rsa_key_to_dnskey key =
  let e = from_hex (rsa_get_e key) in 
  let n = from_hex (rsa_get_n key) in  
  let ret = Cstruct.create 4096 in
  let len = 
    if (String.length e > 255) then
      let _ = Cstruct.set_uint8 ret 0 0 in
      let _ = Cstruct.BE.set_uint16 ret 1 (String.length e) in
        3
    else 
      let _ = Cstruct.set_uint8 ret 0 (String.length e) in 
        1
  in
  let buf = Cstruct.shift ret len in 
  let _ = Cstruct.blit_from_string e 0 buf 0 (String.length e) in
  let buf = Cstruct.shift buf (String.length e) in 
  let _ = Cstruct.blit_from_string n 0 buf 0 (String.length n) in 
  let len = len + (String.length e) + (String.length n) in 
    Cstruct.to_string (Cstruct.sub ret 0 len)

let dnskey_to_rsa_key data =
  let buf = Cstruct.of_bigarray (Lwt_bytes.of_string data) in 
  let ret = new_rsa_key () in
  let (e, n) = 
    match (Cstruct.get_uint8 buf 0) with
    | 0 -> 
        let len = Cstruct.BE.get_uint16 buf 1 in 
        let buf = Cstruct.shift buf 3 in 
        let e = Cstruct.to_string (Cstruct.sub buf 0 len) in 
        let buf = Cstruct.shift buf len in 
        let n = Cstruct.to_string buf in 
          (e, n)
    | len -> 
        let buf = Cstruct.shift buf 1 in 
        let e = Cstruct.to_string (Cstruct.sub buf 0 len) in 
        let buf = Cstruct.shift buf len in 
        let n = Cstruct.to_string buf in 
          (e, n)
  in
  let _ = rsa_set_e ret (hex_of_string e) in 
  let _ = rsa_set_n ret (hex_of_string n) in 
    ret 
let verify_msg alg key data sign =
  rsa_verify_msg key data sign (dnssec_alg_to_int alg)

let sign_msg alg key data =
  rsa_sign_msg key data (dnssec_alg_to_int alg)

let decode_value value = 
    C.transform_string (C.Base64.decode ()) 
        (Re_str.global_replace (Re_str.regexp "=") "" value)

let load_key file =
  let size = ref 0 in
  let n = ref "" in
  let e = ref "" in
  let d = ref "" in 
  let p = ref "" in
  let q = ref "" in 
  let dp = ref "" in 
  let dq = ref "" in 
  let qinv = ref "" in
  let dnssec_alg = ref RSAMD5 in 
  let fd = open_in file in 
  let rec parse_file in_stream =
    try
      let line = Re_str.split (Re_str.regexp "[\ \r]*:[\ \t]*") (input_line in_stream) in 
        match line with
          (* TODO: Need to check if this is an RSA key *)
          | "Modulus" :: value ->
              n := decode_value (List.hd value); 
              size := (String.length !n) * 8;
              parse_file in_stream 
          | "PublicExponent" :: value ->
              e := decode_value (List.hd value); parse_file in_stream             
          | "PrivateExponent" :: value ->
              d := decode_value (List.hd value); parse_file in_stream             
          | "Prime1" :: value ->
              p := decode_value (List.hd value); parse_file in_stream             
          | "Prime2" :: value ->
              q := decode_value (List.hd value); parse_file in_stream             
          | "Exponent1" :: value ->
              dp := decode_value (List.hd value); parse_file in_stream             
          | "Exponent2" :: value ->
              dq:= decode_value (List.hd value); parse_file in_stream             
          | "Coefficient" :: value ->
              qinv := decode_value (List.hd value); parse_file in_stream            
          | "Algorithm" :: value -> begin 
              let _ = 
                dnssec_alg := 
                match (int_to_dnssec_alg (int_of_string
                (List.hd (Re_str.split (Re_str.regexp "[\ \t]+") (List.hd
                value))))) with
                | None -> failwith "Unsupported dnssec algorithm" 
                | Some(a) when 
                ((a=RSAMD5) || (a=RSASHA1) || (a=RSASHA256) || 
                 (a = RSASHA512)) -> a
                | Some a -> failwith (sprintf "Unsupported dnssec algorithm %s"
                                      (dnssec_alg_to_string a))
              in 
             parse_file in_stream 
          end
          | typ :: value -> parse_file in_stream
          | [] -> parse_file in_stream
    with  End_of_file -> ()
  in 
  let _ = parse_file fd in 
  let key = 
    C.RSA.({size=(!size);n=(!n);e=(!e);d=(!d);p=(!p);q=(!q);dp=(!dp);
    dq=(!dq);qinv=(!qinv);} )
  in
    (!dnssec_alg, new_rsa_key_from_param key)

