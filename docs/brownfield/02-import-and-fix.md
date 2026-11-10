# Brownfield 02: 가져오고(import), 코드로 고치기

## 이번에 하는 일

조사에서 찾은 문제 하나를 골라 **실무와 똑같은 순서로** 고칩니다.

> **대상: `web` SG** — 22번(SSH)과 8080번이 인터넷 전체(`0.0.0.0/0`)에 열려 있음
> **목표: 22번과 8080번을 인터넷에서 닫기. 단, 콘솔이 아니라 Terraform으로.**

```
① import    기존 SG를 Terraform이 "내 것"으로 인식하게 연결    → 실제 SG 변화 없음 (태그만 추가)
② 정리      plan 이 "의도한 변경만" 보이도록 코드 정돈
③ 수정      코드에서 위험한 규칙 삭제 → plan 에 "- 22번" 표시
④ apply     실제 SG에서 22번이 닫힘
⑤ 재발 방지  누가 콘솔로 22번을 다시 열면 → plan 이 잡아냄 → apply 로 다시 닫힘
```

이 다섯 단계가 회사 계정에서 **SG 하나, IAM 사용자 하나를 정리할 때마다 반복할 루프**입니다.

---

## 준비

```bash
cd ~/personal/iac-practice
eval "$(mise activate zsh)"
export AWS_PAGER=""
```

작업 폴더는 `terraform/envs/brownfield/`입니다. provider와 backend 설정은 미리 넣어두었습니다(`providers.tf`, `backend.tf`, `versions.tf`). state는 1단계 네트워크와 **분리**되어 있습니다.

```bash
terraform -chdir=terraform/envs/brownfield init
```

---

## ① import: 기존 SG를 코드에 연결

### 1-1. 가져올 SG의 ID 찾기

```bash
aws ec2 describe-security-groups --filters Name=group-name,Values=web \
  --query 'SecurityGroups[0].GroupId' --output text
```

### 1-2. import 블록 작성 (직접)

`terraform/envs/brownfield/import.tf` 파일을 **직접 만들고** 아래 내용을 씁니다. `sg-xxxx`는 위에서 찾은 ID로 바꿉니다.

```hcl
import {
  to = aws_security_group.web
  id = "sg-xxxx"
}
```

- `to`: 코드에서 이 SG를 부를 이름. `aws_security_group`(리소스 종류) + `web`(내가 붙이는 이름)
- `id`: 실제 AWS에 있는 SG의 ID

**뜻: "실제로 있는 sg-xxxx를, 코드의 aws_security_group.web으로 관리하겠다."**

### 1-3. 코드 자동 생성

SG 설정을 손으로 옮겨 적을 필요가 없습니다. Terraform이 실제 SG를 읽어서 코드를 만들어줍니다.

```bash
terraform -chdir=terraform/envs/brownfield plan -generate-config-out=generated.tf
```

`terraform/envs/brownfield/generated.tf`가 생깁니다. **열어서 읽어보세요.** 조사에서 CLI로 봤던 규칙들이 그대로 코드로 적혀 있습니다.

plan 결과의 마지막 줄을 확인하세요.

```
Plan: 1 to import, 0 to add, 1 to change, 0 to destroy.
```

- `1 to import`: SG 하나를 가져옴
- `1 to change`: 무엇이 바뀌는지 plan을 위로 올려서 직접 확인하세요. `tags_all`에 `+ ManagedBy = "terraform"` 같은 **태그 추가**만 있으면 정상입니다(`providers.tf`의 `default_tags` 때문).
- **`destroy`가 0이 아니거나 `ingress`가 바뀐다고 나오면 멈추세요.** 코드가 실제와 다르다는 뜻입니다.

### 1-4. apply

```bash
terraform -chdir=terraform/envs/brownfield apply
```

plan을 다시 보여주고 `yes`를 입력하라고 합니다. 내용이 1-3과 같은지 확인하고 `yes`를 입력합니다.

**이 시점에 실제 SG에 일어난 변화는 태그 2개 추가뿐입니다.** 규칙은 하나도 바뀌지 않습니다.

