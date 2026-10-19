# Run only in a disposable VM with a writable overlay store. The fixture's
# tiny signed payloads test the signing pipeline, not loading kernel ELF files.
{ pkgs, zbm-rs }:
let
  header = pkgs.writeText "fixture-module-header.py" ''
    import struct, sys
    from pathlib import Path
    file = Path(sys.argv[1])
    signature = file.with_suffix(".cms").read_bytes()
    with file.open("ab") as stream:
        stream.write(signature + bytes([0, 0, 2, 0, 0, 0, 0, 0])
                     + struct.pack(">I", len(signature))
                     + b"~Module signature appended~\n")
  '';
  signFile = pkgs.writeShellScript "fixture-sign-file" ''
    set -euo pipefail
    ${pkgs.openssl}/bin/openssl cms -sign -binary -noattr -nocerts -outform DER \
      -signer "$3" -inkey "$2" -in "$4" -out "''${4%.ko}.cms"
    ${pkgs.uv}/bin/uv run --offline --no-project --no-managed-python \
      --python ${pkgs.python3}/bin/python3 ${header} "$4"
    rm "''${4%.ko}.cms"
  '';
  unsigned =
    version:
    pkgs.runCommand "disposable-module-${version}" { } ''
      mkdir -p $out/lib/modules/test
      printf 'disposable module ${version}\n' > $out/lib/modules/test/probe.ko
    '';
  first = unsigned "first";
  changed = unsigned "changed";
in
pkgs.writeShellApplication {
  name = "framework-signing-integration";
  runtimeInputs = [
    pkgs.uv
    pkgs.python3
    pkgs.openssl
    pkgs.nix
    pkgs.jq
    pkgs.systemd
  ];
  text = ''
    systemd-detect-virt --vm >/dev/null || {
      echo 'This destructive fixture is only for a disposable VM.' >&2
      exit 1
    }
    if [[ -e /var/lib/secureboot/db.key || -e /var/lib/zbm-rs-public/framework-modules ]]; then
      echo 'Refusing to replace existing signing keys or modules.' >&2
      exit 1
    fi
    install -d -m700 /var/lib/secureboot
    openssl req -new -x509 -newkey rsa:2048 -nodes -days 1 \
      -subj /CN=disposable-vm-only -keyout /var/lib/secureboot/db.key \
      -out /var/lib/secureboot/db.pem 2>/dev/null
    certificate=$(nix-store --add /var/lib/secureboot/db.pem)
    jq -n --arg cert "$certificate" '{
      version: 1,
      kernel: "${pkgs.linuxPackages.kernel}",
      module_version: "test",
      unsigned: "${first}",
      certificate: $cert,
      sign_file: "${signFile}",
      signer: "${zbm-rs}/nix/sign-module-tree.py",
      python: "${pkgs.python3}/bin/python3",
      uv: "${pkgs.uv}/bin/uv",
      nix_store: "${pkgs.nix}/bin/nix-store",
      tool_path: "${
        pkgs.lib.makeBinPath [
          pkgs.openssl
          pkgs.zstd
        ]
      }"
    }' > /root/module-plan.json
    plan=$(nix-store --add /root/module-plan.json)
    run_signer() {
      uv run --offline --no-project --no-managed-python --python ${pkgs.python3}/bin/python3 \
        ${../scripts/sign-framework-modules.py} "$1"
    }
    run_signer "$plan"
    test "$(find /var/lib/zbm-rs-signing/roots -name '*.plan' -type l | wc -l)" = 1
    cache_root=$(find /var/lib/zbm-rs-signing/roots -type l -print -quit)
    nix-store --query --roots "$(readlink -e "$cache_root")" | grep -F /var/lib/zbm-rs-signing/roots/
    module=/var/lib/zbm-rs-public/framework-modules/lib/modules/test/probe.ko
    before=$(sha256sum "$module")
    run_signer "$plan" 2>/root/module-cache.log
    grep -q 'Reusing cached signed modules' /root/module-cache.log
    test "$before" = "$(sha256sum "$module")"
    jq --arg src "${changed}" '.unsigned = $src' /root/module-plan.json > /root/changed-plan.json
    changed_plan=$(nix-store --add /root/changed-plan.json)
    run_signer "$changed_plan"
    test "$before" != "$(sha256sum "$module")"
    jq -e --arg src "${changed}" '.unsigned_module_store_path == $src and .signed_modules == 1' \
      /var/lib/zbm-rs-public/framework-modules/zbm-module-manifest.json
    echo 'Module signing, immutable-store import, cache reuse and same-ABI source change passed.'
  '';
}
