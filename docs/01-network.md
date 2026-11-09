# 1단계: network 모듈 (VPC, 서브넷, 라우팅)

## 이번 단계의 목표
- 3계층(public / app / db) VPC를 **재사용 가능한 모듈**로 만든다.
- "public/private은 이름이 아니라 **라우팅 테이블**이 결정한다"를 이해한다.
- `terraform test`로 **인프라 없이** 모듈을 검증한다.
- 콘솔 수동 변경(ClickOps)을 흉내 내서 **Terraform이 무엇을 잡고 무엇을 놓치는지** 직접 확인한다.

---

## 1. 만든 구조

```
                         Internet
                            │
                     ┌──────┴──────┐
                     │     IGW     │
                     └──────┬──────┘
 VPC 10.0.0.0/16            │
 ┌──────────────────────────┼─────────────────────────────────┐
 │        AZ a              │              AZ c              │
 │  ┌───────────────────┐   │    ┌───────────────────┐       │
 │  │ public 10.0.0.0/24│◀──┴───▶│ public 10.0.2.0/24│       │  rt: 0.0.0.0/0 → IGW
 │  │   [NAT + EIP]     │        │                   │       │
 │  └────────┬──────────┘        └───────────────────┘       │
 │           │ (모든 AZ 의 app 이 이 NAT 하나를 공유: single_nat)    │
 │  ┌────────▼──────────┐        ┌───────────────────┐       │
 │  │ app  10.0.10.0/24 │        │ app  10.0.12.0/24 │       │  rt: 0.0.0.0/0 → NAT
 │  └───────────────────┘        └───────────────────┘       │
 │  ┌───────────────────┐        ┌───────────────────┐       │
 │  │ db   10.0.20.0/24 │        │ db   10.0.22.0/24 │       │  rt: (인터넷 라우트 없음)
 │  └───────────────────┘        └───────────────────┘       │
 └────────────────────────────────────────────────────────────┘
```

| 계층 | 4단계 이후 들어갈 것 | 밖에서 들어오기 | 밖으로 나가기 |
|---|---|---|---|
| public | ALB, NAT | O | O (IGW) |
| app | EC2 | X | O (NAT 경유, 패키지 설치나 외부 API 호출) |
| db | RDS | X | X |

모든 라우팅 테이블에는 `10.0.0.0/16 → local` 라우트가 **자동으로** 들어 있습니다.
그래서 app에 있는 EC2가 db에 있는 RDS로 접속하는 VPC 내부 통신은 라우트를 따로 만들지 않아도 됩니다.
이 통신을 실제로 허용하거나 막는 건 5단계에서 다룰 **Security Group**의 역할입니다.

---

## 2. 파일 구조: 모듈과 환경을 나누는 이유

```
terraform/
├── modules/network/          # "어떻게 만드는가" — 재사용 단위, 값은 변수로 받음
│   ├── versions.tf           #   필요한 provider 선언 (provider 설정 블록은 두지 않음!)
│   ├── variables.tf          #   입력 + validation
│   ├── main.tf               #   리소스
│   ├── outputs.tf            #   다른 모듈이 쓸 값만 공개
│   └── tests/*.tftest.hcl    #   단위 테스트
└── envs/local/               # "무엇을, 어떤 값으로" — 모듈 조립 + 환경별 값
```

- 실무에서는 `envs/dev`, `envs/prod`가 **같은 모듈**에 다른 값을 넘깁니다. 예를 들어 prod는 `single_nat_gateway = false`로 둡니다. 이렇게 하면 "dev에서 검증한 코드 = prod에 나가는 코드"가 됩니다.
- 모듈 안에 `provider "aws" {}` 블록을 두면 안 됩니다. 리전이나 계정 같은 설정은 호출하는 쪽이 정해야 모듈을 재사용할 수 있습니다.

---

## 3. 코드에서 꼭 볼 포인트

### ① `cidrsubnet()`으로 CIDR 계산
```hcl
cidrsubnet("10.0.0.0/16", 8, 10)  # → "10.0.10.0/24"
```
`/16`에 8비트를 더하면 `/24`가 되고, 그중 10번째 블록을 고릅니다.

