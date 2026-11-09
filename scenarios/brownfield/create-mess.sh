#!/usr/bin/env bash
# =====================================================================
#  ⚠️  스포일러 주의 — 조사 과제(docs/brownfield/01-inventory.md)를
#      끝내기 전에는 이 파일을 읽지 마세요.
# ---------------------------------------------------------------------
# "몇 년 동안 여러 사람이 콘솔에서 손으로 만든 AWS 계정"을 Floci 에 재현합니다.
# 실행: make mess   (Floci 가 떠 있어야 함)
# 한 번만 실행하세요. 다시 만들고 싶으면 make reset → make up → make mess
# =====================================================================
set -euo pipefail

a() { aws "$@"; }
say() { printf '\033[2m  - %s\033[0m\n' "$*"; }

if a ec2 describe-security-groups --filters Name=group-name,Values=temp-kim-test \
     --query 'length(SecurityGroups)' --output text | grep -qv '^0$'; then
  echo "이미 생성되어 있습니다. 다시 만들려면: make reset && make up && make mess"
  exit 0
fi

echo "회사 AWS 계정을 재현하는 중... (1~2분)"

tagspec() { # tagspec <resource-type> Key=Value ...
  local rt=$1; shift
  local tags="" kv
  for kv in "$@"; do tags+="{Key=${kv%%=*},Value=${kv#*=}},"; done
  echo "ResourceType=${rt},Tags=[${tags%,}]"
}

sg_rule() { # sg_rule <sg-id> <proto> <from> <to> <cidr> [desc]
  local desc=${6:-}
  a ec2 authorize-security-group-ingress --group-id "$1" \
    --ip-permissions "IpProtocol=$2,FromPort=$3,ToPort=$4,IpRanges=[{CidrIp=$5${desc:+,Description=$desc}}]" >/dev/null
}

sg_ref() { # sg_ref <sg-id> <proto> <port> <source-sg-id>
  a ec2 authorize-security-group-ingress --group-id "$1" \
    --ip-permissions "IpProtocol=$2,FromPort=$3,ToPort=$3,UserIdGroupPairs=[{GroupId=$4}]" >/dev/null
}

