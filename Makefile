PREFIX ?= /usr/local
LIBDIR ?= $(PREFIX)/lib/linux-ops-toolkit
TOOLS  := triage collect-logs disk-cleanup check-certs

.PHONY: help lint test check install uninstall

help: ## Show available targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

lint: ## Run ShellCheck on every script
	shellcheck -x bin/*.sh lib/*.sh

test: ## Run the bats test suite
	bats tests/

check: lint test ## Lint and test

install: ## Install the tools as ops-<name> into $(PREFIX)/bin
	install -d $(DESTDIR)$(LIBDIR)/bin $(DESTDIR)$(LIBDIR)/lib $(DESTDIR)$(PREFIX)/bin
	install -m 0644 lib/common.sh $(DESTDIR)$(LIBDIR)/lib/common.sh
	for t in $(TOOLS); do \
		install -m 0755 bin/$$t.sh $(DESTDIR)$(LIBDIR)/bin/$$t.sh; \
		ln -sf $(LIBDIR)/bin/$$t.sh $(DESTDIR)$(PREFIX)/bin/ops-$$t; \
	done

uninstall: ## Remove installed tools
	for t in $(TOOLS); do rm -f $(DESTDIR)$(PREFIX)/bin/ops-$$t; done
	rm -rf $(DESTDIR)$(LIBDIR)
