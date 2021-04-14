module Torrent = struct
  let is_new _ _ _ = None
end

let ( let* ) = Lwt.bind

let fetch_rss ~fetch ~seen Config.{ rss_url; shows } =
  let* rss_doc = fetch rss_url in
  Rss.torrents_from_string rss_doc
  |> Option.map (List.filter_map (Torrent.is_new shows seen))
  |> Lwt.return

let download_torrent ~backend (t : Config.torrent) ep_n =
  try%lwt
    let* () = backend t in
    Lwt.return (Some (t.filename, ep_n))
  with _ -> Lwt.return None
