#!/usr/bin/env bash
# Deploys (or updates) the Subcipher stack on a Docker Swarm.
#
#   scripts/deploy.sh            # or: make deploy
#
# Reads the settings from deploy/.env (see deploy/.env.example) and runs
# `docker stack deploy` on the Docker context DEPLOY_CONTEXT (default
# "subcipher-server"), created once with:
#
#   docker context create subcipher-server --docker "host=ssh://USER@192.168.1.50"
#
# The swarm pulls the image from ghcr.io with your local registry login
# (`docker login ghcr.io`), unless the package is public.
set -euo pipefail

cd "$(dirname "$0")/.."

context="${DEPLOY_CONTEXT:-subcipher-server}"
stack="${STACK_NAME:-subcipher}"

if [[ ! -f deploy/.env ]]; then
  echo "deploy/.env is missing: copy deploy/.env.example and fill it in." >&2
  exit 1
fi

# The variables of deploy/.env, for the interpolation of deploy/stack.yaml.
set -a
# shellcheck disable=SC1091
source deploy/.env
set +a

docker --context "$context" stack deploy \
  --with-registry-auth \
  --resolve-image always \
  --prune \
  -c deploy/stack.yaml \
  "$stack"

echo
echo "Deployed. Follow it with:"
echo "  docker --context $context stack ps $stack"
echo "  docker --context $context service logs -f ${stack}_app"
