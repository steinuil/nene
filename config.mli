open Types

val seen_file : string

val shows_file : string

val download : url -> string Lwt.t

val add_torrent : url -> unit Lwt.t