new_sg() { # new_sg <name> <desc> <vpc-id> [Key=Value ...]
  local name=$1 desc=$2 vpc=$3; shift 3
  if [ $# -gt 0 ]; then
    a ec2 create-security-group --group-name "$name" --description "$desc" --vpc-id "$vpc" \
      --tag-specifications "$(tagspec security-group "$@")" --query GroupId --output text
  else
    a ec2 create-security-group --group-name "$name" --description "$desc" --vpc-id "$vpc" \
      --query GroupId --output text
  fi
}

run_ec2() { # run_ec2 <type> <subnet> <sg-ids(comma)> <key|-> <profile|-> [Key=Value ...]
  local type=$1 subnet=$2 sgs=$3 key=$4 prof=$5; shift 5
  local args=(--image-id ami-alpine --instance-type "$type" --subnet-id "$subnet"
              --security-group-ids ${sgs//,/ } --count 1 --query 'Instances[0].InstanceId' --output text)
  [ "$key" != "-" ] && args+=(--key-name "$key")
  [ "$prof" != "-" ] && args+=(--iam-instance-profile "Name=$prof")
  [ $# -gt 0 ] && args+=(--tag-specifications "$(tagspec instance "$@")")
  a ec2 run-instances "${args[@]}"
}

# ---------------------------------------------------------------------
# 1. 네트워크
# ---------------------------------------------------------------------
say "network"
DEF_VPC=$(a ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
DEF_SUB_A=$(a ec2 describe-subnets --filters Name=vpc-id,Values="$DEF_VPC" Name=availability-zone,Values=ap-northeast-2a --query 'Subnets[0].SubnetId' --output text)
DEF_SUB_C=$(a ec2 describe-subnets --filters Name=vpc-id,Values="$DEF_VPC" Name=availability-zone,Values=ap-northeast-2c --query 'Subnets[0].SubnetId' --output text)

PROD_VPC=$(a ec2 create-vpc --cidr-block 10.10.0.0/16 --tag-specifications "$(tagspec vpc Name=prod-vpc env=prod)" --query Vpc.VpcId --output text)
PROD_SUB1=$(a ec2 create-subnet --vpc-id "$PROD_VPC" --cidr-block 10.10.1.0/24 --availability-zone ap-northeast-2a --tag-specifications "$(tagspec subnet Name=prod-public-1)" --query Subnet.SubnetId --output text)
PROD_SUB2=$(a ec2 create-subnet --vpc-id "$PROD_VPC" --cidr-block 10.10.2.0/24 --availability-zone ap-northeast-2c --tag-specifications "$(tagspec subnet Name=prod-public-2)" --query Subnet.SubnetId --output text)
a ec2 create-subnet --vpc-id "$PROD_VPC" --cidr-block 10.10.100.0/24 --availability-zone ap-northeast-2a --query Subnet.SubnetId --output text >/dev/null
PROD_IGW=$(a ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text)
a ec2 attach-internet-gateway --internet-gateway-id "$PROD_IGW" --vpc-id "$PROD_VPC"

# dev 는 prod 와 똑같은 대역으로 만들어버림 (나중에 VPC 연결 불가)
DEV_VPC=$(a ec2 create-vpc --cidr-block 10.10.0.0/16 --tag-specifications "$(tagspec vpc Name=dev-vpc Env=Development)" --query Vpc.VpcId --output text)
a ec2 create-subnet --vpc-id "$DEV_VPC" --cidr-block 10.10.1.0/24 --availability-zone ap-northeast-2a --query Subnet.SubnetId --output text >/dev/null

# 누가 왜 만들었는지 모르는 VPC
a ec2 create-vpc --cidr-block 192.168.0.0/16 --query Vpc.VpcId --output text >/dev/null

# ---------------------------------------------------------------------
# 2. 보안 그룹
# ---------------------------------------------------------------------
say "security groups"
LW1=$(new_sg launch-wizard-1 "launch-wizard-1 created 2022-03-14T10:22:01.123+09:00" "$DEF_VPC")
sg_rule "$LW1" tcp 22 22 0.0.0.0/0

LW2=$(new_sg launch-wizard-2 "launch-wizard-2 created 2022-07-02T15:40:11.551+09:00" "$DEF_VPC")
sg_rule "$LW2" tcp 22 22 0.0.0.0/0
sg_rule "$LW2" tcp 80 80 0.0.0.0/0
sg_rule "$LW2" tcp 3389 3389 0.0.0.0/0

LW3=$(new_sg launch-wizard-3 "launch-wizard-3 created 2023-01-19T09:02:44.004+09:00" "$DEF_VPC")
sg_rule "$LW3" tcp 22 22 0.0.0.0/0

WEB=$(new_sg web "web server" "$DEF_VPC" Name=web owner=park)
sg_rule "$WEB" tcp 80 80 0.0.0.0/0
sg_rule "$WEB" tcp 443 443 0.0.0.0/0
sg_rule "$WEB" tcp 8080 8080 0.0.0.0/0 "tomcat test"
sg_rule "$WEB" tcp 22 22 0.0.0.0/0 "temp"
sg_rule "$WEB" tcp 22 22 211.234.10.5/32 "office"

JENKINS=$(new_sg jenkins "jenkins" "$DEF_VPC" name=jenkins)
sg_rule "$JENKINS" tcp 8080 8080 211.234.10.5/32 "office"
sg_rule "$JENKINS" tcp 8080 8080 0.0.0.0/0 "github webhook"
sg_rule "$JENKINS" tcp 22 22 0.0.0.0/0
sg_rule "$JENKINS" tcp 50000 50000 0.0.0.0/0

INTERNAL=$(new_sg allow-all-internal "allow all internal" "$DEF_VPC")
sg_rule "$INTERNAL" -1 -1 -1 172.31.0.0/16

TEMP=$(new_sg temp-kim-test "임시 - 테스트 후 삭제 예정 (2023.05)" "$DEF_VPC" Name=temp owner=kim)
sg_rule "$TEMP" -1 -1 -1 0.0.0.0/0

PRODWEB=$(new_sg prod-web-sg "prod web" "$PROD_VPC" Name=prod-web-sg Env=Production)
sg_rule "$PRODWEB" tcp 80 80 0.0.0.0/0
sg_rule "$PRODWEB" tcp 443 443 0.0.0.0/0
sg_rule "$PRODWEB" tcp 22 22 0.0.0.0/0

PRODDB=$(new_sg prod-db "prod database" "$PROD_VPC" Name=prod-db env=prod)
sg_ref  "$PRODDB" tcp 3306 "$PRODWEB"
sg_rule "$PRODDB" tcp 3306 3306 0.0.0.0/0 "for DBeaver"
sg_rule "$PRODDB" tcp 5432 5432 0.0.0.0/0

OLDAPI=$(new_sg old-api-sg "old api" "$DEF_VPC")
sg_rule "$OLDAPI" tcp 3000 3000 0.0.0.0/0
BACKUP_SG=$(new_sg sg-backup-do-not-delete "DO NOT DELETE" "$DEF_VPC")
sg_rule "$BACKUP_SG" tcp 0 65535 0.0.0.0/0

# ---------------------------------------------------------------------
# 3. IAM
# ---------------------------------------------------------------------
say "iam"
ADMIN_DOC='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}'
ADMIN_ARN=$(a iam create-policy --policy-name AdminAccess-copy --policy-document "$ADMIN_DOC" --query Policy.Arn --output text)
EC2_TRUST='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

a iam create-user --user-name deploy-bot >/dev/null
a iam attach-user-policy --user-name deploy-bot --policy-arn "$ADMIN_ARN"
a iam create-access-key --user-name deploy-bot >/dev/null
a iam create-access-key --user-name deploy-bot >/dev/null

a iam create-user --user-name kim.dev --tags Key=team,Value=backend >/dev/null
a iam put-user-policy --user-name kim.dev --policy-name full --policy-document "$ADMIN_DOC"
a iam create-access-key --user-name kim.dev >/dev/null

a iam create-user --user-name park.intern >/dev/null
a iam put-user-policy --user-name park.intern --policy-name s3-ec2 --policy-document \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:*","ec2:*"],"Resource":"*"}]}'
a iam create-access-key --user-name park.intern >/dev/null

a iam create-user --user-name jenkins >/dev/null
a iam put-user-policy --user-name jenkins --policy-name jenkins-deploy --policy-document \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["ec2:*","s3:*","iam:PassRole","iam:CreateRole","iam:AttachRolePolicy"],"Resource":"*"}]}'
a iam create-access-key --user-name jenkins >/dev/null

a iam create-user --user-name lee.resigned >/dev/null
a iam attach-user-policy --user-name lee.resigned --policy-arn "$ADMIN_ARN"
a iam create-access-key --user-name lee.resigned >/dev/null

a iam create-group --group-name developers >/dev/null
a iam attach-group-policy --group-name developers --policy-arn "$ADMIN_ARN"
a iam add-user-to-group --group-name developers --user-name kim.dev
a iam add-user-to-group --group-name developers --user-name park.intern

a iam create-role --role-name ec2-role-test --assume-role-policy-document "$EC2_TRUST" >/dev/null
a iam attach-role-policy --role-name ec2-role-test --policy-arn "$ADMIN_ARN"
a iam create-instance-profile --instance-profile-name ec2-role-test >/dev/null
a iam add-role-to-instance-profile --instance-profile-name ec2-role-test --role-name ec2-role-test

a iam create-role --role-name old-lambda-role --assume-role-policy-document \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null

# ---------------------------------------------------------------------
# 4. EC2 (Floci 가 실제 컨테이너로 띄움)
# ---------------------------------------------------------------------
say "ec2 (컨테이너 기동, 시간이 조금 걸립니다)"
a ec2 create-key-pair --key-name kim-laptop --query KeyFingerprint --output text >/dev/null
a ec2 create-key-pair --key-name prod-key-old --query KeyFingerprint --output text >/dev/null
a ec2 create-key-pair --key-name test --query KeyFingerprint --output text >/dev/null

run_ec2 t3.medium "$DEF_SUB_A" "$WEB,$LW1"      prod-key-old -              Name=web-01 env=prod >/dev/null
run_ec2 t3.medium "$DEF_SUB_C" "$LW2"           prod-key-old -              Name=web-02 >/dev/null
run_ec2 m5.large  "$DEF_SUB_A" "$JENKINS,$INTERNAL" kim-laptop ec2-role-test Name=api-server-NEW-final >/dev/null
run_ec2 t3.large  "$DEF_SUB_C" "$JENKINS"       kim-laptop -                Name=jenkins >/dev/null
run_ec2 c5.4xlarge "$DEF_SUB_A" "$TEMP"         test       -                >/dev/null
run_ec2 t3.small  "$PROD_SUB1" "$PRODWEB"       prod-key-old -              Name=prod-web Env=Production >/dev/null
run_ec2 t2.micro  "$PROD_SUB2" "$PRODWEB,$PRODDB" prod-key-old -            Name=prod-web-2 >/dev/null

# ---------------------------------------------------------------------
# 5. 돈만 나가는 것들
# ---------------------------------------------------------------------
say "eip / ebs"
a ec2 allocate-address --domain vpc --query AllocationId --output text >/dev/null
a ec2 allocate-address --domain vpc --tag-specifications "$(tagspec elastic-ip Name=old-jenkins-ip)" --query AllocationId --output text >/dev/null
a ec2 create-volume --availability-zone ap-northeast-2a --size 500 --volume-type gp2 --query VolumeId --output text >/dev/null || true
a ec2 create-volume --availability-zone ap-northeast-2c --size 100 --volume-type io1 --iops 3000 \
  --tag-specifications "$(tagspec volume Name=db-backup-tmp)" --query VolumeId --output text >/dev/null || true

# ---------------------------------------------------------------------
# 6. S3
# ---------------------------------------------------------------------
say "s3"
mk_bucket() { a s3api create-bucket --bucket "$1" --create-bucket-configuration LocationConstraint=ap-northeast-2 >/dev/null; }
mk_bucket company-prod-backup-2023
a s3api delete-public-access-block --bucket company-prod-backup-2023 >/dev/null 2>&1 || true
a s3api put-bucket-policy --bucket company-prod-backup-2023 --policy \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":"*","Action":"s3:GetObject","Resource":"arn:aws:s3:::company-prod-backup-2023/*"}]}'
printf 'id,email,phone\n1,user1@example.com,010-0000-0001\n' > /tmp/.mess-users.csv
a s3 cp /tmp/.mess-users.csv s3://company-prod-backup-2023/db-dump/users_20230512.csv >/dev/null
rm -f /tmp/.mess-users.csv
mk_bucket kim-test-bucket-123
mk_bucket app-logs-prod
mk_bucket app-logs-prod-new

echo "완료. 이제 docs/brownfield/01-inventory.md 의 과제를 시작하세요."
