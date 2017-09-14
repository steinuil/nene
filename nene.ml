(* Util *)
let update_assoc assoc nw = function
  | [] -> [ assoc, nw ]
  | ls -> List.remove_assoc assoc ls |> List.cons (assoc, nw)


let (>>) f1 f2 x = f2 (f1 x)
let (<<) f2 f1 x = f2 (f1 x)


module Save : sig
  val load_trackers : string -> (string * (string * Str.regexp) list) list

  val load_seen : string -> (string * (int * int) list) list

  val save_seen : string -> (string * (int * int) list) list -> unit
end = struct
  open Sexplib

  let decode_trackers =
    let open Conv in
    let regexp_of_sexp = string_of_sexp >> Str.regexp in
    pair_of_sexp string_of_sexp
      (list_of_sexp
        (pair_of_sexp string_of_sexp regexp_of_sexp))

  let load_trackers file =
    Sexp.load_sexps_conv_exn file decode_trackers

    (*
  let episode_of_sexp t =
    let open Conv in
    let number, version = pair_of_sexp int_of_sexp int_of_sexp t in
    { number; version }

  let sexp_of_episode { number; version } =
    let open Conv in
    let f = sexp_of_pair sexp_of_int sexp_of_int in
    f (number, version)
    *)

  let decode_seen =
    let open Conv in
    pair_of_sexp string_of_sexp
      (list_of_sexp
        (pair_of_sexp int_of_sexp int_of_sexp))

  let encode_seen =
    let open Conv in
    sexp_of_pair sexp_of_string
      (sexp_of_list
        (sexp_of_pair sexp_of_int sexp_of_int))

  let load_seen file =
    Sexplib.Sexp.load_sexps_conv_exn file decode_seen

  let save_seen file seen =
    List.map encode_seen seen
    |> Sexplib.Sexp.save_sexps_hum file
end


module Config : sig
  val seen : string

  val trackers : string

  val download : string -> string Lwt.t

  val add_torrent : string -> unit Lwt.t
end = struct
  let seen = "seen.scm"

  let trackers = "shows.scm"

  let download url =
    let cmd = "curl", [|"nene-fetch"; url|] in
    Lwt_process.pread ~stderr:`Dev_null ~env:[||] cmd

  let download_dir = "/home/steenuil/vid/airing"

  let add_torrent uri =
    let args = [|"nene-send"; "-a"; uri; "-w"; download_dir|] in
    let cmd = "transmission-remote", args in
    let open Lwt.Infix in
    ignore =|< Lwt_process.exec ~stderr:`Dev_null cmd
end


open Lwt.Infix


type torrent =
  { filename : string
  ; link     : string }


type episode =
  { number  : int
  ; version : int }


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


let fetch_torrents url =
  Config.download url
  >>= Lwt.wrap1 torrents_of_rss_doc



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
    let last_ver = try List.assoc number seen_eps with Not_found -> -1 in
    if version > last_ver then
      let diff_ep = link, ep in
      update_assoc number version seen_eps, diff_ep :: diff
    else seen_eps, diff
  else seen_eps, diff


let filter_new_eps seen_shows tracker_shows torrents =
  tracker_shows |> List.map @@ fun (title, regexp) ->
    let seen_eps = try List.assoc title seen_shows with Not_found -> [] in
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


let main () =
  let trackers = Save.load_trackers Config.trackers in
  let seen = Save.load_seen Config.seen in
  trackers |> Lwt_list.map_p begin fun (rss_url, tracker_shows) ->
    fetch_torrents rss_url >|= fun torrents ->
    let new_eps = filter_new_eps seen tracker_shows torrents in
    new_eps |> List.map begin fun (title, seen, diff) ->
      diff |> List.iter begin fun (link, ep) ->
        Lwt.ignore_result @@ Config.add_torrent link;
        print_show title ep
      end;
      title, seen
    end
  end >|= fun seen ->
  seen |> List.flatten |> Save.save_seen Config.seen


let () =
  Lwt_main.run @@ main ()
