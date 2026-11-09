# Brownfield 01: 조사 (Inventory)

## 상황

당신은 이 회사에 인프라 담당으로 막 합류했습니다. AWS 계정은 몇 년 동안 여러 사람이 콘솔에서 직접 만들고 고쳐왔습니다. 문서는 없고, 아무도 전체 구성을 모릅니다.

팀장님의 요청은 이렇습니다.
> "우리 AWS를 Terraform으로 관리하고 싶은데, 일단 **지금 뭐가 있는지**부터 파악해줘. 그리고 **제일 위험한 것 5개**만 뽑아줘."

**Terraform 코드를 쓰기 전에, 무엇이 있는지 아는 것이 먼저입니다.** 모르는 것은 코드로 옮길 수 없습니다.

---

## 규칙

1. **읽기 명령만** 사용합니다. `describe-*`, `list-*`, `get-*`만 쓰세요. `create`, `delete`, `modify`, `authorize`, `revoke`는 금지입니다. 회사에서도 첫 조사는 읽기 전용 권한으로 합니다.
2. `scenarios/brownfield/create-mess.sh`는 **과제를 끝내기 전에 열어보지 마세요.** 정답지입니다.
3. 조사 결과는 [inventory.md](inventory.md)에 **직접** 정리합니다.

---

## 준비: AWS CLI 기본

### 셸 설정 (한 번만)

매번 `mise exec --`를 붙이기 번거로우니, 리포 폴더에서 아래를 실행해두세요. 그러면 이 터미널에서는 `aws`만 쳐도 Floci로 연결됩니다.

```bash
cd ~/personal/iac-practice
eval "$(mise activate zsh)"
aws sts get-caller-identity    # Account 가 000000000000 이면 Floci 에 연결된 것
```

### 명령 구조

```
aws  <서비스>  <동작>                  [옵션]
aws  ec2      describe-vpcs
aws  iam      list-users
aws  s3api    list-buckets
```

모르는 명령이 있으면 `aws ec2 help`, `aws ec2 describe-vpcs help`로 확인할 수 있습니다(`q`로 종료).

### 출력 형식: `--output`

```bash
aws ec2 describe-vpcs                    # JSON (기본). 전체 정보, 길다
aws ec2 describe-vpcs --output table     # 표. 사람이 읽기 좋다
aws ec2 describe-vpcs --output text      # 탭 구분. 다른 명령에 넘기기 좋다
```

### 필요한 것만 뽑기: `--query`

JSON이 너무 길면 `--query`로 원하는 칸만 고릅니다. 먼저 JSON을 한 번 보고, 구조를 따라 이름을 적으면 됩니다.

```bash
# 1) 먼저 전체 JSON 구조를 본다
aws ec2 describe-vpcs

# 2) Vpcs 목록에서 각 항목의 VpcId 와 CidrBlock 만
aws ec2 describe-vpcs --query 'Vpcs[].[VpcId, CidrBlock]' --output table

# 3) 칸에 이름을 붙이기
aws ec2 describe-vpcs --query 'Vpcs[].{ID:VpcId, CIDR:CidrBlock}' --output table

# 4) 태그 중 Name 값만 꺼내기 (태그는 [{Key:..,Value:..}] 목록이라 조금 복잡)
aws ec2 describe-vpcs --query 'Vpcs[].{ID:VpcId, CIDR:CidrBlock, Name:Tags[?Key==`Name`]|[0].Value}' --output table

# 5) 조건으로 거르기: --filters (AWS 쪽에서 거름)
aws ec2 describe-vpcs --filters Name=isDefault,Values=true --output table
```

| 문법 | 의미 |
|---|---|
| `Vpcs[]` | Vpcs 목록의 모든 항목 |
| `.[A, B]` | A, B 칸만 |
| `.{이름:A}` | A 칸에 이름 붙이기 |
| `Tags[?Key==\`Name\`]` | Tags 중 Key가 Name인 것만 |
| `\|[0].Value` | 그중 첫 번째의 Value |
| `length(Vpcs)` | 개수 |

---

