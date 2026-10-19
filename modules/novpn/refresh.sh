# shellcheck shell=bash
# This host's novpn.slice owns mark 0xca6c, table 51821, and rules 90/91.
set -euo pipefail
exec 9>/run/novpn-refresh.lock
flock 9
links=$(ip -j -d link show)
for family in 4 6; do
    routes=$(ip -j -"$family" route show table main default)
    eligible=$(jq -cn --argjson links "$links" --argjson routes "$routes" '
      [$routes[] | . as $r | $links[] |
       select(.ifname == $r.dev) |
       select((.flags | index("UP")) != null) |
       select((.flags | index("LOWER_UP")) != null) |
       select((.linkinfo.info_kind // "") |
         test("^(tun|ovpn|wireguard|amneziawg|ipip|sit|gre|ip6gre|ip6tnl|vti|vti6)$") | not) |
       $r | select((.type // "unicast") == "unicast") |
       select((.flags // [] | index("linkdown")) == null)] |
       sort_by(.metric // 0) | .[:1]')
    # Keep a terminal route while updating so marked traffic never falls into VPN routes.
    ip -"$family" route replace unreachable default metric 42760 table 51821
    if ! ip -j -"$family" rule show | jq -e '.[] | select(.priority == 90 and (.table | tostring) == "51821" and .fwmark == "0xca6c")' >/dev/null; then
        ip -"$family" rule add priority 90 fwmark 0xca6c lookup 51821
    fi
    if ! ip -j -"$family" rule show | jq -e '.[] | select(.priority == 91 and .fwmark == "0xca6c" and .action == "unreachable")' >/dev/null; then
        ip -"$family" rule add priority 91 fwmark 0xca6c unreachable
    fi
    ip -"$family" route flush table 51821 type unicast
    while IFS=$'\t' read -r dev gateway; do
        [[ -n "$dev" ]] || continue
        # Preserve directly attached LAN routes, but no routes installed by either VPN.
        while IFS= read -r prefix; do
            [[ -n "$prefix" ]] || continue
            ip -"$family" route replace "$prefix" dev "$dev" table 51821
        done < <(ip -j -"$family" route show table main dev "$dev" | jq -r '.[] | select(.dst != "default" and .protocol == "kernel" and .gateway == null) | .dst')
        args=(default)
        [[ "$gateway" == "-" ]] || args+=(via "$gateway" onlink)
        ip -"$family" route replace "${args[@]}" dev "$dev" metric 100 table 51821
    done < <(jq -r '.[] | [.dev, (.gateway // "-")] | @tsv' <<<"$eligible")
done
# nft resolves the cgroup ID at load time; refresh after the user anchor starts.
if [[ -d /sys/fs/cgroup/@cgroup@ ]]; then
    nft -f @rules@
fi
