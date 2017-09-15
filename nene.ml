(* Util *)
let ( ||> ) (x1, x2) f = f x1 x2
let ( <|| ) f (x1, x2) = f x1 x2
let ( |||> ) (x1, x2, x3) f = f x1 x2 x3
let ( <||| ) f (x1, x2, x3) = f x1 x2 x3
let ( >> ) f1 f2 x = f2 (f1 x)
let ( << ) f2 f1 x = f2 (f1 x)


open Lwt.Infix


type torrent =
  { filename : string
  ; link     : string }


type episode =
  { number  : int
  ; version : int }


module IntMap = Map.Make(struct
  type t = int
  let compare = Pervasives.compare
end)


type episode_map = int IntMap.t


type url = string


module Save = struct
  open Sexplib
  open Conv

  let decode_trackers =
    let regexp_of_sexp = string_of_sexp >> Str.regexp in
    pair_of_sexp string_of_sexp
      (list_of_sexp
        (pair_of_sexp string_of_sexp regexp_of_sexp))

  let load_trackers file =
    Sexp.load_sexps_conv_exn file decode_trackers

  let episode_map_of_sexp =
    let mkep map (num, ver) = IntMap.add num ver map in
    pair_of_sexp int_of_sexp int_of_sexp |> list_of_sexp
    >> List.fold_left mkep IntMap.empty

  let sexp_of_episode_map =
    IntMap.bindings
    >> sexp_of_list (sexp_of_pair sexp_of_int sexp_of_int)

  let decode_seen =
    pair_of_sexp string_of_sexp episode_map_of_sexp

  let encode_seen =
    sexp_of_pair sexp_of_string sexp_of_episode_map

  let load_seen file =
    Sexp.load_sexps_conv_exn file decode_seen

  let save_seen file seen =
    List.map encode_seen seen
    |> Sexp.save_sexps_hum file
end


module Config = struct
  let seen = "seen.scm"

  let trackers = "shows.scm"

  let download url =
    let cmd = "curl", [|"nene-fetch"; url|] in
    Lwt_process.pread ~stderr:`Dev_null ~env:[||] cmd

  let download_dir = "/home/steenuil/vid/airing"

  let add_torrent uri =
    let args = [|"nene-send"; "-a"; uri; "-w"; download_dir|] in
    let cmd = "transmission-remote", args in
    ignore =|< Lwt_process.exec ~stderr:`Dev_null cmd
end


(* *)
let torrent_of_item_attrs attrs =
  let rec loop =
    let open Xml in function
    | (Some filename, Some link), _ ->
        { filename; link }
    | (_, l), Element ("title", _, [PCData name]) :: rest ->
        loop ((Some name, l), rest)
    | (n, _), Element ("link", _, [PCData link]) :: rest ->
        loop ((n, Some link), rest)
    | x, _ :: rest ->
        loop (x, rest)
    | _, [] ->
        failwith "no item title or link"
  in loop ((None, None), attrs)


let torrent_of_item =
  let open Xml in function
  | Element ("item", _, children) ->
      torrent_of_item_attrs children
  | _ -> failwith "not an item node"


let torrents_of_rss_doc doc =
  let filter_items acc item =
    try torrent_of_item item :: acc with
    | Failure _ -> acc in
  let open Xml in
  match parse_string doc with
  | Element ("rss", _, [Element ("channel", _, children)]) ->
      children |> List.fold_left filter_items []
  | _ -> failwith "not an rss document"



(* *)
let episode_of_filename regexp filename =
  let number =
    Str.replace_first regexp "\\1" filename
    |> int_of_string in
  let version =
    try
      let v = Str.replace_first regexp "\\2" filename in
      String.sub v 1 ((String.length v) - 1)
      |> int_of_string
    with Failure _ -> 1 in
  { number; version }


(* Folds over a list of torrents,
 * returning the updated seen list
 * and the changes *)
let new_episodes regexp (seen_eps, diff) { filename; link } =
  if Str.string_match regexp filename 0 then
    let { number; version } as ep = episode_of_filename regexp filename in
    let last_ver =
      try IntMap.find number seen_eps with
      | Not_found -> -1 in
    if version > last_ver then
      let diff_ep = link, ep in
      IntMap.add number version seen_eps, diff_ep :: diff
    else seen_eps, diff
  else seen_eps, diff


let filter_new_eps seen_shows tracker_shows torrents =
  tracker_shows |> List.map @@ fun (title, regexp) ->
    let seen_eps =
      try List.assoc title seen_shows with
      | Not_found -> IntMap.empty in
    let all_eps, diff =
      let f = new_episodes regexp in
      List.fold_left f (seen_eps, []) torrents in
    title, all_eps, diff


let print_show title { number; version } =
  print_string title;
  print_char ' ';
  print_int number;
  if version <> 1 then begin
    print_char ' ';
    print_int version
  end;
  print_newline ()


let download_show title (link, ep) =
  Lwt.ignore_result @@ Config.add_torrent link;
  print_show title ep


let main () =
  let trackers = Save.load_trackers Config.trackers in
  let seen = Save.load_seen Config.seen in
  trackers |> Lwt_list.map_p begin fun (rss_url, tracker_shows) ->
    Config.download rss_url >|= fun doc ->
    let torrents = try torrents_of_rss_doc doc with Failure _ -> [] in
    let new_eps = filter_new_eps seen tracker_shows torrents in
    new_eps |> List.map begin fun (title, seen, diff) ->
      diff |> List.iter @@ download_show title;
      title, seen
    end
  end >|= fun seen ->
  seen |> List.flatten |> Save.save_seen Config.seen


let () =
  Lwt_main.run @@ main ()
