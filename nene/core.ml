open Types

exception Invalid_feed

let get_torrent_info attrs =
  let rec loop =
    let open Xml in
    function
    | _, (Some filename, Some link) -> { filename; link }
    | Element ("title", _, [ PCData name ]) :: rest, (_, l) ->
        loop (rest, (Some name, l))
    | Element ("link", _, [ PCData link ]) :: rest, (n, _) ->
        loop (rest, (n, Some link))
    | _ :: rest, x -> loop (rest, x)
    | [], _ -> raise Invalid_feed
  in
  loop (attrs, (None, None))

let torrents_of_rss_doc doc =
  let open Xml in
  let filter_items acc = function
    | Element ("item", _, children) -> get_torrent_info children :: acc
    | _ -> acc
  in
  match parse_string doc with
  | Element ("rss", _, [ Element ("channel", _, children) ]) ->
      List.fold_left filter_items [] children
  | exception Error _ -> raise Invalid_feed
  | exception Dtd.Parse_error _ -> raise Invalid_feed
  | _ -> raise Invalid_feed

let parse_episode_filename regexp filename =
  try
    let number = int_of_string @@ Str.replace_first regexp "\\1" filename in
    let version =
      try
        let ver = Str.replace_first regexp "\\2" filename in
        int_of_string @@ String.sub ver 1 (String.length ver - 1)
      with Failure _ -> 1
    in
    Some { number; version }
  with Failure _ -> None

let is_episode_new seen_eps { number; version } =
  match IntMap.find_opt number seen_eps with
  | None -> true
  | Some last_ver -> version > last_ver

let new_episodes regexp (seen_eps, new_links) { filename; link } =
  match parse_episode_filename regexp filename with
  | None -> (seen_eps, new_links)
  | Some ep ->
      if is_episode_new seen_eps ep then
        (IntMap.add ep.number ep.version seen_eps, (link, ep) :: new_links)
      else (seen_eps, new_links)

let get_new_episodes ~callback regexp seen_eps torrents =
  let seen, ep_links =
    List.fold_left (new_episodes regexp) (seen_eps, []) torrents
  in
  let%lwt () = Lwt_list.iter_s callback ep_links in
  Lwt.return seen

let count = ref 0

let total = ref 0

let print_status () = Lwt_io.printf "\rProcessed %2d/%d%!" !count !total

(* let log_print action str =
   let%lwt () = Lwt_io.printlf "\r\x1b[1m* \x1b[32m%s\x1b[0m: %s%!" action str in
   print_status () *)

let error_print str =
  let%lwt () = Lwt_io.printlf "\r\x1b[1;31m[ERROR]\x1b[0m %s%!" str in
  print_status ()

let format_show title { number; version } =
  let buf = Buffer.create 16 in
  Printf.bprintf buf "%s %d" title number;
  if version <> 1 then Printf.bprintf buf "v%d" version;
  (*Buffer.add_string buf "\x1b[0m";*)
  Buffer.contents buf

(* TODO: deal with errors from adding the torrent *)
(* let _download_ep title (link, { number; version }) =
   let%lwt () = Config.add_torrent link in
   log_print "downloaded" (format_show title { number; version }) *)

let die_fatal str =
  Printf.printf "\r\x1b[1;31mFatal error\x1b[0m: %s\n" str;
  exit 1

let run ~shows_file ~seen_file ~jobs:_ ~backend:_ =
  let trackers =
    try Save.load_trackers shows_file with
    | Sys_error err -> die_fatal err
    | Failure _ -> die_fatal (shows_file ^ ": Unbalanced left parenthesis")
    | Sexplib.Sexp.Parse_error { err_msg; _ } ->
        die_fatal (Printf.sprintf "%s: %s" shows_file err_msg)
    | Sexplib.Conv.Of_sexp_error
        (Sexplib.Sexp.Annotated.Conv_exn (loc, Failure err), _) ->
        die_fatal (Printf.sprintf "%s: %s " loc err)
  in
  let seen = Save.load_seen seen_file in
  total := List.length trackers;
  let%lwt new_seen =
    trackers
    |> Lwt_list.map_p (fun (rss_url, tracker_shows) ->
           (* Download and parse RSS documents *)
           let%lwt doc = Config.download rss_url in
           let%lwt torrents =
             try
               let t = torrents_of_rss_doc doc in
               Lwt.return t
             with Invalid_feed ->
               let%lwt () =
                 error_print
                   (Printf.sprintf
                      "\x1b[1m%s\x1b[0m returned an invalid document" rss_url)
               in
               Lwt.return []
           in
           incr count;
           let%lwt () = print_status () in

           (* Determine the new episodes and download them *)
           tracker_shows
           |> Lwt_list.map_s (fun (title, regexp) ->
                  let seen_eps =
                    try List.assoc title seen with Not_found -> IntMap.empty
                  in
                  let%lwt seen_eps =
                    get_new_episodes
                      ~callback:(fun (url, _) ->
                        print_endline url;
                        Lwt.return ())
                      regexp seen_eps torrents
                  in
                  Lwt.return (title, seen_eps)))
  in
  Save.save_seen seen_file (List.flatten new_seen);
  Lwt_io.printf "\r\x1b[K%!"

(* let () =
   Lwt_main.run
    ((* Load config files *)
      let trackers =
        try Save.load_trackers Config.shows_file with
        | Sys_error err -> die_fatal err
        | Failure _ ->
          die_fatal (Config.shows_file ^ ": Unbalanced left parenthesis")
        | Sexplib.Sexp.Parse_error { err_msg; _ } ->
          die_fatal (Printf.sprintf "%s: %s" Config.shows_file err_msg)
        | Sexplib.Conv.Of_sexp_error
            (Sexplib.Sexp.Annotated.Conv_exn (loc, Failure err), _) ->
          die_fatal (Printf.sprintf "%s: %s " loc err)
      in
      let seen = Save.load_seen Config.seen_file in
      total := List.length trackers;

      let%lwt new_seen =
        trackers
        |> Lwt_list.map_p (fun (rss_url, tracker_shows) ->
            (* Download and parse RSS documents *)
            let%lwt doc = Config.download rss_url in
            let%lwt torrents =
              try
                let t = torrents_of_rss_doc doc in
                Lwt.return t
              with Invalid_feed ->
                let%lwt () =
                  error_print
                    (Printf.sprintf
                       "\x1b[1m%s\x1b[0m returned an invalid document"
                       rss_url)
                in
                Lwt.return []
            in
            incr count;
            let%lwt () = print_status () in

            (* Determine the new episodes and download them *)
            tracker_shows
            |> Lwt_list.map_s (fun (title, regexp) ->
                let seen_eps =
                  try List.assoc title seen
                  with Not_found -> IntMap.empty
                in
                let%lwt seen_eps =
                  get_new_episodes
                    ~callback:(fun (url, _) ->
                        print_endline url;
                        Lwt.return ())
                    regexp seen_eps torrents
                in
                Lwt.return (title, seen_eps)))
      in
      Save.save_seen Config.seen_file (List.flatten new_seen);
      Lwt_io.printf "\r\x1b[K%!") *)