## 과제

각 질문에 답하면서 [inventory.md](inventory.md)를 채우세요. 막히면 질문 아래의 힌트를 펼쳐보세요.

### Q1. 네트워크 (VPC)
1. VPC는 몇 개이고, 각각의 ID, CIDR, 이름은?
2. **이 중 Terraform이 관리하는 VPC는 어느 것인가?** 어떻게 구분했나?
3. CIDR가 겹치는 VPC가 있나? 겹치면 왜 문제인가?
4. 이름도 태그도 없는 VPC가 있나?

<details><summary>힌트</summary>

- 1단계에서 만든 VPC에는 provider의 `default_tags`가 붙어 있습니다. 태그 전체를 보려면 `--query 'Vpcs[].{ID:VpcId,Tags:Tags}'`
- 같은 대역을 쓰는 두 VPC는 나중에 서로 연결(VPC Peering)할 수 없습니다. 주소가 같으면 패킷을 어디로 보낼지 정할 수 없기 때문입니다.
</details>

### Q2. 보안 그룹 (SG): 가장 중요
1. SG는 몇 개이고, 각각의 이름, ID, 속한 VPC는?
2. **인터넷 전체(`0.0.0.0/0`)에 열려 있는 규칙**을 모두 찾으세요. SG 이름, 포트, 프로토콜을 정리합니다.
3. 그중 특히 위험한 포트는? (22, 3389, 3306, 5432, 그리고 **모든 포트**가 열린 경우)
4. IP 대신 **다른 SG를 출발지로 허용**하는 규칙이 있나? (SG 체이닝)

<details><summary>힌트</summary>

- `aws ec2 describe-security-groups --query 'SecurityGroups[].{Name:GroupName,ID:GroupId,VPC:VpcId}' --output table`
- 규칙은 `IpPermissions` 안에 있습니다. 먼저 SG 하나의 JSON을 자세히 보세요.
  `aws ec2 describe-security-groups --group-ids sg-xxxx`
- 규칙 단위로 보려면 `describe-security-group-rules`가 편합니다.
  `aws ec2 describe-security-group-rules --query 'SecurityGroupRules[?CidrIpv4==\`0.0.0.0/0\` && !IsEgress].{SG:GroupId,Proto:IpProtocol,From:FromPort,To:ToPort,Desc:Description}' --output table`
- `IpProtocol`이 `-1`이면 **모든 프로토콜, 모든 포트**입니다.
- `!IsEgress`는 "들어오는(inbound) 규칙만"이라는 뜻입니다.
</details>

### Q3. 서버 (EC2)
1. 인스턴스 목록: 이름, ID, 타입, 상태, 사설 IP, 붙은 SG, 키페어, IAM 프로파일
2. **이름(Name 태그)이 없는 인스턴스**는?
3. 가장 비싼 인스턴스 타입은? (참고: t3.medium은 시간당 약 $0.05, c5.4xlarge는 약 $0.77)
4. 같은 키페어를 여러 서버가 공유하나? 왜 문제인가?

<details><summary>힌트</summary>

- `aws ec2 describe-instances --query 'Reservations[].Instances[].{Name:Tags[?Key==\`Name\`]|[0].Value,ID:InstanceId,Type:InstanceType,State:State.Name,IP:PrivateIpAddress,Key:KeyName}' --output table`
- SG는 `SecurityGroups[].GroupName`, IAM 프로파일은 `IamInstanceProfile.Arn`
- `terminated` 상태는 이미 삭제된 서버입니다. 목록에서 잠시 보이다가 사라집니다.
</details>

### Q4. 아무도 안 쓰는 SG
1. **어떤 인스턴스에도 붙어 있지 않은 SG**는?
2. 그중 지워도 될 것 같은 것과, 함부로 지우면 안 될 것 같은 것을 구분해보세요. 이유는?

<details><summary>힌트</summary>

