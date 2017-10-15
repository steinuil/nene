type torrent =
  { filename : string
  ; link     : string }

type episode =
  { number  : int
  ; version : int }

module IntMap : Map.S with type key = int

type episode_map =
  int IntMap.t

type url = string
