# iac-practice

실무형 IaC(Infrastructure as Code) 연습 리포지토리입니다.
**Terraform**으로 AWS 인프라를 정의하고, **Floci**(로컬 AWS 에뮬레이터)에 배포합니다.
AWS 계정이나 비용 없이 연습할 수 있습니다.

> 목표는 "인프라가 진짜로 돌아가는지"가 아니라
> **"인프라를 코드로 정의하고, 검증하고, 통제하는 과정"**을 몸에 익히는 것입니다.
> VM 내부 동작(user_data, 앱 유저 권한 등)은 별도 VM/컨테이너로 검증합니다.

---

## 빠른 시작 (새 컴퓨터 기준)

```bash
# 0) 사전 요구: git, Docker 실행 중 (아래 "수동 설치" 참고)
git clone git@github.com:JaeMoonNoh/iac-practice.git
cd iac-practice

make bootstrap   # mise + terraform/tflint/aws-cli (고정 버전) 설치
make up          # Floci 기동 (localhost:4566)
make init        # terraform init
make plan        # 변경 계획 확인
make apply       # 적용
```

`make` 만 입력하면 사용 가능한 명령 전체가 나옵니다.

| 명령 | 설명 |
|---|---|
| `make bootstrap` | 도구 설치 (최초 1회, 여러 번 실행해도 안전) |
| `make up` / `down` | Floci 기동 / 중지 (데이터 유지) |
| `make reset` | Floci 중지 + 로컬 데이터 전부 삭제 |
| `make status` | Floci 상태와 인증 확인 |
| `make init` | `terraform init` |
| `make check` | fmt 검사 + validate + tflint (**PR 올리기 전 필수**) |
| `make plan` / `apply` | plan을 파일로 저장한 뒤, **그 plan 그대로** 적용 |
| `make destroy` | 리소스 전부 삭제 |

---

## 수동 설치가 필요한 것

`make bootstrap`이 자동으로 설치하지 **않는** 항목입니다.

### 1. Git + `make`
- **macOS**: `xcode-select --install` (git, make 포함)
- **Ubuntu/WSL**: `sudo apt-get install -y git make curl`

### 2. Docker (택1)

Floci는 EC2/RDS를 실제 컨테이너로 띄우기 때문에 Docker 엔진과 **docker.sock** 접근이 필요합니다.

