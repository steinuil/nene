type torrent =
  { filename : string
  ; link     : string }

type episode =
  { number  : int
  ; version : int }

val torrents_of_rss_doc : string -> torrent list

val fetch_torrents : string -> (torrent list) Lwt.t

val episode_of_filename : Str.regexp -> string -> episode

val new_episodes
  : Str.regexp
  -> (int * int) list * (string * episode) list
  -> torrent
  -> (int * int) list * (string * episode) list

val filter_new_eps
  : (string * (int * int) list) list
  -> (string * Str.regexp) list
  -> torrent list
  -> (string * (int * int) list * (string * episode) list) list

val print_show : string -> episode -> unit

val main : unit -> unit Lwt.t
