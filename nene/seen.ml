module Episode_map = Map.Make (struct
  type t = int

  let compare = Stdlib.compare
end)

module Shows_map = Map.Make (struct
  type t = string

  let compare = Stdlib.compare
end)

type t = int Episode_map.t Shows_map.t

let is_new seen Episode.{ number; version } =
  match Episode_map.find_opt number seen with
  | None -> true
  | Some last_ver -> version > last_ver

let seen_test =
  [ (1, 2); (2, 1); (3, 5); (5, 3) ] |> List.to_seq |> Episode_map.of_seq

let%test "new episode" = is_new seen_test Episode.{ number = 4; version = 0 }
let%test "new version" = is_new seen_test Episode.{ number = 2; version = 2 }

let%test "same episode" =
  not (is_new seen_test Episode.{ number = 3; version = 5 })

let%test "old episode" =
  not (is_new seen_test Episode.{ number = 1; version = 1 })

let ( let+ ) = Option.bind

let parse shows filename =
  List.find_map
    (fun Config.{ name; pattern } ->
      let+ ep = Pattern.parse_filename pattern filename in
      Some (name, ep))
    shows

let is_new seen name ep =
  match Shows_map.find_opt name seen with
  | Some seen when is_new seen ep -> true
  | None -> true
  | Some _ -> false

(* let parse_new ~shows ~seen Config.{ filename; link } =
   let+ name, ep =
     List.find_map
       (fun Config.{ name; pattern } ->
         let+ ep = Pattern.parse_filename pattern filename in
         Some (name, ep))
       shows
   in
   match Shows_map.find_opt name seen with
   | Some seen when is_new seen ep -> Some (name, link, ep)
   | None -> Some (name, link, ep)
   | Some _ -> None *)

let merge shows new_eps =
  List.fold_left
    (fun shows (show_name, Episode.{ number; version }) ->
      Shows_map.update show_name
        (fun maybe_eps ->
          Option.value ~default:Episode_map.empty maybe_eps
          |> Episode_map.add number version
          |> Option.some)
        shows)
    shows new_eps

open Sexplib
open Sexplib.Conv

let episode_map_of_sexp eps =
  list_of_sexp (pair_of_sexp int_of_sexp int_of_sexp) eps
  |> List.to_seq |> Episode_map.of_seq

let sexp_of_episode_map map =
  Episode_map.bindings map
  |> sexp_of_list (sexp_of_pair sexp_of_int sexp_of_int)

let of_sexp map =
  list_of_sexp (pair_of_sexp string_of_sexp episode_map_of_sexp) map
  |> List.to_seq |> Shows_map.of_seq

let to_sexp map =
  Shows_map.bindings map
  |> sexp_of_list (sexp_of_pair sexp_of_string sexp_of_episode_map)

let read_file file =
  try Sexp.load_sexp_conv_exn file of_sexp with Sys_error _ -> Shows_map.empty

let write_file file seen = to_sexp seen |> Sexp.save_hum file
