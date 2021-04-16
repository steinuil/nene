open Lwt.Syntax
open Lwt.Infix

let torrents_from_rss rss_url =
  match%lwt Backend.download rss_url >|= Rss.torrents_from_string with
  | Some torrents -> Lwt.return torrents
  | None ->
      Format.printf "[WARN] invalid RSS feed returned: %a\n" Uri.pp rss_url;
      Lwt.return []
  | exception _ ->
      Format.printf "[WARN] couldn't fetch RSS feed: %a\n" Uri.pp rss_url;
      Lwt.return []

let ( let+ ) = Option.bind

let pp_episode out (name, Episode.{ number; version }) =
  if version = 1 then Format.fprintf out "%s - %d" name number
  else Format.fprintf out "%s - %dv%d" name number version

let run ~trackers ~seen ~jobs:_ ~backend =
  let%lwt new_seen =
    Lwt_list.map_p
      (fun Config.{ rss_url; shows } ->
        let* torrents = torrents_from_rss rss_url in
        List.filter_map
          (fun torrent ->
            let+ name, ep = Seen.parse shows torrent.Config.filename in
            if Seen.is_new seen name ep then Some ((name, ep), torrent)
            else None)
          torrents
        |> Lwt_list.filter_map_s (fun (seen, torrent) ->
               try%lwt
                 backend torrent;%lwt
                 Format.printf "[INFO] added torrent: %a\n" pp_episode seen;
                 Lwt.return (Some seen)
               with
               | Backend.Add_torrent_failure f ->
                   Format.printf
                     "[WARN] couldn't add torrent %a to Transmission: %s\n"
                     Config.pp_torrent torrent f;

                   Lwt.return None
               | Backend.Request_error _ ->
                   Format.printf "[WARN] couldn't add torrent %a\n"
                     Config.pp_torrent torrent;
                   Lwt.return None))
      trackers
  in
  List.flatten new_seen |> Seen.merge seen |> Lwt.return
