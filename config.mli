open Types

val seen : string

val shows : string

val download : url -> string Lwt.t

val add_torrent : url -> unit Lwt.t
