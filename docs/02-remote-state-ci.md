# 2단계: Remote State와 PR CI

## 이번 단계의 목표
- state 파일을 내 Mac에서 **S3 버킷**으로 옮기고, 동시 실행을 막는 **잠금(lock)**을 건다.
- PR을 올리면 **GitHub Actions가 자동으로 검사, plan, apply 테스트**를 하고 결과를 PR 댓글로 남기게 한다.
- CI가 통과하지 않으면 **머지할 수 없게** 막는다(브랜치 보호).

처음에 말씀하신 "iac-practice에 올리고, 거기서 검증한 뒤"가 이 단계입니다.

---

## Part A. Remote State

### 1. state가 뭐였더라?

Terraform이 **"내가 만든 리소스 목록"을 기억하는 파일**입니다. 1단계에서는 `terraform/envs/local/terraform.tfstate`(내 Mac)에 있었습니다.

```
코드(.tf)      "VPC가 있어야 한다"
state          "내가 만든 VPC는 vpc-00e95f90이다"   ← 이게 없으면 Terraform은 VPC를 또 만들려고 함
실제 인프라     vpc-00e95f90
```

### 2. state를 내 Mac에 두면 생기는 문제

| 문제 | 상황 |
|---|---|
| 공유 불가 | 동료나 CI는 내 Mac의 파일을 볼 수 없음 → 같은 인프라를 관리할 수 없음 |
| 유실 위험 | 노트북이 고장 나면 Terraform이 자기가 만든 인프라를 전부 잊어버림 |
| 동시 실행 | 두 사람이 동시에 apply하면 state가 꼬임 |
| 보안 | state에는 DB 비밀번호 같은 민감값이 **평문**으로 들어감 |

### 3. 해결: S3 버킷 + 잠금

```
       나 (make apply)              CI (make apply)
            │                            │
            ▼                            ▼
     ┌────────── S3: iac-practice-tfstate ───────────┐
     │  envs/local/terraform.tfstate         ← state │
     │  envs/local/terraform.tfstate.tflock  ← 잠금  │
     └───────────────────────────────────────────────┘
```

- 실행을 시작하면 Terraform이 `.tflock` 파일을 만듭니다. **이미 있으면 실패합니다.** 그래서 먼저 시작한 쪽만 진행됩니다.
- 실행이 끝나면 `.tflock`을 지웁니다.
- 이 "있으면 실패"를 S3의 조건부 쓰기(`If-None-Match`)로 구현합니다. 예전에는 DynamoDB 테이블을 따로 만들어 잠갔지만, Terraform 1.10부터 S3만으로 됩니다(`use_lockfile = true`).

### 4. 닭과 달걀 문제: [terraform/bootstrap/](../terraform/bootstrap/)

> state를 S3에 두려면 버킷이 먼저 있어야 하는데, 그 버킷도 Terraform으로 만들고 싶다. 그럼 **버킷을 만드는 Terraform의 state는 어디에?**

그래서 **버킷만 만드는 작은 스택**을 따로 두고, 그 스택의 state만 로컬 파일로 둡니다. 계정당 한 번 만들고 거의 건드리지 않습니다.

버킷에는 보호 장치 5개를 걸었습니다.

| 설정 | 이유 |
|---|---|
| 버전 관리 | state가 깨지면 이전 버전으로 복구 |
| 암호화 | 저장된 state 암호화 |
| 퍼블릭 접근 차단 | state 유출 방지 |
| ACL 비활성화 | 권한 관리를 버킷 정책 하나로 통일 |
| `prevent_destroy` | `terraform destroy`로도 버킷이 지워지지 않게 |

### 5. [backend.tf](../terraform/envs/local/backend.tf)

```hcl
terraform {
  backend "s3" {
    bucket       = "iac-practice-tfstate"
    key          = "envs/local/terraform.tfstate"   # 버킷 안의 경로
    use_lockfile = true                              # 잠금
    ...
  }
}
```

**backend 블록에는 변수(`var.xxx`)를 쓸 수 없습니다.** backend는 `terraform init` 시점에 다른 어떤 것보다 먼저 읽히기 때문입니다.

### 6. 실제로 한 일 (마이그레이션)

```bash
make state-bootstrap                       # 버킷 생성 (리소스 5개)
terraform init -migrate-state              # 로컬 state → S3로 복사
make state-ls                              # S3에 state 파일 확인
make plan                                  # "No changes" → 옮기기만 했고 인프라는 그대로
```

마이그레이션 후 로컬 `terraform.tfstate`는 **0바이트**가 되고, 원본은 `terraform.tfstate.backup`으로 남습니다.

---

## Part B. PR CI ([.github/workflows/terraform.yml](../.github/workflows/terraform.yml))

### 1. 흐름

```
PR 생성 / 새 커밋 push
   │
   ├─ static (1분)  ─ 인프라 없이 검사
   │    fmt-check → validate → tflint → terraform test
   │        실패하면 여기서 중단
   │
   └─ e2e (3분)     ─ 빈 Floci를 새로 띄워서 실제 실행
        make up → state-bootstrap → init → plan
          → PR에 plan 댓글 게시
          → apply
          → 다시 plan해서 변경 없음 확인 (멱등성)
          → destroy
```

### 2. 왜 `make` 명령을 그대로 쓰나

CI에서도 로컬과 **똑같은 명령**을 실행합니다. 도구 버전도 같은 `mise.toml`을 읽습니다. 그래서 "내 Mac에선 되는데 CI에선 안 돼요"가 생기지 않습니다. 반대로 CI가 실패하면 로컬에서 같은 명령으로 그대로 재현할 수 있습니다.

