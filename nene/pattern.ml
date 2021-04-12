type t = { regexp : Re.re; episode : int; version : int }

let ( let* ) = Option.bind

let around sep input =
  let around_re =
    let open Re in
    [
      group (seq [ bos; non_greedy (rep any) ]);
      str sep;
      group (seq [ rep any; eos ]);
    ]
    |> seq |> compile
  in
  let* groups = Re.exec_opt around_re input in
  match Re.Group.(get groups 1, get groups 2) with
  | exception Not_found -> None
  | before, after -> Some (before, after)

let%test "around returns the string before and the string after sep" =
  around "<ep>" "Kaemono Friends <ep> [**].mkv"
  = Some ("Kaemono Friends ", " [**].mkv")

let%test "around returns two empty strings if sep = input" =
  around "<ep>" "<ep>" = Some ("", "")

let%test "around returns None if it doesn't find sep in its input" =
  around "<ep>" "aaa <episode>" = None

module Glob = struct
  let is_not_empty_string = function `String "" -> false | _ -> true

  let condense_globs acc token =
    match (acc, token) with `Glob :: _, `Glob -> acc | _ -> token :: acc

  let condense_globs ls = List.fold_left condense_globs [] ls |> List.rev

  let%test "condense_globs merges multiple contiguous globs into one" =
    condense_globs [ `String "a"; `Glob; `Glob; `Glob; `String "b"; `Glob ]
    = [ `String "a"; `Glob; `String "b"; `Glob ]

  let rec parse acc input =
    match around "**" input with
    | Some (before, after) -> parse (`Glob :: `String before :: acc) after
    | None -> List.rev (`String input :: acc)

  let parse input =
    parse [] input |> List.filter is_not_empty_string |> condense_globs

  let%test "parse parses ** into a glob" =
    parse "abc**de" = [ `String "abc"; `Glob; `String "de" ]

  let%test "parse returns a list with a single string if no globs are found" =
    parse "abcde" = [ `String "abcde" ]

  let%test "parse merges multiple globs into one and removes empty strings" =
    parse "**********" = [ `Glob ]

  let to_re =
    Re.(function `String string -> str string | `Glob -> non_greedy (rep any))

  let of_string input = parse input |> List.map to_re
end

let episode_regexp =
  Re.(
    seq [ group (repn digit 1 (Some 4)); opt (seq [ char 'v'; group digit ]) ])

let group_get_opt groups n =
  if Re.Group.test groups n then Some (Re.Group.get groups n) else None

let parse_episode { regexp; episode; version } input =
  let* groups = Re.exec_opt regexp input in
  let* episode = group_get_opt groups episode in
  let* episode = int_of_string_opt episode in
  let version =
    let* version = group_get_opt groups version in
    int_of_string_opt version
  in
  Some
    Episode_num.{ number = episode; version = Option.value version ~default:1 }

let%test "parse_episode with both episode and version" =
  parse_episode
    { regexp = Re.compile episode_regexp; episode = 1; version = 2 }
    "12v2"
  = Some Episode_num.{ number = 12; version = 2 }

let%test "parse_episode without version" =
  parse_episode
    { regexp = Re.compile episode_regexp; episode = 1; version = 2 }
    "12"
  = Some Episode_num.{ number = 12; version = 1 }

let%test "parse episode returns None on fail" =
  parse_episode
    { regexp = Re.compile episode_regexp; episode = 1; version = 2 }
    "abcv"
  = None

let%test "real episode" =
  parse_episode
    {
      regexp =
        Re.Perl.compile_pat
          {|\[MoyaiSubs\] Godzilla Singular Point - (\d+) (\[v(\d+)\])?|};
      episode = 1;
      version = 3;
    }
    "[MoyaiSubs] Godzilla Singular Point - 02 (Web 1080p AAC) [CB0B7D8F].mkv"
  = Some Episode_num.{ number = 2; version = 1 }

let compile input =
  let* before, after = around "<episode>" input in
  let regexp = Glob.(of_string before @ (episode_regexp :: of_string after)) in
  let regexp = Re.(seq ((bos :: regexp) @ [ eos ]) |> compile) in
  Some { regexp; episode = 1; version = 2 }

let%test "compile" =
  parse_episode
    (Option.get (compile "abcd<episode>tfw**as"))
    "abcd1v2tfwasdasdas"
  = Some Episode_num.{ number = 1; version = 2 }

let%test "compile" =
  let pattern =
    "[MoyaiSubs] Godzilla Singular Point - <episode> (Web 1080p AAC) [**].mkv"
  in
  parse_episode
    (Option.get (compile pattern))
    "[MoyaiSubs] Godzilla Singular Point - 03 (Web 1080p AAC) [CB0B7D8F].mkv"
  = Some Episode_num.{ number = 3; version = 1 }

let compile_perl_regexp str ~episode_idx ~version_idx =
  let regexp = Re.Perl.compile_pat str in
  { regexp; episode = episode_idx; version = version_idx }
