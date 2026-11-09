# =====================================================================
# 자주 쓰는 명령 모음. `make help` 로 목록 확인.
# terraform/aws 는 항상 `mise exec --` 로 실행 → mise.toml 의 고정 버전 + [env] 보장
# (셸에 mise activate 를 안 해도 동일하게 동작)
# =====================================================================
ENV    ?= local
TF_DIR := terraform/envs/$(ENV)
MISE   := mise exec --
TF     := $(MISE) terraform -chdir=$(TF_DIR)

.DEFAULT_GOAL := help
.PHONY: help bootstrap up down reset status logs mess state-bootstrap state-ls init lock fmt fmt-check validate lint test check plan apply destroy output

help: ## 명령 목록
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-11s\033[0m %s\n",$$1,$$2}'

bootstrap: ## 도구 설치 (새 컴퓨터에서 최초 1회)
	@./scripts/bootstrap.sh

# ---- Floci (로컬 AWS) -------------------------------------------------
up: ## Floci 기동 + 준비될 때까지 대기
	@docker compose up -d
	@printf "Floci 준비 대기"; for i in $$(seq 1 30); do \
	  if $(MISE) aws sts get-caller-identity >/dev/null 2>&1; then echo " -> ready"; exit 0; fi; \
	  printf "."; sleep 2; done; echo " -> timeout"; docker compose logs --tail 30 floci; exit 1

down: ## Floci 중지 (데이터 유지)
	@docker compose down

reset: ## Floci 중지 + 로컬 데이터 전부 삭제 (주의!)
	@docker compose down
	@rm -rf ./.floci-data
	@echo "Floci 데이터 삭제 완료"

status: ## Floci 상태 + 인증 확인
	@docker compose ps
	@$(MISE) aws sts get-caller-identity

logs: ## Floci 로그 따라보기
	@docker compose logs -f floci

# ---- Brownfield 시나리오 ------------------------------------------------
mess: ## (brownfield) 콘솔로 막 만든 회사 AWS 를 Floci 에 재현
	@chmod +x scenarios/brownfield/create-mess.sh
	@$(MISE) ./scenarios/brownfield/create-mess.sh

# ---- Remote State ----------------------------------------------------
BOOTSTRAP := $(MISE) terraform -chdir=terraform/bootstrap

state-bootstrap: ## state 저장용 S3 버킷 생성 (Floci 기동 후 최초 1회, 여러 번 실행해도 안전)
	@$(BOOTSTRAP) init -input=false >/dev/null
	@$(BOOTSTRAP) apply -input=false -auto-approve
	@echo "state 버킷 준비 완료 -> 이제 make init"

state-ls: ## S3 에 저장된 state 파일 목록
	@$(MISE) aws s3 ls s3://iac-practice-tfstate --recursive

# ---- Terraform -------------------------------------------------------
init: ## terraform init (S3 backend 연결)
	@$(TF) init -input=false

lock: ## provider lock 파일에 Mac/Linux 해시 모두 기록 (CI 에서도 같은 provider 보장)
	@$(TF) providers lock -platform=darwin_arm64 -platform=darwin_amd64 -platform=linux_amd64 -platform=linux_arm64

fmt: ## 코드 자동 정렬
	@$(MISE) terraform fmt -recursive terraform

fmt-check: ## 정렬 안 된 파일 검사 (CI용, 수정 안 함)
	@$(MISE) terraform fmt -recursive -check -diff terraform

validate: ## 문법/타입 검사 (backend 연결 없이 → Floci 꺼져 있어도 동작)
	@$(TF) init -backend=false -input=false >/dev/null
	@$(TF) validate
	@$(MISE) terraform -chdir=terraform/bootstrap init -backend=false -input=false >/dev/null
	@$(MISE) terraform -chdir=terraform/bootstrap validate

lint: ## tflint 검사
	@$(MISE) tflint --init --config "$(CURDIR)/.tflint.hcl" >/dev/null
	@$(MISE) tflint --recursive --config "$(CURDIR)/.tflint.hcl"

test: ## 모듈 단위 테스트 (mock provider, Floci 불필요)
	@for d in terraform/modules/*/; do \
	  if [ -d "$$d/tests" ]; then \
	    echo "== $$d"; \
	    $(MISE) terraform -chdir=$$d init -backend=false -input=false >/dev/null && \
	    $(MISE) terraform -chdir=$$d test || exit 1; \
	  fi; \
	done

check: fmt-check validate lint test ## 정적 검사 + 테스트 일괄 (PR 올리기 전에 실행)

plan: ## 변경 계획 확인 (tfplan 파일로 저장)
	@$(TF) plan -out=tfplan

apply: ## 저장된 plan 그대로 적용 (plan 먼저 실행 필요)
	@$(TF) apply tfplan
	@rm -f $(TF_DIR)/tfplan

destroy: ## 이 환경의 리소스 전부 삭제
	@$(TF) destroy

output: ## output 값 출력
	@$(TF) output