- Q2의 SG 목록과 Q3의 "인스턴스에 붙은 SG"를 비교합니다.
- 실제 AWS에서는 SG가 EC2 말고도 RDS, ELB, Lambda 등에 붙을 수 있습니다. "EC2에 없다 = 안 쓴다"가 아닐 수 있습니다. 그래서 실무에서는 `describe-network-interfaces`로 확인합니다.
- `default` SG는 VPC마다 자동으로 있고 지울 수 없습니다.
</details>

### Q5. 권한 (IAM)
1. IAM 유저 목록, 각 유저의 **액세스 키 개수**
2. 각 유저에게 붙은 권한: 관리형 정책(attached), 인라인 정책(inline), **그룹을 통해 받은 권한**까지
3. **모든 권한(`"Action": "*"`)을 가진 유저/역할**은?
4. 퇴사자로 보이는 계정이 있나?
5. EC2에 붙은 IAM 역할의 권한은?

<details><summary>힌트</summary>

- `aws iam list-users --output table`
- `aws iam list-access-keys --user-name <이름>`
- `aws iam list-attached-user-policies --user-name <이름>` (관리형)
- `aws iam list-user-policies --user-name <이름>` → `aws iam get-user-policy --user-name <이름> --policy-name <정책>` (인라인)
- `aws iam list-groups-for-user --user-name <이름>` → `aws iam list-attached-group-policies --group-name <그룹>`
- 정책 내용 보기: `aws iam get-policy-version --policy-arn <ARN> --version-id v1`
- 역할: `aws iam list-roles`, `aws iam list-attached-role-policies --role-name <이름>`
</details>

### Q6. 돈만 나가는 것
1. **어디에도 연결되지 않은 Elastic IP**는? (실제 AWS에서는 연결 안 된 EIP에도 요금이 붙습니다)
2. **어디에도 연결되지 않은 EBS 볼륨**은? 크기와 타입은?

<details><summary>힌트</summary>

- `aws ec2 describe-addresses --output table`에서 `AssociationId`나 `InstanceId`가 없는 것
- `aws ec2 describe-volumes --filters Name=status,Values=available --output table`
</details>

### Q7. S3
1. 버킷 목록
2. **누구나 읽을 수 있는(public) 버킷**이 있나? 안에 무엇이 들어 있나?

<details><summary>힌트</summary>

- `aws s3api list-buckets --output table`
- `aws s3api get-bucket-policy --bucket <이름>` → `"Principal": "*"`는 "누구나"라는 뜻
  - `NoSuchBucketPolicy` 에러는 "정책이 아예 없다"는 뜻이라 정상입니다.
- `aws s3 ls s3://<이름> --recursive`
</details>

### Q8. 태그 규칙
리소스에 붙은 태그를 보면 같은 의미인데 이름이 제각각인 것들이 있습니다. 어떤 것들이 있나요? 이게 왜 문제인가요?

---

## 최종 결과물

[inventory.md](inventory.md)에 다음을 정리합니다.
1. 리소스별 표 (VPC, SG, EC2, IAM, EIP/EBS, S3)
2. **위험 TOP 5**: 무엇이, 왜 위험하고, 어떻게 고쳐야 하는지

다 하셨으면 알려주세요. 같이 리뷰한 뒤, 다음 과제 **Brownfield 02: 코드로 가져오기(import)**로 넘어갑니다. 정리한 inventory를 바탕으로 SG 하나를 직접 `.tf`로 작성하고 Terraform 관리로 가져옵니다.

---

## 회사에 적용할 때

- 실제 AWS에는 리전이 여러 개입니다. **모든 리전을 확인**해야 합니다. 사람들이 실수로 버지니아(`us-east-1`)에 만들어두는 경우가 많습니다.
  `aws ec2 describe-regions --query 'Regions[].RegionName' --output text`
- 조사용으로 **ReadOnlyAccess 정책만 가진 IAM 사용자나 역할**을 따로 요청하세요.
- 콘솔에서는 **AWS Config**, **Resource Explorer**, **IAM Access Analyzer**, **Trusted Advisor**가 이 조사를 도와줍니다. 다만 CLI로 직접 한 번 해봐야 각 리소스의 구조를 이해할 수 있습니다.