| 환경 | 추천 | 설치 | docker.sock |
|---|---|---|---|
| macOS | **OrbStack** (가볍고 빠름) | `brew install --cask orbstack` | `/var/run/docker.sock` (자동) |
| macOS | Docker Desktop | `brew install --cask docker` | 설정 > Advanced > "Allow the default Docker socket" 체크 |
| macOS | Colima | `brew install colima docker docker-compose && colima start` | `export DOCKER_SOCK=$HOME/.colima/default/docker.sock` |
| Linux | Docker Engine | [공식 문서](https://docs.docker.com/engine/install/) | `/var/run/docker.sock` (사용자를 `docker` 그룹에 추가) |
| Windows | WSL2 + Docker Desktop | WSL 안에서 이 리포 사용 | WSL integration 활성화 |

> 회사 컴퓨터에서 Docker Desktop은 **유료 라이선스 대상**일 수 있습니다 (직원 250명 이상 또는 매출 1천만 달러 이상인 회사).
> 이 경우 OrbStack(개인 무료, 회사는 유료)이나 Colima(무료)를 검토하세요.

### 3. (선택) mise 셸 연동

`make` 명령만 쓴다면 필요 없습니다. 터미널에서 `terraform`, `aws`를 직접 칠 때
고정 버전과 가짜 자격증명이 자동으로 적용되게 하려면:

```bash
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc   # bash 사용 시 zsh → bash
exec $SHELL
```

---

## 도구와 버전

모든 버전은 고정되어 있습니다. 바꿀 때는 해당 파일을 수정하고 PR로 올립니다.

| 도구 | 버전 | 고정 위치 |
|---|---|---|
| Terraform | 1.17.1 | [mise.toml](mise.toml) |
| AWS provider | ~> 6.0 (정확한 버전은 lock 파일) | [versions.tf](terraform/envs/local/versions.tf), `.terraform.lock.hcl` |
| tflint | 0.65.0 | [mise.toml](mise.toml) |
| AWS CLI | 2.39.5 | [mise.toml](mise.toml) |
| Floci | 2.4.0 | [compose.yaml](compose.yaml) |

### 왜 LocalStack이 아니라 Floci인가
- LocalStack은 2026년 3월에 무료 Community 에디션 지원을 종료했습니다. 지금은 계정과 auth token이 필요합니다.
- Floci는 MIT 라이선스이고 가입이나 토큰이 필요 없습니다. LocalStack과 같은 4566 포트와 API를 씁니다.
- 이 리포의 시나리오에 필요한 서비스를 Floci가 지원합니다. EC2는 실제 컨테이너로 뜨고 UserData와 IMDS도 동작합니다. RDS는 실제 Postgres 컨테이너로 뜹니다. ALB, ECR, IAM Instance Profile, Secrets Manager, SSM도 지원합니다.
- 주의할 점: 신생 프로젝트라서 일부 기능이 실제 AWS와 다를 수 있습니다. Security Group이 실제로 패킷을 막는지는 보장되지 않습니다.

---

## 안전장치 (실수로 진짜 AWS를 건드리지 않기)

회사 컴퓨터에 실제 AWS 자격증명이 있을 수 있어서, 세 겹으로 막아두었습니다.

1. provider에 가짜 자격증명(`test`/`test`)을 직접 박아뒀습니다. 그래서 셸에 있는 실제 자격증명이 무시됩니다.
2. `allowed_account_ids = ["000000000000"]`: 에뮬레이터 계정이 아니면 plan 단계에서 거부합니다.
3. `aws_endpoint` 변수 validation: localhost가 아닌 주소를 넣으면 실패합니다.

---

## 디렉터리 구조

```
.
├── compose.yaml            # Floci 컨테이너 정의
├── mise.toml               # 도구 버전 + 이 폴더 전용 환경변수
├── Makefile                # 자주 쓰는 명령
├── .tflint.hcl             # 린트 규칙
├── scripts/bootstrap.sh    # 새 컴퓨터 세팅
├── docs/                   # 단계별 학습 노트
└── terraform/
    ├── modules/            # (1단계~) 재사용 모듈: network, iam, compute, database ...
    └── envs/
        └── local/          # 환경별 진입점 (모듈을 조립)
```

---

## 학습 로드맵

| 단계 | 내용 | 노트 |
|---|---|---|
| 0 | 도구 설치, Floci, provider 연결, 안전장치 | [docs/00-setup.md](docs/00-setup.md) |
| 1 | VPC, 퍼블릭/프라이빗 서브넷, 라우팅 (network 모듈) | |
| 2 | Remote State(S3 + lock), PR CI (fmt/validate/tflint/plan 코멘트) | |
| 3 | IAM Role / Instance Profile (S3 읽기, ECR pull, SSM) — 최소 권한 | |
| 4 | EC2 + SG, 인스턴스 타입 제한(validation), user_data | |
| 5 | Secrets Manager + RDS + SG 체이닝 | |
| 6 | Policy as Code (conftest/OPA, checkov) CI 연동 | |
| 7 | self-hosted runner CD, drift 감지 스케줄 | |

### 작업 규칙 (실무 흉내)
- `main`에 직접 push하지 않습니다. 단계별로 브랜치를 만들어 PR로 올립니다. 예: `phase-1/network`
- PR을 올리기 전에 `make check`를 통과시킵니다.
- 적용은 항상 `plan`을 먼저 실행해 저장한 뒤, 그 plan 파일로 `apply`합니다. 리뷰한 내용과 실제 적용 내용이 같다는 걸 보장하기 위해서입니다.

---

## 문제 해결

| 증상 | 원인 / 해결 |
|---|---|
| `make up`이 timeout | `docker compose logs floci` 확인. 4566 포트가 이미 사용 중인지 확인 (`lsof -i :4566`) |
| EC2/RDS 생성 시 Docker 관련 에러 | docker.sock 경로 확인. Colima는 `DOCKER_SOCK` 지정 필요 |
| `Invalid TOML ... mise.toml` | mise 버전이 너무 오래됨 → `brew upgrade mise` |
| `mise.toml is not trusted` | `mise trust` |
| `allowed_account_ids` 에러 | 엔드포인트가 Floci가 아닌 곳을 가리키고 있음. **즉시 중단하고 설정 확인** |
