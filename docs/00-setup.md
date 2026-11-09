# 0단계: 환경 구성과 provider 연결

## 이번 단계의 목표
- 어느 컴퓨터에서든 **명령 몇 줄로 같은 환경**을 재현할 수 있다.
- Terraform이 **Floci(로컬 AWS)에 연결**되고, **실제 AWS에는 절대 연결되지 않는다**.
- Terraform의 기본 흐름(`init → plan → apply`)과 각 단계에서 무슨 일이 일어나는지 이해한다.

리소스는 아직 하나도 만들지 않습니다.

---

## 1. 전체 그림

```
 [내 코드 *.tf]
      │  terraform init   : provider 플러그인 다운로드, lock 파일 생성
      │  terraform plan   : "코드(원하는 상태)" vs "state(마지막으로 알고 있는 상태)" vs "실제 인프라" 비교
      │  terraform apply  : 차이를 메우는 API 호출 실행 → 결과를 state에 기록
      ▼
 [hashicorp/aws provider] ──HTTP(AWS API)──▶ [Floci :4566]  ──▶ (EC2/RDS는 Docker 컨테이너로 생성)
```

**핵심 개념 3가지**

| 개념 | 설명 | 이 리포에서 |
|---|---|---|
| Provider | Terraform이 특정 플랫폼(AWS, GCP, GitHub...) API를 호출하게 해주는 플러그인 | `hashicorp/aws`. 주소만 Floci로 바꿔 사용 |
| State | Terraform이 "내가 만든 리소스 목록과 속성"을 기억하는 JSON 파일 | 지금은 로컬 `terraform.tfstate`. 2단계에서 S3로 옮김 |
| Plan | 적용 전에 "무엇을 만들고/바꾸고/지울지" 보여주는 미리보기 | **실무에서 PR 리뷰의 핵심 대상** |

---

## 2. 파일별 설명

### [mise.toml](../mise.toml): 도구 버전 고정
- Terraform 1.16과 1.17은 동작이 미묘하게 다를 수 있습니다. 팀원마다 버전이 다르면 같은 코드로도 다른 plan이 나옵니다.
- 실무에서는 `tfenv`, `asdf`, `mise` 같은 버전 매니저를 쓰거나 Docker 이미지로 버전을 통일합니다. 여기서는 Terraform, tflint, AWS CLI를 한 파일로 관리할 수 있는 mise를 씁니다.
- `[env]` 섹션은 이 폴더 안에서만 환경변수를 덮어씁니다. 회사 AWS 자격증명(`AWS_PROFILE`)이 셸에 있어도 여기서는 제거됩니다.

### [compose.yaml](../compose.yaml): Floci 기동
- `floci/floci:2.4.0`처럼 버전을 고정했습니다. `latest`는 내일 다른 버전이 될 수 있어서 재현성이 깨집니다.
- `127.0.0.1:4566:4566`처럼 내 컴퓨터에서만 접근되게 열었습니다. 그냥 `4566:4566`으로 열면 같은 Wi-Fi에 있는 다른 사람도 접근할 수 있습니다.
- `docker.sock` 마운트: Floci가 호스트의 Docker에게 "EC2 대신 컨테이너를 하나 띄워줘"라고 요청하는 통로입니다.
- `FLOCI_STORAGE_MODE: persistent`: Floci를 재시작해도 만든 리소스가 남습니다. 데이터는 `.floci-data/`에 저장됩니다.

### [versions.tf](../terraform/envs/local/versions.tf): 버전 제약
- `required_version`: Terraform 본체 버전 범위
- `version = "~> 6.0"`: 6.x는 허용하고 7.0은 막습니다. 메이저 버전에는 breaking change가 있으므로 실무에서는 항상 상한을 겁니다.
- `init` 후 생기는 **`.terraform.lock.hcl`은 Git에 커밋합니다.** 정확한 provider 버전과 해시가 기록되어서 모든 사람과 CI가 똑같은 바이너리를 쓰게 됩니다. npm의 `package-lock.json`과 같은 역할입니다.

### [providers.tf](../terraform/envs/local/providers.tf): 연결 설정과 안전장치
| 설정 | 왜 필요한가 |
|---|---|
| `access_key = "test"` | 실제 자격증명이 절대 쓰이지 않게 |
| `allowed_account_ids` | 계정 ID가 다르면 즉시 중단. **실무에서도 dev/prod 혼동 방지용으로 씀** |
| `skip_credentials_validation` 등 | 에뮬레이터에는 진짜 인증/메타데이터 서버가 없음 |
| `s3_use_path_style` | `bucket.localhost` 형태의 DNS가 로컬에서 안 되므로 `localhost/bucket` 사용 |
| `endpoints { ... }` | 서비스별 API 주소를 Floci로. **새 서비스를 쓰면 반드시 여기에 추가** |
| `default_tags` | 모든 리소스에 Project/Environment/ManagedBy 태그 자동 부착 |

