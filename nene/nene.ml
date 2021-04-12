let ( let* ) = Result.bind

let ( let+ ) = Option.bind

let option_or d = function Some _ as s -> s | None -> d

let default_seen_file =
  let ( / ) = Filename.concat in
  let+ xdg_config_dir =
    match Sys.getenv_opt "XDG_CONFIG_DIR" with
    | Some dir -> Some dir
    | None -> Sys.getenv_opt "HOME" |> Option.map (fun h -> h / ".config")
  in
  Some (xdg_config_dir / "nene" / "shows.scm")

let nene config_file seen_file backend log_level style_renderer jobs =
  Fmt_tty.setup_std_outputs ?style_renderer ();
  Logs.set_level log_level;
  Logs.set_reporter (Logs_fmt.reporter ());
  let* seen_file =
    seen_file
    |> option_or default_seen_file
    |> Option.to_result
         ~none:
           (`Msg
             "Coulnd't determine the config dir, you should explicitly specify \
              the seen file with the --seen option.")
  in
  let* () =
    if jobs > 0 then Ok ()
    else Error (`Msg "Specify a number of jobs higher than 0.")
  in
  Lwt_main.run (Core.run ~shows_file:config_file ~seen_file ~jobs ~backend);
  Ok ()

open Cmdliner

let config_file =
  let doc = "Path to the config file." in
  Arg.(required & pos 0 (some file) None & info [] ~docv:"CONFIG" ~doc)

let seen_file =
  let doc =
    "Path to the file in which to store the already downloaded episodes."
  in
  Arg.(value & opt (some string) None & info [ "seen" ] ~docv:"FILE" ~doc)

type backend = Transmission | Directory

let backend =
  let backend = [ ("transmission", Transmission); ("dir", Directory) ] in
  let doc = "Which backend to use for saving the torrent files." in
  let docv = "transmission|dir" in
  Arg.(value & opt (enum backend) Directory & info [ "backend" ] ~docv ~doc)

let jobs = Arg.(value & opt int 4 & info [ "j"; "jobs" ] ~docv:"COUNT")

let nene_t =
  Term.(
    term_result
      ( const nene $ config_file $ seen_file $ backend $ Logs_cli.level ()
      $ Fmt_cli.style_renderer () $ jobs ))

let () = Term.eval (nene_t, Term.info "nene") |> Term.exit