블록 번호 = **계층 시작 번호(public 0 / app 10 / db 20) + AZ 끝 글자 번호(a=0, b=1, c=2)**

| | 2a | 2b | 2c |
|---|---|---|---|
| public | 10.0.0.0/24 | 10.0.1.0/24 | 10.0.2.0/24 |
| app | 10.0.10.0/24 | 10.0.11.0/24 | 10.0.12.0/24 |
| db | 10.0.20.0/24 | 10.0.21.0/24 | 10.0.22.0/24 |

> **실제로 겪은 버그.** 처음에는 AZ 번호를 "목록에서의 순서"로 매겼습니다. 그러자 실습 D에서 AZ 목록을 `[a, c]`에서 `[a, b, c]`로 바꿨을 때 c의 번호가 1에서 2로 밀렸습니다. 그 결과 c 서브넷 3개의 CIDR이 바뀌면서 **멀쩡한 서브넷이 교체(replace)되는 plan**이 나왔습니다.
> for_each로 리소스 키는 안정적으로 만들었지만, **CIDR 계산에 순번이 남아 있으면** 같은 문제가 그대로 생깁니다.
> 서브넷 CIDR이 바뀌면 서브넷이 재생성되고, 그 안의 EC2와 RDS도 함께 재생성됩니다. 실제 환경이었다면 장애입니다.
> 그래서 번호를 AZ 글자에서 계산하도록 고쳤고, 같은 실수가 다시 들어오지 않도록 회귀 테스트 `adding_az_keeps_existing_cidrs`를 추가했습니다.

직접 해보기: `mise exec -- terraform -chdir=terraform/envs/local console` 실행 후 `cidrsubnet("10.0.0.0/16", 8, 22)`

### ② `count` 대신 `for_each`
```
count    : aws_subnet.this[0], [1], [2] ...                   ← 순번으로 기억
for_each : aws_subnet.this["app/ap-northeast-2a"] ...         ← 이름(키)으로 기억
```
`count`를 쓰면 목록 중간 항목을 지울 때 뒤 번호가 한 칸씩 당겨집니다. 그러면 Terraform은 "1번이 바뀌었으니 지우고 다시 만든다"고 판단합니다. `for_each`는 키가 그대로라서 해당 항목만 영향을 받습니다. **실무에서 여러 개의 리소스를 만들 때는 거의 항상 `for_each`를 씁니다.**

### ③ `aws_default_security_group`으로 기본 SG 무력화
AWS는 VPC를 만들 때마다 "같은 SG끼리 전부 허용"하는 기본 SG를 자동으로 만듭니다. 이 리소스를 규칙 없이 선언하면 Terraform이 그 SG를 넘겨받아 **규칙을 모두 비웁니다.** CIS Benchmark에도 있는 실무 보안 권고사항입니다.

### ④ `route = []`: "없음"도 명시해야 관리된다 (이번 단계의 핵심)
아래 5번 실습에서 직접 확인합니다.

---

## 4. 테스트 (`make test`)

```
run "creates_three_tiers_per_az"... pass   서브넷 6개, CIDR 규칙, 공인 IP 자동할당 OFF
run "db_tier_has_no_internet_route"... pass  db 격리 + route = [] 유지
run "single_nat_by_default"... pass
run "nat_per_az_for_prod"... pass
run "no_nat_when_disabled"... pass
run "rejects_single_az"... pass             잘못된 입력이 "거부되는지" 테스트
run "adding_az_keeps_existing_cidrs"... pass  회귀 테스트: AZ 추가 시 기존 CIDR 불변
run "rejects_invalid_cidr"... pass
```

- `mock_provider "aws" {}`: AWS도 Floci도 호출하지 않습니다. 그래서 몇 초 만에 끝나고, CI에서도 그대로 돌릴 수 있습니다.
- `expect_failures`: "이 입력은 **실패해야** 통과"라는 뜻입니다. validation 규칙이 실수로 지워지는 걸 막아줍니다.
- 이 테스트는 **"코드가 의도대로 계획되는가"**를 확인합니다. "실제로 패킷이 통하는가"는 확인하지 않습니다.

---

## 5. 직접 해보기: ClickOps와 Drift

> 아래는 제가 실제로 실행해서 확인한 결과입니다. 직접 따라 해보세요.

