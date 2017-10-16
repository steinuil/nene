open Types
open Lwt.Infix


(* *)
let torrent_of_item_attrs attrs =
  let rec loop =
    let open Xml in function
    | _, (Some filename, Some link) ->
        { filename; link }
    | Element ("title", _, [PCData name]) :: rest, (_, l) ->
        loop (rest, (Some name, l))
    | Element ("link",  _, [PCData link]) :: rest, (n, _) ->
        loop (rest, (n, Some link))
    | _ :: rest, x ->
        loop (rest, x)
    | [], _ ->
        failwith "no item title or link"
  in loop (attrs, (None, None))


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
      List.fold_left filter_items [] children
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
  let%lwt () = Config.add_torrent link in
  print_show title ep;
  Lwt.return_unit


let main () =
  let trackers = Save.load_trackers Config.shows_file in
  let seen = Save.load_seen Config.seen_file in
  let%lwt new_seen = trackers |> Lwt_list.map_p begin fun (rss_url, tracker_shows) ->
    let%lwt doc = Config.download rss_url in
    let torrents =
      try torrents_of_rss_doc doc with
      | Failure str ->
          print_endline @@ "error while processing " ^ rss_url ^ ": " ^ str;
          []
      | _ ->
          print_endline @@ "error while processing " ^ rss_url;
          [] in
    let new_eps = filter_new_eps seen tracker_shows torrents in
    new_eps |> Lwt_list.map_s begin fun (title, seen, diff) ->
      let%lwt () = Lwt_list.iter_s (download_show title) diff in
      Lwt.return (title, seen)
    end
  end in
  Save.save_seen Config.seen_file (List.flatten new_seen);
  Lwt.return_unit


let () =
  Lwt_main.run @@ main ()
