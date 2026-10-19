#!/usr/bin/env bash
# OpenVPN runs up-scripts with a minimal PATH, so locate our tools explicitly.
# /run/wrappers/bin + /run/current-system/sw/bin cover NixOS; the rest cover FHS distros.
export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

resolvectl_bin="@RESOLVECTL@"

# OpenVPN passes the tun device as $1 and every server-pushed option as
# foreign_option_1..N, e.g. "dhcp-option DNS 172.21.0.1" / "dhcp-option DOMAIN vk.team".
dev="$1"

dns=()
domains=()
i=1
while true; do
    var="foreign_option_$i"
    val="${!var-}"
    [ -z "$val" ] && break
    case "$val" in
        "dhcp-option DNS "*)
            dns+=("${val#dhcp-option DNS }")
            ;;
        "dhcp-option DOMAIN "*)
            read -r d _ <<<"${val#dhcp-option DOMAIN }"
            [ -n "$d" ] && domains+=("$d")
            ;;
    esac
    i=$((i + 1))
done

echo "Pushed DNS: ${dns[*]:-<none>}"
echo "Pushed DOMAIN count: ${#domains[@]}"

if [ "${#dns[@]}" -eq 0 ]; then
    echo "No DNS pushed by the server, leaving resolvectl untouched" >&2
    exit 0
fi

# Share the suffix list with the existing corporate VPN DNS hook.
# Corporate DNS must not become the resolver for unrelated Internet names.
if [ -r /etc/openvpn/barbos-dns-domains ]; then
    mapfile -t local_domains < <(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' /etc/openvpn/barbos-dns-domains)
    domains+=("${local_domains[@]}")
fi
routing_domains=()
for domain in "${domains[@]}"; do
    domain="${domain#\~}"
    case "$domain" in
        ''|.) continue ;;
    esac
    routing_domains+=("~$domain")
done
if [ "${#routing_domains[@]}" -eq 0 ]; then
    echo "No corporate routing domains configured; refusing catch-all DNS" >&2
    exit 1
fi
sudo -n "$resolvectl_bin" dns "$dev" "${dns[@]}" || exit 1
sudo -n "$resolvectl_bin" domain "$dev" "${routing_domains[@]}" || exit 1
sudo -n "$resolvectl_bin" default-route "$dev" no
