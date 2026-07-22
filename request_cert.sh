#!/usr/bin/env bash
set -uo pipefail

HOST="https://msm.scs.lbl.gov"
OUTPUT_DIR="."
LIFETIME="12h"
KEY_NAME=""
SERVICE_USER=""
PRESET=""
LOGIN_NODE="lrc-login.lbl.gov"



usage() {
    echo "Usage: $0 [-a HOST] [-o OUTPUT_DIR] [-n KEY_NAME] [-l LIFETIME] [-s SERVICE_USER] [-p PRESET]" 1>&2
    echo "  -a HOST           MSM server host (default: https://msm.scs.lbl.gov)" 1>&2
    echo "  -o OUTPUT_DIR     Directory to store keys (default: current directory)" 1>&2
    echo "  -n KEY_NAME       Filename to store key as (default: key ID)" 1>&2
    echo "  -l LIFETIME       Certificate lifetime (default: 12h)" 1>&2
    echo "  -s SERVICE_USER   Service User to request cert for (default: none)" 1>&2
    echo "  -p PRESET         Use a pre-defined preset: lrc, brc (default: none)" 1>&2
    exit 1
}



while getopts "a:o:l:n:s:p:h" opt; do
    case $opt in
        a) HOST="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        l) LIFETIME="$OPTARG" ;;
        n) KEY_NAME="$OPTARG" ;;
        s) SERVICE_USER="$OPTARG" ;;
        p) PRESET="$OPTARG" ;;
        h|\?) usage ;;
        *) usage ;;
    esac
done



# Handle Presets
if [[ $PRESET == "lrc" ]]; then
  LRC_OUTPUT_DIR="$HOME/.ssh/ssh_certs"
  LRC_KEY_NAME="lrc_cert"
  SSH_DIR="$HOME/.ssh"
  LOGIN_NODE="lrc-login.lbl.gov"

  # Check if the location LRC_OUTPUT_DIR exists
  # and create the directory if it doesn't
  if [[ ! -d $LRC_OUTPUT_DIR ]]; then
    mkdir -p $LRC_OUTPUT_DIR
  fi
  # enforce file perm 700 for .ssh
  chmod 700 $SSH_DIR


  OUTPUT_DIR=$LRC_OUTPUT_DIR
  KEY_NAME=$LRC_KEY_NAME

elif [[ $PRESET == "brc" ]]; then
  HOST="https://msm.brc.lbl.gov"
  BRC_OUTPUT_DIR="$HOME/.ssh/ssh_certs"
  BRC_KEY_NAME="brc_cert"
  SSH_DIR="$HOME/.ssh"
  LOGIN_NODE="hpc.brc.berkeley.edu"

  # Check if the location BRC_OUTPUT_DIR exists
  # and create the directory if it doesn't
  if [[ ! -d $BRC_OUTPUT_DIR ]]; then
    mkdir -p $BRC_OUTPUT_DIR
  fi
  # enforce file perm 700 for .ssh
  chmod 700 $SSH_DIR
  OUTPUT_DIR=$BRC_OUTPUT_DIR
  KEY_NAME=$BRC_KEY_NAME

fi



# Add or verify SSH config entry so the cert is used automatically
ensure_ssh_config() {
  local host_alias="$1"
  local hostname="$2"
  local cert_user="$3"
  local key_path="$4"
  local ssh_config="$HOME/.ssh/config"

  if [[ ! -f "$ssh_config" ]]; then
    touch "$ssh_config"
    chmod 600 "$ssh_config"
  fi

  if grep -q "Host.*${host_alias}" "$ssh_config"; then
    return 0
  fi

  printf "\nHost %s %s\n    User %s\n    HostName %s\n    IdentityFile %s\n    IdentitiesOnly yes\n" \
    "$host_alias" "$hostname" "$cert_user" "$hostname" "$key_path" >> "$ssh_config"
  echo "Added SSH config entry for $host_alias"
}

