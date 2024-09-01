all: gem

gem:
	@gem install --install-dir=vendor $$(awk '/^gem/{print $$2}' Gemfile | tr -d "'")

.PHONY: gem
