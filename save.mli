open Types

val load_trackers : string -> (string * (string * Str.regexp) list) list

val load_seen : string -> (string * episode_map) list

val save_seen : string -> (string * episode_map) list -> unit
