{
  lib,
  entries,
  base,
}:
let
  datasets =
    policy:
    lib.listToAttrs (
      lib.mapAttrsToList (_: e: lib.nameValuePair e.dataset true) (
        lib.filterAttrs (_: e: e.enable && policy e.backup) entries
      )
    );
  snap = datasets (p: p != "none");
  push = datasets (p: p == "mira");
in
base
// {
  jobs = lib.concatMap (
    job:
    let
      filesystems = if job.type == "snap" then snap else push;
    in
    lib.optional (filesystems != { }) (job // { inherit filesystems; })
  ) base.jobs;
}
