open Types
open Sexplib
open Conv

let decode_trackers =
  let regexp_of_sexp x = string_of_sexp x |> Str.regexp in
  pair_of_sexp string_of_sexp
    (list_of_sexp (pair_of_sexp string_of_sexp regexp_of_sexp))

let load_trackers file = Sexp.load_sexps_conv_exn file decode_trackers

let episode_map_of_sexp eps =
  let mkep map (num, ver) = IntMap.add num ver map in
  list_of_sexp (pair_of_sexp int_of_sexp int_of_sexp) eps
  |> List.fold_left mkep IntMap.empty

let sexp_of_episode_map map =
  IntMap.bindings map |> sexp_of_list (sexp_of_pair sexp_of_int sexp_of_int)

let decode_seen = pair_of_sexp string_of_sexp episode_map_of_sexp

let encode_seen = sexp_of_pair sexp_of_string sexp_of_episode_map

let load_seen file =
  try Sexp.load_sexps_conv_exn file decode_seen with Sys_error _ -> []

let save_seen file seen = List.map encode_seen seen |> Sexp.save_sexps_hum file
