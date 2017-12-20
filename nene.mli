open Types

exception Invalid_feed
  (** Raised when trying to parse invalid RSS documents. *)

val torrents_of_rss_doc : string -> torrent list
  (** Parse an RSS document into a list of torrents.
      @raise Invalid_feed when the document is not valid RSS. *)

val parse_episode_filename : Str.regexp -> string -> episode option
  (** Attempt to parse an episode filename using a regexp. *)

val get_new_episodes : callback : (url * episode -> unit Lwt.t) -> Str.regexp -> episode_map -> torrent list -> episode_map Lwt.t
  (** Loop over a list of torrents and return the updated list of
      seen episodes, running a callback on their links. *)

val format_show : title -> episode -> string
