.PHONY: help serve draft build clean
.DEFAULT_GOAL := help

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "  serve   Serve site on LAN (0.0.0.0)"
	@echo "  draft   Serve site on LAN with drafts"
	@echo "  build   Production build (--gc --minify)"
	@echo "  clean   Remove public/ and resources/"

# Local dev server accessible on intranet (0.0.0.0)
serve:
	hugo server --bind 0.0.0.0 --baseURL http://$(shell hostname -I | awk '{print $$1}')

# Same but includes draft posts
draft:
	hugo server --bind 0.0.0.0 --baseURL http://$(shell hostname -I | awk '{print $$1}') --buildDrafts

# Production build
build:
	hugo --gc --minify

# Remove generated files
clean:
	rm -rf public/ resources/
