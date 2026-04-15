#!/bin/bash

# This script does the following things
# * Start a vault instance with vault/vault.json configuration
# * Unseal the vault
# * Create a v2 kv engine
# * Prints the unseal keys and root token
# * This script does not automatically unseal vault on restarts, it only works with fresh installations

COMPOSE_FILE="${1:-docker-compose.yml}"
SERVICE_NAME="${2:-vault}"

echo "Setting up $SERVICE_NAME in $COMPOSE_FILE"

docker-compose -f "$COMPOSE_FILE" up -d "$SERVICE_NAME"

# Function to check if Vault is ready
check_vault_status() {
  vault_status=$(docker-compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" vault status 2>&1)
  if [[ $vault_status == *"connection refused"* ]]; then
    echo "Unable to connect to Vault. Waiting for Vault to start..."
    return 1
  elif [[ $vault_status == *"Sealed             true"* ]]; then
    echo "Vault is sealed. Waiting for unsealing..."
    return 0
  else
    echo "Unsealed and up. Moving to next steps."
    return 0
  fi
}


# Wait for Vault service to become available
until check_vault_status; do
    echo "Waiting for Vault service to start..."
    sleep 1;
done


# Remove colors for reliable matching
clean_vault_status=$(echo "$vault_status" | sed 's/\x1B\[[0-9;]*[JKmsu]//g')

if echo "$clean_vault_status" | grep -q "Initialized.*true"; then
    echo "Vault is initialized."
    # Check if keys.txt exists and has content (size > 0)
    if [ -s "keys.txt" ]; then
        echo "keys.txt found. Unsealing..."
    else
        echo "CRITICAL ERROR: Vault is initialized (locked) but keys.txt is missing or empty!"
        echo "Unable to unseal. You must restore keys.txt or wipe vault-data to reset."
        exit 1
    fi
else
    echo "Vault is NOT initialized. Starting fresh setup..."
    # keys contains ansi escape sequences, remove them if any
    docker-compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" vault operator init > ansi-keys.txt
    sed 's/\x1B\[[0-9;]*[JKmsu]//g' < ansi-keys.txt  > keys.txt
fi

sed -n 's/Unseal Key 1: \(.*\)/\1/p' keys.txt > parsed-key.txt
key=$(cat parsed-key.txt)
docker-compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" vault operator unseal "$key" < /dev/null

sed -n 's/Unseal Key 2: \(.*\)/\1/p' keys.txt > parsed-key.txt
key=$(cat parsed-key.txt)
docker-compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" vault operator unseal "$key" < /dev/null

sed -n 's/Unseal Key 3: \(.*\)/\1/p' keys.txt > parsed-key.txt
key=$(cat parsed-key.txt)
docker-compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" vault operator unseal "$key" < /dev/null

root_token=$(sed -n 's/Initial Root Token: \(.*\)/\1/p' keys.txt | tr -dc '[:print:]')

if echo "$clean_vault_status" | grep -q "Initialized.*true"; then
    echo "Vault is initialized already. Skipping creating a KV engine"
else
  # Use a temporary file for compatibility with both GNU and BSD sed
  sed "s/VAULT_TOKEN=.*/VAULT_TOKEN=$root_token/" ".env" > ".env.tmp" && mv ".env.tmp" ".env"
  docker-compose -f "$COMPOSE_FILE" exec -e VAULT_TOKEN=$root_token -T "$SERVICE_NAME" vault secrets enable -path=kv kv-v2
fi

echo -e "\nNOTE: KEYS ARE STORED IN keys.txt"

if [ -f "ansi-keys.txt" ] ; then
    rm ansi-keys.txt
fi

if [ -f "parsed-key.txt" ] ; then
    rm parsed-key.txt
fi
