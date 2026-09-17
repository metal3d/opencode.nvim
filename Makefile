# Test entry points. Plenary is a test-only dependency; point PLENARY at a
# local clone, e.g. `make test PLENARY=~/.local/share/nvim/lazy/plenary.nvim`.
PLENARY ?= /tmp/plenary
NVIM_BIN ?= nvim

.PHONY: test test-file

test:
	PLENARY_PATH=$(PLENARY) $(NVIM_BIN) --headless --clean -u tests/minimal_init.lua \
		-c "lua require('plenary.test_harness').test_directory('tests/opencode', { minimal_init = 'tests/minimal_init.lua' })"

test-file:
	@test -n "$(FILE)" || { echo "usage: make test-file FILE=tests/opencode/<name>_spec.lua"; exit 1; }
	PLENARY_PATH=$(PLENARY) $(NVIM_BIN) --headless --clean -u tests/minimal_init.lua \
		-c "lua require('plenary.test_harness').test_file('$(FILE)')"
