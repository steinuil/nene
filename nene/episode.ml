type t = { number : int; version : int }

module Seen = struct
  module Int_map = Map.Make (struct
    type t = int

    let compare = Stdlib.compare
  end)

  include Int_map

  type nonrec t = int Int_map.t

  open Sexplib
  open Sexplib.Conv

  let episode_map_of_sexp eps =
    let mkep map (num, ver) = add num ver map in
    list_of_sexp (pair_of_sexp int_of_sexp int_of_sexp) eps
    |> List.fold_left mkep empty

  let sexp_of_episode_map map =
    bindings map |> sexp_of_list (sexp_of_pair sexp_of_int sexp_of_int)

  let of_sexp = pair_of_sexp string_of_sexp episode_map_of_sexp

  let to_sexp = sexp_of_pair sexp_of_string sexp_of_episode_map

  let read_file file =
    try Sexp.load_sexps_conv_exn file of_sexp with Sys_error _ -> []

  let write_file file seen = List.map to_sexp seen |> Sexp.save_sexps_hum file
end