> 실제 AWS용 provider라면 `region` 한 줄과 `default_tags` 정도만 남습니다. 나머지는 에뮬레이터 때문에 붙은 설정입니다.

### [variables.tf](../terraform/envs/local/variables.tf): 입력값과 validation
- `validation` 블록은 잘못된 입력을 plan 단계에서 막습니다.
- 4단계에서는 같은 방식으로 "t3.*, m5.* 인스턴스만 허용"하는 규칙을 만듭니다. Policy as Code의 가장 단순한 형태입니다.

### [main.tf](../terraform/envs/local/main.tf): `data` 소스
- `resource`는 무언가를 **만듭니다**. `data`는 이미 있는 것을 **조회만** 합니다.
- 그래서 지금 `apply`해도 생성되는 리소스가 없고, output 값만 state에 기록됩니다.

### [Makefile](../Makefile): 명령 표준화
- 팀원 모두가 같은 명령을 같은 방식으로 실행하게 합니다. CI도 같은 `make check`를 호출할 예정입니다.
- `make plan`은 `-out=tfplan`으로 저장하고, `make apply`는 그 파일로만 적용합니다.
  - 이유: plan을 본 뒤 apply 직전에 누군가 인프라를 바꿨다면, 그냥 `terraform apply`는 **내가 본 것과 다른 변경**을 적용할 수 있습니다. 저장된 plan을 쓰면 "리뷰한 것 = 적용되는 것"이 보장됩니다.

---

## 3. 실행 결과 해석

```
account_id         = "000000000000"     ← 에뮬레이터 계정 (안전장치 통과)
caller_arn         = "arn:aws:iam::000000000000:root"
region             = "ap-northeast-2"
availability_zones = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c"]
```

AZ가 3개 나온 것을 기억해두세요. 1단계에서 서브넷을 AZ 2개 이상에 나눠 배치합니다(고가용성).

---

## 4. 직접 해보기 (망가뜨리면서 배우기)

각 실습을 한 뒤 원래대로 되돌리세요.

1. **endpoint 안전장치**
   `mise exec -- terraform -chdir=terraform/envs/local plan -var aws_endpoint=https://sts.amazonaws.com`
   → `Invalid value for variable` 에러가 나야 정상입니다.

2. **계정 ID 안전장치**
   `providers.tf`의 `allowed_account_ids`를 `["111111111111"]`로 바꾼 뒤 `make plan`을 실행합니다.
   → 계정 불일치 에러가 납니다. 실무에서 이 에러가 났다면 **즉시 멈춰야 하는 상황**입니다.

3. **포맷 검사**
   `main.tf`의 들여쓰기를 일부러 망가뜨린 뒤 `make check`를 실행합니다.
   → fmt-check가 실패합니다. 2단계 CI에서 PR을 막는 바로 그 검사입니다. `make fmt`로 복구하세요.

4. **state 들여다보기**
   `cat terraform/envs/local/terraform.tfstate | head -40`
   → Terraform이 무엇을 기억하는지 확인합니다. 지금은 output만 있습니다.
   리소스가 생기면 ID와 속성이 전부 여기에 기록되고, **비밀번호 같은 민감값도 평문으로 들어갑니다.** 그래서 state는 Git에 올리지 않고(`.gitignore`), 2단계에서 암호화된 원격 저장소로 옮깁니다.

5. **Floci를 직접 호출해보기**
   `mise exec -- aws ec2 describe-availability-zones --query 'AvailabilityZones[].ZoneName'`
   → Terraform이 내부적으로 호출하는 API와 같은 것을 CLI로 호출해봅니다.

---

## 5. 체크리스트
- [ ] `make bootstrap`, `make up`, `make init`, `make plan`, `make apply` 성공
- [ ] `.terraform.lock.hcl`이 커밋 대상에 포함되고, `terraform.tfstate`와 `.floci-data/`는 제외되는지 `git status`로 확인
- [ ] 위 실습 1~3에서 의도한 에러 확인
- [ ] "왜 plan을 파일로 저장해서 apply하는가"를 한 문장으로 설명할 수 있다

다음: **1단계: network 모듈 (VPC, 서브넷, 라우팅)**
