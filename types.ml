type torrent =
  { filename : string
  ; link     : string }

type episode =
  { number  : int
  ; version : int }

module IntMap = Map.Make(struct
  type t = int
  let compare = Pervasives.compare
end)

type episode_map = int IntMap.t

type url = string
