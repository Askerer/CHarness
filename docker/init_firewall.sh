#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ALLOWED_DOMAINS_FILE="/etc/codex/allowed_domains.txt"
if [ -f "$ALLOWED_DOMAINS_FILE" ]; then
    ALLOWED_DOMAINS=()
    while IFS= read -r domain; do
        [[ -z "$domain" ]] && continue
        ALLOWED_DOMAINS+=("$domain")
    done < "$ALLOWED_DOMAINS_FILE"
elif [ -n "${OPENAI_ALLOWED_DOMAINS:-}" ]; then
    IFS=' ,' read -r -a ALLOWED_DOMAINS <<< "$OPENAI_ALLOWED_DOMAINS"
else
    ALLOWED_DOMAINS=("api.openai.com")
fi

if [ ${#ALLOWED_DOMAINS[@]} -eq 0 ]; then
    echo "ERROR: No allowed domains specified" >&2
    exit 1
fi

iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# Allow DNS and loopback
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

ipset create allowed-domains hash:net

for domain in "${ALLOWED_DOMAINS[@]}"; do
    ips=$(dig +short A "$domain")
    if [ -z "$ips" ]; then
        echo "ERROR: Failed to resolve $domain" >&2
        exit 1
    fi
    while read -r ip; do
        if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            ipset add allowed-domains "$ip" -exist
        fi
    done < <(echo "$ips")
done

HOST_IP=$(ip route | awk '/default/ {print $3; exit}')
if [ -n "$HOST_IP" ]; then
    HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
    iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
    iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT
fi

iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

iptables -A INPUT -p tcp -j REJECT --reject-with tcp-reset
iptables -A INPUT -p udp -j REJECT --reject-with icmp-port-unreachable
iptables -A OUTPUT -p tcp -j REJECT --reject-with tcp-reset
iptables -A OUTPUT -p udp -j REJECT --reject-with icmp-port-unreachable
iptables -A FORWARD -p tcp -j REJECT --reject-with tcp-reset
iptables -A FORWARD -p udp -j REJECT --reject-with icmp-port-unreachable
