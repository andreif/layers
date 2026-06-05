SHELL = bash
export UV_FROZEN=1
export PYTHONPATH=src
export PYTHONUNBUFFERED=1
PYTHON = 3.14
TAG = public.ecr.aws/lambda/python:$(PYTHON)-arm64
UV_IMAGE = ghcr.io/astral-sh/uv:0.11
LAYER_DIR = $(NAME)
LAYER_ZIP = dist/layer.zip
REQ = dist/requirements.txt
AWS_REGION = eu-north-1
DEPENDABOT = .github/dependabot.yml

define err
	printf '\033[31m%s\033[0m\n' "$(1)" >&2; exit 1
endef

clean: dist-clean
	rm -rf .venv

dist-clean:
	rm -rf dist

_check-name:
ifndef NAME
	$(error NAME is required, e.g. make layer-build NAME=demo-layer)
endif

_check-dependabot: _check-name
	@grep -qF '"/$(NAME)"' $(DEPENDABOT) \
		|| { $(call err,$(NAME) not listed in $(DEPENDABOT)); }

_check-layer: _check-name _check-dependabot
	@test -d $(LAYER_DIR) || { $(call err,unknown layer: $(NAME)); }

layer-gen: _check-name
	python3 template.py $(NAME)

layer-lock: _check-name
	mkdir -p $(LAYER_DIR)
	python3 template.py $(NAME)
	cd $(LAYER_DIR) && UV_FROZEN=0 uv lock
	make _check-dependabot

layer-build: _check-layer layer-gen dist-clean
	mkdir -p dist
	@cid=$$(docker create --platform linux/arm64 $(UV_IMAGE)); \
	docker cp $$cid:/uv dist/uv; \
	docker rm $$cid; \
	chmod +x dist/uv
	cd $(LAYER_DIR) && uv export --frozen --no-dev --no-editable -o $(CURDIR)/$(REQ)
	docker run --rm --platform linux/arm64 \
		--entrypoint /bin/uv \
		-e UV_LINK_MODE=copy \
		-e UV_NO_COLOR=1 \
		-v $(CURDIR)/dist:/dist \
		-v $(CURDIR)/dist/uv:/bin/uv:ro \
		-w /dist \
		$(TAG) \
		pip install --no-installer-metadata --no-compile-bytecode \
			--prefix packages -r requirements.txt 2>&1 | tee dist/install.log

layer-zip: layer-build
	mkdir -p dist/python
	cp -r dist/packages/lib dist/python/
	cd dist && zip -rX layer.zip python

layer-clean: dist-clean

description:
	@grep -oE '^[a-zA-Z0-9_.-]+==[^ \\]+' $(REQ) | awk '{if (n++) printf ", "; printf "%s", $$0}'

layer-publish: layer-zip
	aws lambda publish-layer-version \
		--region $(AWS_REGION) \
		--layer-name $(NAME) \
		--zip-file fileb://$(LAYER_ZIP) \
		--compatible-runtimes python$(PYTHON) \
		--compatible-architectures arm64 \
		--description="$$(make -s description | tr -d '\r')" | yq -P
	$(MAKE) dist-clean

publish-%: layer-clean
	$(MAKE) layer-publish NAME=$*
lock-%:
	$(MAKE) layer-lock NAME=$*

x-%:
	aws-vault exec experiments-admin --region eu-north-1 -- $(MAKE) $*
m-%:
	mise exec -- $(MAKE) $*


m-lock-pydantic:
m-lock-sentry-sdk:

x-m-publish-pydantic:
x-m-publish-sentry-sdk:
