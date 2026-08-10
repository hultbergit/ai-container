# ai-container

Run AI coders in a docker/podman container.

Supported:

* Claude Code with docker
* Codex CLI with docker

## Setup

### Claude Code

This repo includes `Dockerfile.claude`, which installs the `@anthropic-ai/claude-code` CLI on top of `node:24-slim`, plus common tools (`git`, `vim`, `unzip`, `jq`, etc.) and PHP 8.4. Build the image:

```shell
$ docker build -t claude-code:latest -f Dockerfile.claude .
```

Alternatively, Anthropic maintains their own Dockerfile for Claude Code, used for their VS Code extension. Clone `git@github.com:anthropics/claude-code.git`, enter the `.devcontainer` directory, and build from there instead if you'd rather track theirs directly (it also adds zsh and other niceties not included here):

```shell
$ docker build -t claude-code:latest .
```

Then you add the script `claude-container.sh` into your `$PATH` so it`s available. You can rename or alias the script if you want.

The script supports multiple "environments" allowing you to have one for work and one personal on the same computer, or different clients for instance.

The script supports configuring using docker or podman with env variable `CONTAINER_ENGINE`.

I recommend an alias in your shell profile to tie everything:

```bash
claude-work() {
    CONTAINER_ENGINE=docker \
        /usr/bin/claude-container.sh work
}
```

### The `.claude-<env>` directory

Each environment name maps to a directory on your local machine at `$HOME/.claude-<env>` (e.g. `$HOME/.claude-work`). This directory is mounted into the container at `/home/node/.claude`, which is Claude Code's config directory (`CLAUDE_CONFIG_DIR`).

Because it's just a regular directory on the host, you can edit it directly without entering the container — for example to install or manage skills, drop in `settings.json`, add `CLAUDE.md`, or manage credentials/history for that environment. Changes persist across container runs since the directory lives outside the container.

#### Installing default skills

Run these once per environment, from inside the container (e.g. `claude-work` then run the commands at the shell, or prefix each with `claude-work` to run non-interactively). They write into `$CLAUDE_CONFIG_DIR` (`/home/node/.claude`), which is the bind-mounted `.claude-<env>` directory, so the install persists across container runs — no rebuild needed, and no need to repeat it for existing environments once done.

[Matt Pocock's skills](https://github.com/mattpocock/skills) — install just the ones we use, as individual skill files (`-g` installs to `~/.claude/skills` instead of per-project):

```shell
npx skills@latest add mattpocock/skills \
	--skill code-review --skill grilling --skill grill-me --skill grill-with-docs \
	--skill handoff --skill to-spec --skill domain-modeling \
	-a claude-code -g -y
```

[caveman](https://github.com/JuliusBrussee/caveman) — installed as a full Claude Code plugin (it wires up hooks, so it needs the plugin mechanism rather than individual skill files):

```shell
claude plugin marketplace add JuliusBrussee/caveman
claude plugin install caveman@caveman
```

To add a new environment with these already in place, run the same commands once against its `.claude-<newenv>` directory before first use.

### Codex CLI

This repo includes `Dockerfile.codex`, which installs the `@openai/codex` CLI on top of `node:24-slim`. Build the image:

```shell
$ docker build -t codex:latest -f Dockerfile.codex .
```

Then add the script `codex-container.sh` into your `$PATH`, the same way as `claude-container.sh`. It supports the same `CONTAINER_ENGINE` env variable and per-environment directories.

```bash
codex-work() {
    CONTAINER_ENGINE=docker \
        /usr/bin/codex-container.sh work
}
```

If `OPENAI_API_KEY` is set in your shell when you run the script, it's passed through to the container. Alternatively, run `codex` inside the container and log in with your ChatGPT account; the resulting credentials are written to the mounted `.codex-<env>` directory and persist across runs.

### The `.codex-<env>` directory

Each environment name maps to a directory on your local machine at `$HOME/.codex-<env>` (e.g. `$HOME/.codex-work`). This directory is mounted into the container at `/home/node/.codex`, which is Codex CLI's config directory (`CODEX_HOME`), holding `auth.json`, `config.toml`, and session history for that environment.

## Network firewall

Both images apply an outbound-only firewall (`docker/init-firewall.sh`) before starting the CLI, so a compromised or confused agent (e.g. via a prompt injection) can't exfiltrate data or reach arbitrary hosts. It allows: loopback, DNS, SSH (22), GitHub's published IP ranges, the host's local network, and a per-image allowlist of domains (npm registry, `api.anthropic.com`/`statsig` for Claude, `api.openai.com`/`chatgpt.com` for Codex) — everything else is rejected.

`iptables`/`ipset` filter on IP addresses, not hostnames, so the allowlist domains can't be handed to the firewall directly. Instead, at container startup the script resolves each domain with `dig` and adds the resulting IPs to an `ipset` (same technique Anthropic's own devcontainer firewall uses, and the same one used for GitHub's IP ranges). This is a resolve-once snapshot: if a domain's IP changes later (CDN rotation, failover) while the container keeps running, traffic to the new IP is rejected until the container restarts and re-resolves. If a domain fails to resolve at startup (e.g. a stale/retired hostname), the script logs a warning and skips it rather than failing the whole boot — check the container's startup logs if something you expect to reach turns out blocked.

Because applying `iptables`/`ipset` rules requires root and the `NET_ADMIN`/`NET_RAW` capabilities, both containers now start as root and the entrypoint (`docker/entrypoint.sh`) drops down to your host uid/gid via `gosu` only after the firewall is in place — `claude-container.sh`/`codex-container.sh` pass those capabilities and your uid/gid automatically, no extra flags needed.

Two env vars, passed through from your shell if set, tune this per run:

* `EXTRA_ALLOWED_DOMAINS="foo.example.com bar.example.com"` — extend the allowlist (space-separated), e.g. if your project needs a private package registry.
* `SKIP_FIREWALL=true` — disable the firewall entirely, e.g. for a quick debugging session.

If a container engine or host doesn't grant `NET_ADMIN`/`NET_RAW` (some rootless Podman or restricted CI setups), `init-firewall.sh` will fail — use `SKIP_FIREWALL=true` in that case.