# Check if an existing cert is still valid by inspecting its actual expiration
cert_is_valid() {
  local cert_file="$OUTPUT_DIR/$KEY_NAME-cert.pub"
  [[ -f "$cert_file" ]] || return 1
  python3 -c "
from datetime import datetime
import subprocess, sys
result = subprocess.run(['ssh-keygen', '-L', '-f', sys.argv[1]], capture_output=True, text=True)
for line in result.stdout.splitlines():
    if 'Valid:' in line:
        expiry = line.split('to ')[-1].strip()
        expires = datetime.fromisoformat(expiry).astimezone()
        now = datetime.now().astimezone()
        sys.exit(0 if now < expires else 1)
sys.exit(1)
" "$cert_file"
}

gen_cert() {
  TMPFILE=$(mktemp)
  trap 'rm -f "$TMPFILE"' EXIT

  echo -n "Username: "
  read -r user
  echo -n "PIN: "
  read -rs password
  echo -ne "\n"
  echo -n "OTP: "
  read -r mfa
  
  echo "Requesting cert..."
  ret=-1
  [[ -z "$SERVICE_USER" ]] && { 
    ret=$(curl --silent -o "$TMPFILE" --write-out "%{http_code}" -H "True-Client-IP: 127.0.0.1" "$HOST/v1/cert" -d "{\"username\":\"$user\",\"password\":\"$password\",\"mfa\":\"$mfa\", \"lifetime\":\"$LIFETIME\"}")
  } || {
    ret=$(curl --silent -o "$TMPFILE" --write-out "%{http_code}" -H "True-Client-IP: 127.0.0.1" "$HOST/v1/service_cert" -d "{\"username\":\"$user\",\"password\":\"$password\",\"mfa\":\"$mfa\",\"service_user\":\"$SERVICE_USER\", \"lifetime\":\"$LIFETIME\"}")
  }
  
  [[ $ret != "201" ]] && {
    echo "auth failed - status code: $ret"
    cat "$TMPFILE"
    echo -ne "\n"
    exit
  }
  
  # low-key jq
  q() {
    python3 -c "import sys, json; print(json.load(sys.stdin)['$1'].strip())"
  }
  
  # convert to local timezone
  t() {
    python3 -c "from datetime import datetime; import sys; print(datetime.fromisoformat(sys.stdin.read().strip()).astimezone().strftime('%Y-%m-%d %H:%M:%S %Z'))";
  }
  
  key_id=$(cat "$TMPFILE" | q "key_id")
  echo "key id: $key_id"
  [[ -z "$KEY_NAME" ]] && KEY_NAME="$key_id"
  
  cat "$TMPFILE" | q "public_key" > "$OUTPUT_DIR/$KEY_NAME.pub"
  cat "$TMPFILE" | q "private_key" > "$OUTPUT_DIR/$KEY_NAME"
  cat "$TMPFILE" | q "signed_public_key" > "$OUTPUT_DIR/$KEY_NAME-cert.pub"
  expires_at=$(cat "$TMPFILE" | q "expires_at" | t)
  
  chmod 600 "$OUTPUT_DIR/$KEY_NAME"
  echo "wrote key $OUTPUT_DIR/$KEY_NAME"
  echo "key expires at $expires_at"
  echo "Usage: ssh -i $OUTPUT_DIR/$KEY_NAME -l $user $LOGIN_NODE"

  echo "Done"
}



## Generate CERT
if [[ $PRESET == "lrc" ]]; then
  ## Check if there's an existing, unexpired certificate
  if cert_is_valid; then
    echo "Cert is still valid."
    echo "No need to renew."
  else
    gen_cert
    ensure_ssh_config "lrc-login" "$LOGIN_NODE" "$user" "~/.ssh/ssh_certs/$KEY_NAME"
  fi
else
  # Default
  gen_cert
fi
