(* Util *)
let ( ||> ) (x1, x2) f = f x1 x2
let ( <|| ) f (x1, x2) = f x1 x2
let ( |||> ) (x1, x2, x3) f = f x1 x2 x3
let ( <||| ) f (x1, x2, x3) = f x1 x2 x3
let ( >> ) f1 f2 x = f2 (f1 x)
let ( << ) f2 f1 x = f2 (f1 x)
let with_default def = function Some x -> x | None -> def


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
    try Sexp.load_sexps_conv_exn file decode_seen with
    | Sys_error _ -> []

  let save_seen file seen =
    List.map encode_seen seen
    |> Sexp.save_sexps_hum file
end


module Config = struct
  type flags =
    { download_dir : string option
    ; shows_file   : string option
    ; transmission_host : string option
    ; transmission_port : int option }

  let flags =
    let args = List.tl @@ Array.to_list Sys.argv in
    let rec loop flags acc = match flags, acc with
      | [], acc -> acc
      | "-download-dir" :: path :: rest
      , { download_dir = None; _ } ->
          loop rest { acc with download_dir = Some path }
      | "-shows" :: path :: rest
      , { shows_file = None; _ } ->
          loop rest { acc with shows_file = Some path }
      | "-transmission-host" :: host :: rest
      , { transmission_host = None; _ } ->
          loop rest { acc with transmission_host = Some host }
      | "-transmission-port" :: port :: rest
      , { transmission_port = None; _ } ->
          let port = int_of_string port in
          loop rest { acc with transmission_port = Some port }
      | "-h" :: _, _ | "-help" :: _, _ ->
          let cmd_name = Sys.argv.(0) in
          print_endline ("Usage: " ^ cmd_name
            ^ " [-h] [-download-dir <path>] [-shows <path>]\n"
            ^ String.make (8 + String.length cmd_name) ' '
            ^ "[-transmission-host <host>] [-transmission-port <port>]");
          exit 0
      | opt :: _, _ ->
          failwith ("Unrecognized option: " ^ opt) in
    loop args
      { download_dir = None; shows_file = None
      ; transmission_host = None; transmission_port = None }

  let home_dir =
    Sys.getenv "HOME"

  let nene_dir =
    let config_dir =
      match Sys.getenv_opt "XDG_CONFIG_HOME" with
      | Some dir -> dir
      | None ->
          Filename.concat home_dir ".config" in
    let nene_dir = Filename.concat config_dir "nene" in
    if not @@ Sys.file_exists nene_dir then
      Unix.mkdir nene_dir 0o644;
    nene_dir

  let in_config_dir f =
    Filename.concat nene_dir f

  let seen =
    in_config_dir "seen.scm"

  let trackers = match flags.shows_file with
    | Some f -> f
    | None -> in_config_dir "shows.scm"

  let download_dir = match flags.download_dir with
    | Some d -> d
    | None -> Filename.concat home_dir "vid/airing"

  let download url =
    let cmd = "curl", [|"nene-fetch"; url|] in
    Lwt.catch
      (fun () ->
        Lwt_process.pread ~timeout:15. ~stderr:`Dev_null ~env:[||] cmd)
      (fun _ -> Lwt.return "")

  let session_id_mutex = Lwt_mutex.create ()

  let transmission_url =
    let port = with_default 9091 flags.transmission_port in
    let host = with_default "127.0.0.1" flags.transmission_host in
    Uri.make ~scheme:"http" ~port ~host ~path:"/transmission/rpc" ()

  let session_id' : Cohttp.Header.t option ref =
    ref None

  let session_id () =
    Lwt_mutex.lock session_id_mutex >>= fun () ->
    match !session_id' with
    | Some headers ->
        Lwt_mutex.unlock session_id_mutex;
        Lwt.return headers
    | None ->
        Cohttp_lwt_unix.Client.get transmission_url >|= fun (resp, _) ->
        let headers = Cohttp_lwt.Response.headers resp in
        let header_name = "X-Transmission-Session-Id" in
        let session_id_hdr =
          match Cohttp.Header.get headers header_name with
          | Some id -> Cohttp.Header.init_with header_name id
          | None -> Cohttp.Header.init () in
        session_id' := Some session_id_hdr;
        Lwt_mutex.unlock session_id_mutex;
        session_id_hdr

  let add_torrent url =
    session_id () >>= fun headers ->
    let body = Cohttp_lwt_body.of_string ("{\"method\":\"torrent-add\",\"arguments\":{\"download-dir\":\""
      ^ download_dir ^ "\",\"filename\":\"" ^ url ^ "\"}}") in
    Cohttp_lwt_unix.Client.post ~body ~headers transmission_url >>= fun (_, body) ->
    Cohttp_lwt_body.to_string body >|= print_endline
end


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
  Lwt.ignore_result @@ Config.add_torrent link;
  print_show title ep


let main () =
  let trackers = Save.load_trackers Config.trackers in
  let seen = Save.load_seen Config.seen in
  trackers |> Lwt_list.map_p begin fun (rss_url, tracker_shows) ->
    Config.download rss_url >|= fun doc ->
    let torrents =
      try torrents_of_rss_doc doc with
      | Failure str ->
          print_endline @@ "error while processing " ^ rss_url ^ ": " ^ str;
          []
      | _ ->
          print_endline @@ "error while processing " ^ rss_url;
          [] in
    let new_eps = filter_new_eps seen tracker_shows torrents in
    new_eps |> List.map begin fun (title, seen, diff) ->
      diff |> List.iter @@ download_show title;
      title, seen
    end
  end >|= fun seen ->
  seen |> List.flatten |> Save.save_seen Config.seen


let () =
  Lwt_main.run @@ main ()
