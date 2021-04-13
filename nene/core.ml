open Types

let is_episode_new seen_eps Episode.{ number; version } =
  match Episode.Seen.find_opt number seen_eps with
  | None -> true
  | Some last_ver -> version > last_ver

let new_episodes pattern (seen_eps, new_links) Config.{ title; link } =
  match Pattern.parse_episode pattern title with
  | None -> (seen_eps, new_links)
  | Some ep ->
      if is_episode_new seen_eps ep then
        (Episode.Seen.add ep.number ep.version seen_eps, (link, ep) :: new_links)
      else (seen_eps, new_links)

let get_new_episodes ~callback pattern seen_eps torrents =
  let seen, ep_links =
    List.fold_left (new_episodes pattern) (seen_eps, []) torrents
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

let run ~trackers ~seen ~jobs:_ ~backend:_ =
  total := List.length trackers;
  let%lwt new_seen =
    trackers
    |> Lwt_list.map_p (fun Config.{ rss_url; shows } ->
           (* Download and parse RSS documents *)
           let%lwt doc = Config.download (Uri.to_string rss_url) in
           let%lwt torrents =
             match Rss.torrents_from_string doc with
             | Some t -> Lwt.return t
             | None ->
                 let%lwt () =
                   error_print
                     (Printf.sprintf
                        "\x1b[1m%s\x1b[0m returned an invalid document"
                        (Uri.to_string rss_url))
                 in
                 Lwt.return []
           in
           incr count;
           let%lwt () = print_status () in

           (* Determine the new episodes and download them *)
           shows
           |> Lwt_list.map_s (fun Config.{ name; pattern } ->
                  let seen_eps =
                    try List.assoc name seen
                    with Not_found -> Episode.Seen.empty
                  in
                  let%lwt seen_eps =
                    get_new_episodes
                      ~callback:(fun (url, _) ->
                        print_endline url;
                        Lwt.return ())
                      pattern seen_eps torrents
                  in
                  Lwt.return (name, seen_eps)))
  in
  Lwt_io.printf "\r\x1b[K%!";%lwt
  Lwt.return (List.flatten new_seen)
