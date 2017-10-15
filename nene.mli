open Types

val torrents_of_rss_doc : string -> torrent list

val episode_of_filename : Str.regexp -> string -> episode

val new_episodes
  : Str.regexp
  -> episode_map * (url * episode) list
  -> torrent
  -> episode_map * (url * episode) list

val filter_new_eps
  : (string * episode_map) list
  -> (string * Str.regexp) list
  -> torrent list
  -> (string * episode_map * (url * episode) list) list

val print_show : string -> episode -> unit

val main : unit -> unit Lwt.t
