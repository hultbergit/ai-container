#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Restrict the container to an outbound allowlist so a compromised or
# confused agent (e.g. via prompt injection) can't exfiltrate data or
# reach arbitrary hosts. Must run as root, before privileges are dropped.

iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)
if [ -n "$DOCKER_DNS_RULES" ]; then
	echo "Restoring Docker DNS rules..."
	iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
	iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
	echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
fi

iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

ipset create allowed-domains hash:net

echo "Fetching GitHub IP ranges..."
gh_meta_cache="/home/node/.claude/gh-meta-cache.json"
gh_ranges=""
for attempt in 1 2 3; do
	gh_ranges=$(curl -s --fail --max-time 10 https://api.github.com/meta || true)
	if [ -n "$gh_ranges" ] && echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null 2>&1; then
		mkdir -p "$(dirname "$gh_meta_cache")"
		echo "$gh_ranges" >"$gh_meta_cache"
		break
	fi
	gh_ranges=""
	sleep 2
done

if [ -z "$gh_ranges" ]; then
	echo "WARNING: failed to fetch GitHub IP ranges, trying cache at $gh_meta_cache" >&2
	if [ -f "$gh_meta_cache" ] && gh_ranges=$(cat "$gh_meta_cache") && echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null 2>&1; then
		echo "Using cached GitHub IP ranges from $gh_meta_cache" >&2
	else
		echo "ERROR: failed to fetch GitHub IP ranges and no valid cache available" >&2
		exit 1
	fi
fi

while read -r cidr; do
	[[ "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]] || continue
	ipset add -exist allowed-domains "$cidr"
done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)

# ALLOWED_DOMAINS is baked in per image; EXTRA_ALLOWED_DOMAINS can extend it at runtime.
IFS=' ' read -ra domains <<<"${ALLOWED_DOMAINS:-} ${EXTRA_ALLOWED_DOMAINS:-}"
for domain in "${domains[@]}"; do
	[ -n "$domain" ] || continue
	echo "Resolving $domain..."
	ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')
	if [ -z "$ips" ]; then
		echo "WARNING: failed to resolve $domain, skipping" >&2
		continue
	fi
	while read -r ip; do
		[[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || continue
		ipset add -exist allowed-domains "$ip"
	done <<<"$ips"
done

HOST_IP=$(ip route | awk '/^default/ {print $3; exit}')
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
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

echo "Firewall configured. Allowed domains: ${ALLOWED_DOMAINS:-} ${EXTRA_ALLOWED_DOMAINS:-}"
