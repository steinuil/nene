type torrent =
  { filename : string
  ; link     : string }

type episode =
  { number  : int
  ; version : int }

module IntMap : Map.S

type episode_map

type url

module Save : sig
  val load_trackers : string -> (string * (string * Str.regexp) list) list

  val load_seen : string -> (string * episode_map) list

  val save_seen : string -> (string * episode_map) list -> unit
end

module Config : sig
  val seen : string

  val trackers : string

  val download : url -> string Lwt.t

  val add_torrent : url -> unit Lwt.t
end

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