```bash
terraform -chdir=terraform/envs/brownfield plan
# → No changes.   코드 = 실제. 이제 이 SG는 Terraform이 관리합니다.
```

---

## ② 정리

- `generated.tf`를 `web-sg.tf`로 이름을 바꿉니다. 자동 생성 파일이라는 표시를 없애고 정식 코드로 삼는 것입니다.
- `import.tf`는 **지워도 됩니다.** 이미 state에 기록됐기 때문에 다시 필요 없습니다. 실무에서는 기록을 위해 PR에 남겨두기도 합니다.
- 지운 뒤에도 `plan`이 `No changes`인지 확인합니다.

---

## ③ 수정: 위험한 규칙 삭제 (직접)

`web-sg.tf`의 `ingress = [ ... ]` 안에는 규칙이 `{ ... }` 단위로 나열되어 있습니다.

1. `from_port = 22`이고 `cidr_blocks = ["0.0.0.0/0"]`인 `{ ... }` 블록을 **통째로 삭제**합니다.
   - `211.234.10.5/32`(사무실)에서 오는 22번 규칙은 **남깁니다.**
2. `from_port = 8080`인 블록도 삭제합니다.
3. 쉼표(`,`)가 남거나 빠지지 않게 주의하세요. 저장할 때 자동 포맷이 정리해줍니다.

```bash
terraform -chdir=terraform/envs/brownfield plan
```

plan에 **삭제할 두 규칙만 `-`로** 표시되는지 확인하세요. 다른 규칙에 `-`나 `+`가 보이면 블록을 잘못 지운 것입니다.

**실무라면 여기서 PR을 올립니다.** 리뷰어는 이 plan을 보고 "22번 닫는 거 맞네, 사무실 IP는 남아 있네"를 확인합니다.

---

## ④ apply

```bash
terraform -chdir=terraform/envs/brownfield apply
```

실제로 닫혔는지 **Terraform 바깥에서** 확인합니다.

```bash
aws ec2 describe-security-groups --filters Name=group-name,Values=web \
  --query 'SecurityGroups[0].IpPermissions[].{Port:FromPort, From:IpRanges[].CidrIp}' --output json
```

---

## ⑤ 재발 방지 확인

누군가 콘솔에서 "잠깐만" 하고 22번을 다시 열었다고 해봅시다.

```bash
WEB=$(aws ec2 describe-security-groups --filters Name=group-name,Values=web --query 'SecurityGroups[0].GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $WEB \
  --ip-permissions 'IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=0.0.0.0/0,Description=hotfix}]'

terraform -chdir=terraform/envs/brownfield plan     # → 다시 연 22번이 "- " 로 잡힘
terraform -chdir=terraform/envs/brownfield apply    # → 다시 닫힘
```

`ingress = [...]`처럼 **규칙 전체를 코드에 적어두면**, 코드에 없는 규칙은 전부 drift로 잡힙니다. 1단계에서 `route = []`로 "없어야 하는 것"까지 관리했던 것과 같은 원리입니다.

---

## 회사에서 이 루프를 돌릴 때

| 단계 | 주의할 점 |
|---|---|
| ① import | 읽기 권한 + state 저장소 쓰기 권한이면 충분. **실제 리소스는 바뀌지 않음** (태그 제외) |
| 1-3 plan | **`1 to change`의 내용을 반드시 확인.** 태그 외의 변경이 보이면 apply 금지 |
| ③ 수정 | 닫기 전에 **그 포트를 누가 쓰는지 확인하고 공지.** 22번을 닫으면 SSH로 들어가던 사람이 막힘 |
| ④ apply | 개발 계정 먼저, 그다음 운영. 문제가 생기면 코드를 되돌려(`git revert`) 다시 apply |
| ⑤ 재발 방지 | Terraform은 **plan을 돌려야만** 잡음. 정기적으로 plan을 돌리는 CI(drift 감지)와, 콘솔 수정 권한 회수가 함께 필요 |
