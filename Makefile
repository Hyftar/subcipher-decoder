# Common development commands. Run `make help` for the list.
#
# Commands run inside the Nix environment: directly if you are already in
# `nix-shell` / `nix develop` / direnv, otherwise wrapped in `nix-shell --run`.

ifdef IN_NIX_SHELL
  RUN = bash -c
else
  RUN = nix-shell --run
endif

.DEFAULT_GOAL := help
.PHONY: help setup start iex db-up db-down db-logs db-reset psql mail deploy \
        test test-js precommit format assets fixtures clean

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

setup: db-up ## First-time setup: deps, database, assets
	$(RUN) 'mix setup'

start: db-up ## Start the database and the Phoenix server (http://localhost:4000)
	$(RUN) 'mix phx.server'

iex: db-up ## Start the server inside IEx
	$(RUN) 'iex -S mix phx.server'

db-up: ## Start PostgreSQL and MailDev (Docker) and wait until they are ready
	$(RUN) 'docker compose up -d --wait'

db-down: ## Stop PostgreSQL and MailDev (data is kept)
	$(RUN) 'docker compose down'

db-logs: ## Follow PostgreSQL logs
	$(RUN) 'docker compose logs -f db'

db-reset: db-up ## Drop, recreate, migrate and seed the dev database
	$(RUN) 'mix ecto.reset'

mail: ## Open the MailDev inbox (emails sent in development)
	@echo "MailDev: http://localhost:$${MAILDEV_WEB_PORT:-1080}"
	-@xdg-open "http://localhost:$${MAILDEV_WEB_PORT:-1080}" >/dev/null 2>&1

deploy: ## Deploy or update the stack on the Docker Swarm (deploy/.env, see README)
	./scripts/deploy.sh

psql: db-up ## Open a psql shell on the dev database
	$(RUN) 'psql postgres://postgres:postgres@localhost:$${POSTGRES_PORT:-5432}/subcipher_dev'

test: db-up ## Run the Elixir test suite
	$(RUN) 'mix test'

test-js: ## Run the JS detector tests (Node)
	$(RUN) 'mix test.js'

precommit: db-up ## Compile (warnings as errors), format, run all tests
	$(RUN) 'mix precommit'

format: ## Format Elixir code
	$(RUN) 'mix format'

assets: ## Build CSS and JS assets
	$(RUN) 'mix assets.build'

fixtures: ## Regenerate the test pictures and detection results
	$(RUN) './scripts/make_fixtures.sh && mix test.js'

clean: ## Remove build artifacts and dependencies
	rm -rf _build deps priv/static/assets
