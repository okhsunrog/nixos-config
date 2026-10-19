{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "novpn-routing";
  nodes = {
    client = { ... }: {
      imports = [ ../modules/novpn ];
      virtualisation.vlans = [
        1
        2
      ];
      networking.useDHCP = false;
      networking.interfaces.eth1.ipv4.addresses = [
        {
          address = "192.168.1.1";
          prefixLength = 24;
        }
      ];
      networking.interfaces.eth1.ipv6.addresses = [
        {
          address = "2001:db8:1::1";
          prefixLength = 64;
        }
      ];
      networking.interfaces.eth2.ipv4.addresses = [
        {
          address = "192.168.2.1";
          prefixLength = 24;
        }
      ];
      networking.defaultGateway = "192.168.1.2";
      networking.defaultGateway6 = {
        address = "2001:db8:1::2";
        interface = "eth1";
      };
      networking.firewall = {
        enable = true;
        backend = "firewalld";
        checkReversePath = "loose";
      };
      services.firewalld.enable = true;
      networking.nftables.enable = true;
      services.novpn = {
        enable = true;
        user = "tester";
      };
      users.users.tester = {
        isNormalUser = true;
        uid = 1000;
        linger = true;
      };
      environment.systemPackages = [
        pkgs.curl
        pkgs.jq
        pkgs.nftables
        pkgs.python3
      ];
    };
    uplink = { ... }: {
      virtualisation.vlans = [
        1
        2
      ];
      networking.useDHCP = false;
      networking.firewall.enable = false;
      networking.interfaces.eth1.ipv4.addresses = [
        {
          address = "192.168.1.2";
          prefixLength = 24;
        }
      ];
      networking.interfaces.eth1.ipv6.addresses = [
        {
          address = "2001:db8:1::2";
          prefixLength = 64;
        }
      ];
      networking.interfaces.eth2.ipv4.addresses = [
        {
          address = "192.168.2.2";
          prefixLength = 24;
        }
      ];
      networking.interfaces.lo.ipv4.addresses = [
        {
          address = "198.18.0.1";
          prefixLength = 32;
        }
      ];
      networking.interfaces.lo.ipv6.addresses = [
        {
          address = "2001:db8:99::1";
          prefixLength = 128;
        }
      ];
      systemd.services.http = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig.ExecStart = "${pkgs.python3}/bin/python -m http.server 8080 --bind ::";
      };
    };
  };
  testScript = ''
    start_all()
    uplink.wait_for_unit("http.service")
    uplink.succeed("ip addr add 198.18.0.1/32 dev lo; ip -6 addr add 2001:db8:99::1/128 dev lo")
    client.wait_for_unit("multi-user.target")
    client.wait_for_unit("user@1000.service")
    user = "runuser -u tester -- env XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus "
    client.succeed(user + "systemctl --user start novpn-anchor")
    client.succeed(user + "sudo -n ${pkgs.systemd}/bin/systemctl restart novpn-firewall.service")
    # Model Floppa's full-tunnel rules without a real VPN or provider credentials.
    client.succeed("ip tuntap add dev vpn-test mode tun; ip addr add 10.66.66.1/24 dev vpn-test; ip link set vpn-test up; ip route add default dev vpn-test table 1718382448; ip rule add priority 31000 not fwmark 0x666c6f70 lookup main suppress_prefixlength 0; ip rule add priority 31010 not fwmark 0x666c6f70 lookup 1718382448")
    client.succeed("ip -6 addr add fd66::1/64 dev vpn-test; ip -6 route add default dev vpn-test table 1718382448; ip -6 rule add priority 31000 not fwmark 0x666c6f70 lookup main suppress_prefixlength 0; ip -6 rule add priority 31010 not fwmark 0x666c6f70 lookup 1718382448")
    client.fail("curl --noproxy '*' --max-time 3 -fsS http://198.18.0.1:8080")
    def direct(url):
        return user + "systemd-run --user --wait --pipe --collect --slice=novpn.slice curl --noproxy '*' --max-time 5 -fsS " + url
    try:
        client.succeed(direct("http://198.18.0.1:8080"))
    except Exception:
        print(client.succeed("ip -4 rule; ip -4 route show table 51821; ip -4 route get 198.18.0.1 mark 0xca6c; nft list ruleset; sysctl net.ipv4.conf.all.rp_filter net.ipv4.conf.eth1.rp_filter"))
        print(uplink.succeed("ip addr; ip route; journalctl -u http --no-pager"))
        raise
    client.succeed(direct("http://[2001:db8:99::1]:8080"))
    client.succeed("nft list table inet novpn | grep -E 'counter packets [1-9]'")
    # A corporate split default in main must never become a direct default.
    client.succeed("ip tuntap add dev corp-test mode tun; ip link set corp-test up; ip route add 0.0.0.0/1 dev corp-test; ip route add 128.0.0.0/1 dev corp-test")
    client.succeed("systemctl restart novpn-firewall")
    client.succeed(direct("http://198.18.0.1:8080"))
    # Switch the physical default, as after Ethernet/Wi-Fi/USB network changes.
    client.succeed("ip route replace default via 192.168.2.2 dev eth2; systemctl restart novpn-firewall")
    client.succeed("ip route get 198.18.0.1 mark 0xca6c | grep eth2")
    client.succeed(direct("http://198.18.0.1:8080"))
    # No physical default: do not fall back into either VPN.
    client.succeed("ip route del default; systemctl restart novpn-firewall")
    client.fail(direct("http://198.18.0.1:8080"))
    client.fail("ip route get 198.18.0.1 mark 0xca6c")
    # Re-resolve the cgroup after a user unit is recreated.
    client.succeed("ip route add default via 192.168.1.2 dev eth1")
    client.succeed(user + "systemctl --user stop novpn-anchor novpn.slice")
    client.succeed(user + "systemctl --user start novpn-anchor")
    client.succeed(user + "sudo -n ${pkgs.systemd}/bin/systemctl restart novpn-firewall.service")
    client.succeed(direct("http://198.18.0.1:8080"))
  '';
}
