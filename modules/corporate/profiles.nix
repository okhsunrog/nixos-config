{ lib, home }:
let
  common = ''
    #include <abstractions/base>
    #include <abstractions/nameservice>
    capability dac_override,
    capability dac_read_search,
    network inet stream,
    network inet dgram,
    network inet6 stream,
    network inet6 dgram,
    network netlink raw,
    network unix stream,
    network unix dgram,
    /run/corporate-agent-dbus/system-bus rw,
    signal (receive) peer=unconfined,
    / r,
    /etc/ r,
    /etc/** r,
    /usr/** mr,
    /bin/** mr,
    /run/current-system/** mr,
    /nix/ r,
    /nix/store/ r,
    /nix/store/** mr,
    audit /nix/store/** ix,
    audit /bin/** ix,
    /proc/ r,
    /proc/** r,
    owner /proc/[0-9]*/task/[0-9]*/comm w,
    /sys/ r,
    /sys/** r,
    /run/udev/data/** r,
    /run/systemd/resolve/** r,
    /dev/tpm[0-9]* rw,
    /dev/tpmrm[0-9]* rw,
    /opt/ r,
    /var/lib/corporate-agent-work/ r,
    audit deny /root/** rwklmx,
    audit deny /mnt/nfs{,/,/**} rwklmx,
    audit deny /etc/zfs/zroot.key rwklmx,
    audit deny /etc/{shadow,gshadow,shadow-,gshadow-,security/opasswd} r,
    audit deny /etc/ssh/*key* r,
    audit deny /etc/NetworkManager/system-connections/** r,
    audit deny /etc/{wireguard,floppa-vpn,credstore,credstore.encrypted}/** r,
    audit deny /proc/*/{mem,environ} r,
    audit deny /run/{user,secrets,secrets.d,secrets-for-users,secrets-for-users.d}/** rwklmx,
    audit deny /var/lib/{sops-nix,secureboot,sbctl,zbm-secureboot,corporate-agent-archive}/** rwklmx,
    audit deny /var/lib/floppa-vpn/** rwklmx,
  '';
in
{
  corporate-orbit = ''
    #include <tunables/global>
    profile corporate-orbit flags=(attach_disconnected) {
      ${common}
      signal (send, receive) peer=corporate-orbit,
      ptrace (read) peer=corporate-orbit,
      /opt/orbit/ rw,
      /opt/orbit/** rwkm,
      audit /opt/orbit/** ix,
      /var/log/{orbit,osquery}/ rw,
      /var/log/{orbit,osquery}/** rwk,
      /var/lib/corporate-agent-work/orbit/ rw,
      /var/lib/corporate-agent-work/orbit/** rwkm,
      audit /var/lib/corporate-agent-work/orbit/** ix,
      audit deny /home/** rwklmx,
    }
  '';
  corporate-nac = ''
    #include <tunables/global>
    profile corporate-nac flags=(attach_disconnected) {
      ${common}
      signal (send, receive) peer=corporate-nac,
      capability setuid,
      capability setgid,
      ${home}/.config/kscreenlockerrc r,
      /opt/orbit/osquery.db/ r,
      /opt/orbit/osquery.db/** r,
      /var/log/nac-agent/ rw,
      /var/log/nac-agent/** rwk,
      /var/lib/nac-agent/ rw,
      /var/lib/nac-agent/** rwk,
      /var/cache/nac-agent/ rw,
      /var/cache/nac-agent/** rwk,
      /var/lib/corporate-agent-work/nac/ rw,
      /var/lib/corporate-agent-work/nac/** rwkm,
      audit /var/lib/corporate-agent-work/nac/** ix,
    }
  '';
}
