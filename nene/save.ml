open Sexplib
open Sexplib.Conv

let episode_map_of_sexp eps =
  let mkep map (num, ver) = Episode.Seen.add num ver map in
  list_of_sexp (pair_of_sexp int_of_sexp int_of_sexp) eps
  |> List.fold_left mkep Episode.Seen.empty

let sexp_of_episode_map map =
  Episode.Seen.bindings map
  |> sexp_of_list (sexp_of_pair sexp_of_int sexp_of_int)

let decode_seen = pair_of_sexp string_of_sexp episode_map_of_sexp

let encode_seen = sexp_of_pair sexp_of_string sexp_of_episode_map

let load_seen file =
  try Sexp.load_sexps_conv_exn file decode_seen with Sys_error _ -> []

let save_seen file seen = List.map encode_seen seen |> Sexp.save_sexps_hum file