### 실습 A: 누군가 콘솔에서 태그를 바꿨다
```bash
VPC=$(mise exec -- terraform -chdir=terraform/envs/local output -raw vpc_id)
mise exec -- aws ec2 create-tags --resources $VPC --tags Key=Environment,Value=hacked
make plan
```
결과: `~ "Environment" = "hacked" -> "local"` → **감지됨.** `make apply`를 실행하면 원래대로 복구됩니다.

### 실습 B: 누군가 DB 서브넷을 인터넷에 열었다 ⚠️
```bash
DBRT=$(mise exec -- aws ec2 describe-route-tables \
  --filters Name=tag:Name,Values=iac-practice-local-db-rt \
  --query 'RouteTables[0].RouteTableId' --output text)
IGW=$(mise exec -- aws ec2 describe-internet-gateways \
  --filters Name=attachment.vpc-id,Values=$VPC \
  --query 'InternetGateways[0].InternetGatewayId' --output text)
mise exec -- aws ec2 create-route --route-table-id $DBRT \
  --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW
make plan
```
- `route = []`가 **없던 처음 버전**에서는 태그 변경만 감지되고, 이 라우트는 **"No changes"로 그냥 넘어갔습니다.**
- 이유: Terraform은 **코드에 적힌 속성만** 비교합니다. `route`를 아예 안 적으면 "관심 없음"으로 취급합니다.
- `route = []`를 명시한 지금은 `- cidr_block = "0.0.0.0/0"`로 감지되고, apply하면 제거됩니다.

**교훈**
1. "Terraform이 drift를 다 잡아준다"는 말은 틀렸습니다. **코드에 선언된 범위만** 잡습니다.
2. 보안상 중요한 "없어야 하는 것"은 비어 있다는 것까지 명시해야 합니다.
3. 코드 밖에서 생긴 리소스(예: 누군가 콘솔에서 새로 만든 SG)는 Terraform이 아예 모릅니다. 실무에서는 AWS Config, Security Hub 같은 별도 도구로 보완합니다.

### 실습 C: drift 감지를 자동화하려면
```bash
mise exec -- terraform -chdir=terraform/envs/local plan -detailed-exitcode
echo $?   # 0 = 변경 없음, 1 = 에러, 2 = drift(변경 있음)
```
7단계에서는 이 종료 코드를 스케줄 CI에 연결해서, 2가 나오면 알림을 보내도록 만듭니다.

### 실습 D: count와 for_each 차이 체감
`envs/local/main.tf`의 `locals.azs` 필터를 `["a", "b", "c"]`로 바꾸고 `make plan`을 실행해보세요.
- 결과: `Plan: 8 to add, 0 to change, 0 to destroy`. b AZ 관련 리소스만 **추가**되고, 기존 a와 c는 그대로입니다.
- 만약 `count`를 썼거나, 위 3-① 버그처럼 CIDR을 순번으로 계산했다면 어땠을까요? c의 순번이 1에서 2로 밀려서 `must be replaced`가 나옵니다. 고치기 전 코드에서 실제로 `6 to destroy`가 나왔습니다.
- 확인한 뒤에는 apply하지 말고 `["a", "c"]`로 되돌리세요.

---

## 6. Floci 환경의 한계
- 라우팅 테이블, NAT, IGW는 **API 수준**에서만 만들어집니다. 실제로 패킷이 NAT를 지나가는지는 검증되지 않습니다.
- 실제 AWS에서는 NAT Gateway가 **시간당 과금**됩니다(서울 리전 기준 월 약 $45 + 트래픽 비용). `single_nat_gateway` 같은 비용 변수가 왜 있는지 기억해두세요.

## 7. 체크리스트
- [ ] `make check` 통과 (fmt, validate, lint, test 8개)
- [ ] `make plan`과 `make apply`로 24개 리소스 생성, 재실행 시 "No changes"
- [ ] 실습 B에서 `route = []`를 잠시 지웠을 때와 있을 때의 plan 차이 확인
- [ ] "왜 for_each인가", "왜 route = []인가"를 각각 한 문장으로 설명할 수 있다

다음: **2단계: Remote State(S3 + lock)와 PR CI**
