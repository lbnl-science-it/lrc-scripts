# `lrc-scripts`: Useful Scripts for Lawrencium

## Prerequisites

- `python3`
- `curl`
- `ssh-keygen`

## `request_cert.sh`

Requests an SSH certificate from an MSM server. When prompted, enter your username, PIN, and OTP.

### Presets

Use `-p` to select a preset, which configures the output directory, key name, and login node automatically. The `brc` preset also sets the server host.

**Lawrencium (`lrc`)**

```
./request_cert.sh -p lrc
```

Writes three files to `~/.ssh/ssh_certs/`: `lrc_cert` (private key), `lrc_cert.pub` (public key), and `lrc_cert-cert.pub` (signed certificate). If a valid (unexpired) certificate already exists, the script skips renewal and tells you. If no SSH config entry exists yet, the script adds one so you can connect with just:

```
ssh lrc-login
```

**BRC (`brc`)**

```
./request_cert.sh -p brc
```

Writes three files to `~/.ssh/ssh_certs/`: `brc_cert` (private key), `brc_cert.pub` (public key), and `brc_cert-cert.pub` (signed certificate). Unlike the `lrc` preset, this always requests a new certificate even if an unexpired one exists.

```
ssh -i ~/.ssh/ssh_certs/brc_cert -l username hpc.brc.berkeley.edu
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `-p PRESET` | Use a preset (`lrc` or `brc`) | none |
| `-a HOST` | MSM server host | `https://msm.scs.lbl.gov` |
| `-o OUTPUT_DIR` | Directory to store keys | current directory |
| `-n KEY_NAME` | Filename for the key | key ID from server |
| `-l LIFETIME` | Certificate lifetime | `12h` |
| `-s SERVICE_USER` | Request cert for a service user | none |

**Note:** When using a preset, `-o` and `-n` are overridden by the preset values. The `brc` preset also overrides `-a`. Without a preset, the printed usage hint defaults to `lrc-login.lbl.gov` as the login node.

### SSH config

The `lrc` preset automatically adds an SSH config entry if one doesn't already exist. If you need to set one up manually (e.g., for the `brc` preset), add an entry to `~/.ssh/config`:

```
Host lrc-login lrc-login.lbl.gov
    User username
    HostName lrc-login.lbl.gov
    IdentityFile ~/.ssh/ssh_certs/lrc_cert
    IdentitiesOnly yes

Host brc-login hpc.brc.berkeley.edu
    User username
    HostName hpc.brc.berkeley.edu
    IdentityFile ~/.ssh/ssh_certs/brc_cert
    IdentitiesOnly yes
```

`IdentitiesOnly yes` prevents SSH from trying other keys (e.g., from the SSH agent) before the certificate, which can cause "too many authentication failures" errors.