### 3. 멱등성(idempotency) 검사란?

> **같은 코드로 apply를 몇 번 하든 결과가 같아야 한다.**

apply 직후 다시 plan했는데 변경이 나온다면, 코드와 실제 값이 영원히 일치하지 않는 버그입니다. 예를 들어 코드에는 `"10.0.0.0/16 "`(공백 포함)처럼 쓰고 AWS는 공백을 지워서 저장하면, 매번 diff가 나옵니다. 이런 코드는 **매 PR마다 의미 없는 변경이 plan에 섞여서 진짜 변경을 가립니다.** 그래서 CI에서 막습니다.

### 4. 최소 권한

```yaml
permissions:
  contents: read              # 기본은 읽기만
jobs:
  e2e:
    permissions:
      pull-requests: write    # 댓글이 필요한 job에만 쓰기 권한
```

CI도 하나의 "사용자"입니다. 필요한 권한만 줍니다. 3단계 IAM에서 다룰 최소 권한 원칙과 같은 이야기입니다.

### 5. 한계 (중요)

CI의 Floci는 **매번 비어 있는 새 환경**입니다. 그래서 PR 댓글의 plan은 항상 "처음부터 전부 생성" 기준입니다(`24 to add`).

실무의 PR plan은 **실제 운영 state와 비교한 차이**(예: `1 to change`)를 보여줍니다. 그게 가능하려면 CI가 내 Mac의 Floci에 접근해야 하고, 그건 **7단계 self-hosted runner**에서 합니다.

지금 CI가 보장하는 것은 이렇습니다.
- 코드가 포맷, 문법, 린트, 테스트를 통과한다.
- **빈 환경에 처음부터 배포해도 성공**한다(새 환경을 만들 때 깨지지 않음).
- 배포 후 상태가 코드와 일치한다(멱등성).

---

## Part C. 브랜치 보호 (브라우저에서 직접)

CI가 있어도 실패한 PR을 머지할 수 있다면 소용이 없습니다. GitHub에서 **main에 대한 규칙**을 겁니다.

1. 리포 → **Settings** → **Rules** → **Rulesets** → **New ruleset** → **New branch ruleset**
2. 설정
   - Ruleset name: `protect-main`
   - Enforcement status: **Active**
   - Target branches: **Add target** → **Include default branch**
   - 체크할 규칙
     - ✅ **Restrict deletions** (main 삭제 금지)
     - ✅ **Require a pull request before merging** (직접 push 금지)
       - Required approvals: **0** (혼자 하는 리포라서. 팀이라면 1 이상)
     - ✅ **Require status checks to pass**
       - **Add checks** → `static checks`와 `plan / apply on Floci` 추가
       - (목록에 안 보이면 CI가 한 번 실행된 뒤에 나타납니다)
     - ✅ **Block force pushes**
3. **Create**

설정 후 확인할 것
- main에 직접 push하면 거부되는지
- CI가 실패한 PR은 머지 버튼이 비활성화되는지

---

## 직접 해보기

### 실습 A: 잠금 체험
누군가 apply 중인 상황을 가짜 잠금 파일로 만들어봅니다.

```bash
echo '{"ID":"fake","Who":"colleague@other-laptop","Operation":"OperationTypeApply"}' > /tmp/lock.json
mise exec -- aws s3 cp /tmp/lock.json s3://iac-practice-tfstate/envs/local/terraform.tfstate.tflock

make plan        # → Error acquiring the state lock ... Who: colleague@other-laptop

mise exec -- aws s3 rm s3://iac-practice-tfstate/envs/local/terraform.tfstate.tflock   # 정리
```

실무에서 이 에러가 나면 **먼저 그 사람에게 연락합니다.** 정말로 실행 중인 apply가 없을 때만 `terraform force-unlock <ID>`로 풀어줍니다. 함부로 풀면 두 apply가 동시에 돌면서 state가 깨집니다.

### 실습 B: state 버전 관리
```bash
mise exec -- aws s3api list-object-versions --bucket iac-practice-tfstate \
  --prefix envs/local/terraform.tfstate --query 'Versions[].{Ver:VersionId,Time:LastModified,Size:Size}' --output table
```
apply할 때마다 버전이 하나씩 쌓입니다. state가 깨지면 이전 버전을 내려받아 복구할 수 있습니다.

### 실습 C: CI를 일부러 실패시키기
1. 새 브랜치에서 `.tf` 파일 들여쓰기를 망가뜨리고 PR을 올립니다.
   → `static checks`의 `terraform fmt`에서 실패하고, e2e는 실행되지 않습니다.
2. network 모듈 테스트의 기대값(`10.0.0.0/24`)을 틀리게 바꿔서 PR을 올립니다.
   → `terraform test`에서 실패합니다.
3. 브랜치 보호가 걸려 있다면 머지 버튼이 막혀 있는지 확인합니다.

---

## 체크리스트
- [ ] `make state-ls`에 `envs/local/terraform.tfstate`가 보인다
- [ ] 실습 A에서 잠금 에러와 `Who` 정보를 확인했다
- [ ] PR을 올리면 CI 2개(static, e2e)가 돌고, plan 댓글이 달린다
- [ ] 브랜치 보호 규칙을 만들고, CI 실패 시 머지가 막히는 것을 확인했다
- [ ] "state를 왜 원격에 두는가", "lock이 없으면 무슨 일이 생기나"를 설명할 수 있다

다음: **3단계: IAM Role / Instance Profile (최소 권한)**
