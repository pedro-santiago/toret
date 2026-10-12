# Toret backend. Run `make help`.
#
# Nothing here writes account data (account id, certificate ARN, keys) to a
# tracked file: those are looked up at run time and passed on the command line.
# `deploy` and `pepper` are the only targets that call AWS, and they use
# whatever AWS credentials the shell has (the default profile unless PROFILE is set).

GO       ?= go
STACK    ?= toret-api
REGION   ?= sa-east-1
VERSION  ?= 1.0.0
PROFILE  ?=
# The ISSUED wildcard certificate to use; resolved by `deploy` unless CERT_ARN is given.
CERT_DOMAIN ?= *.deepdive.dev.br
CERT_ARN    ?=
# Where `sam deploy` uploads the package. Empty: sam uses the bucket from its own
# configuration. S3_BUCKET=<name> names one; RESOLVE_S3=1 lets sam create or
# reuse its shared "aws-sam-cli-managed-default" stack (a stack outside this one).
S3_BUCKET  ?=
RESOLVE_S3 ?=
PEPPER_PARAM ?= /toret/pepper
SMAT_ENABLED ?= false
# Reserved concurrent executions; -1 leaves a function unreserved (accounts whose
# limit is so low that reserving would leave fewer than 10 unreserved).
API_CONCURRENCY    ?= 10
INGEST_CONCURRENCY ?= 1
# Pass CONFIRM= to deploy without reviewing the change set first.
CONFIRM ?= --confirm-changeset

AWS = aws $(if $(PROFILE),--profile $(PROFILE)) --region $(REGION)
SAM = sam

.PHONY: help data build test vet check validate pepper deploy outputs clean

help:
	@sed -n '2,8p' Makefile | sed 's/^# \{0,1\}//'
	@echo
	@echo "  make data      copy the app's fountains.json into data/ (one source of truth)"
	@echo "  make test      go vet, then go test -race ./...   (offline)"
	@echo "  make validate  lint template.yaml                  (offline)"
	@echo "  make build     sam build (arm64, provided.al2023)  (offline)"
	@echo "  make pepper    create the SSM SecureString $(PEPPER_PARAM) once, never overwriting"
	@echo "  make deploy    resolve the certificate, check the pepper, sam deploy"
	@echo "  make outputs   print the stack outputs"

# The catalogue is a copy of the app's file. It is committed so the module builds
# on its own, and refreshed here whenever the app's file is newer.
ifneq ($(wildcard ../Shared/Resources/fountains.json),)
data/fountains.json: ../Shared/Resources/fountains.json
	cp $< $@
endif
data: data/fountains.json

vet: data/fountains.json
	$(GO) vet ./...

test: vet
	$(GO) test -race -count=1 ./...

check: test validate

# cfn-lint runs the SAM transform locally and needs no credentials. `sam validate`
# is the fallback, with every credential source blanked so it cannot reach AWS.
validate:
	@if command -v cfn-lint >/dev/null; then cfn-lint template.yaml && echo "cfn-lint: template.yaml ok"; \
	else env -u AWS_PROFILE -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN \
	  AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null AWS_EC2_METADATA_DISABLED=true \
	  $(SAM) validate --lint --region $(REGION) --template-file template.yaml; fi

# sam build runs these two targets, one per function (BuildMethod: makefile).
GOBUILD = CGO_ENABLED=0 GOOS=linux GOARCH=arm64 $(GO) build -tags lambda.norpc -trimpath -ldflags "-s -w -X main.version=$(VERSION)"
build-ApiFunction: data/fountains.json
	$(GOBUILD) -o "$(ARTIFACTS_DIR)/bootstrap" ./cmd/api
build-IngestFunction: data/fountains.json
	$(GOBUILD) -o "$(ARTIFACTS_DIR)/bootstrap" ./cmd/ingest

build: data/fountains.json
	$(SAM) build

# The pepper keys every install and IP hash. It is created once and never
# rotated (rotating it makes every install lose its reports), hence --no-overwrite.
pepper:
	@set -e; umask 077; tmp=$$(mktemp); trap 'rm -f "$$tmp"' EXIT; \
	openssl rand -hex 32 | tr -d '\n' > "$$tmp"; \
	$(AWS) ssm put-parameter --name "$(PEPPER_PARAM)" --type SecureString --no-overwrite \
	  --description "Toret HMAC pepper. Never rotate." --value "file://$$tmp" >/dev/null \
	  && echo "created $(PEPPER_PARAM)"

deploy: test validate build
	@set -e; \
	cert="$(CERT_ARN)"; \
	if [ -z "$$cert" ]; then \
	  cert=$$($(AWS) acm list-certificates --certificate-statuses ISSUED \
	    --includes keyTypes=RSA_2048,EC_prime256v1,EC_secp384r1 \
	    --query "CertificateSummaryList[?DomainName=='$(CERT_DOMAIN)'].CertificateArn" --output text); \
	  n=$$(printf '%s' "$$cert" | wc -w | tr -d ' '); \
	  if [ "$$n" != 1 ]; then echo "expected exactly one ISSUED certificate for $(CERT_DOMAIN) in $(REGION), found $$n; pass CERT_ARN=<arn> to choose one" >&2; exit 1; fi; \
	fi; \
	$(AWS) ssm get-parameter --name "$(PEPPER_PARAM)" --query 'Parameter.Type' --output text >/dev/null 2>&1 \
	  || { echo "$(PEPPER_PARAM) does not exist: run 'make pepper' first" >&2; exit 1; }; \
	$(SAM) deploy --template-file .aws-sam/build/template.yaml --stack-name $(STACK) --region $(REGION) \
	  $(if $(PROFILE),--profile $(PROFILE)) \
	  $(if $(S3_BUCKET),--s3-bucket $(S3_BUCKET)) $(if $(RESOLVE_S3),--resolve-s3) \
	  --capabilities CAPABILITY_IAM --no-fail-on-empty-changeset $(CONFIRM) \
	  --tags project=toret \
	  --parameter-overrides "CertificateArn=$$cert" "PepperParameterName=$(PEPPER_PARAM)" "SmatEnabled=$(SMAT_ENABLED)" \
	    "ApiReservedConcurrency=$(API_CONCURRENCY)" "IngestReservedConcurrency=$(INGEST_CONCURRENCY)"

outputs:
	@$(AWS) cloudformation describe-stacks --stack-name $(STACK) --query 'Stacks[0].Outputs' --output table

clean:
	rm -rf bin .aws-sam
