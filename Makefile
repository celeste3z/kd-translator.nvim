NVIM_EXEC ?= nvim

TEST_FILES := $(wildcard tests/test_*.lua)
TEST_TARGETS := $(TEST_FILES:tests/%.lua=test-%)

test: $(TEST_TARGETS)

documentation:
	$(NVIM_EXEC) --headless --noplugin -u scripts/minimal_init.lua \
	  -c "lua require('mini.doc').generate()" -c "qa!"

test-clean:
	rm -f tests/screenshots/*

test-%: tests/%.lua
	$(NVIM_EXEC) --headless --noplugin -u scripts/minimal_init.lua \
	  -c "lua require('mini.test').setup()" \
	  -c "lua MiniTest.run_file('tests/$*.lua')"
