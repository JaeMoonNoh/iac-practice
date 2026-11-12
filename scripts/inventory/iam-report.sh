#!/usr/bin/env bash
# =====================================================================
# iam-report.sh — IAM 사용자/역할별 권한 요약 (읽기 전용)
# ---------------------------------------------------------------------
# 누가 어떤 권한을 "어디서" 받았는지(직접 / 인라인 / 그룹)와
# 관리자 권한(Action "*" + Resource "*") 여부, 액세스 키 개수를 한 표로 보여줍니다.
#
# 사용:
#   Floci 연습  : cd ~/personal/iac-practice && eval "$(mise activate zsh)" && ./scripts/inventory/iam-report.sh
#   회사 계정   : cd ~ && aws-vault exec <프로파일> -- ~/personal/iac-practice/scripts/inventory/iam-report.sh
#
# 필요한 권한: iam:GetAccountAuthorizationDetails, iam:ListAccessKeys,
#             iam:GetAccessKeyLastUsed  (AWS 관리형 SecurityAudit 정책에 포함)
# 이 스크립트는 아무것도 변경하지 않습니다.
# =====================================================================
set -euo pipefail
export AWS_PAGER=""

# 1) IAM 전체 정보를 한 번에 가져옴 (사용자, 그룹, 역할, 정책 문서 전부)
AUTH=$(aws iam get-account-authorization-details --output json)

# 관리자 판정 + 권한 출처 정리 (jq 함수)
JQ_LIB='
  def arr: if type == "array" then . else [.] end;
  def isadmin: [.Statement] | flatten
      | any(.Effect == "Allow" and ((.Action | arr) | index("*")) and ((.Resource | arr) | index("*")));
  (.Policies | map({(.Arn): (.PolicyVersionList[] | select(.IsDefaultVersion) | .Document)}) | add // {}) as $pol
  | (.GroupDetailList | map({(.GroupName): [.AttachedManagedPolicies[].PolicyArn]}) | add // {}) as $grp
  |
'

echo "## IAM 사용자"
{
  printf 'USER\tKEYS\tKEY_LAST_USED\tPOLICIES (출처/이름)\tADMIN\n'
  echo "$AUTH" | jq -r "$JQ_LIB"'
    .UserDetailList[] | .UserName as $u
    | ( [.AttachedManagedPolicies[] | {src: "직접",   name: .PolicyName, d: $pol[.PolicyArn]}]
      + [.UserPolicyList[]?         | {src: "인라인", name: .PolicyName, d: .PolicyDocument}]
      + [.GroupList[] as $g | ($grp[$g] // [])[] | {src: ("그룹:" + $g), name: (split("/") | last), d: $pol[.]}]
      ) as $all
    | [$u,
       ($all | map(.src + "/" + .name) | join(", ")),
       (if ($all | any(.d != null and (.d | isadmin))) then "⚠️ 관리자" else "-" end)]
    | @tsv' |
  while IFS=$'\t' read -r user policies admin; do
    keys=$(aws iam list-access-keys --user-name "$user" --query 'AccessKeyMetadata[].AccessKeyId' --output text)
    count=$(echo "$keys" | wc -w | tr -d ' ')
    last="-"
    for k in $keys; do
      d=$(aws iam get-access-key-last-used --access-key-id "$k" --query 'AccessKeyLastUsed.LastUsedDate' --output text)
      [ "$d" != "None" ] && last="$d"
    done
    [ "$count" -gt 0 ] && [ "$last" = "-" ] && last="사용기록없음"
    printf '%s\t%s\t%s\t%s\t%s\n' "$user" "$count" "$last" "${policies:--}" "$admin"
  done
} | column -t -s $'\t'

echo
echo "## IAM 역할 (Role)"
{
  printf 'ROLE\tWHO_CAN_USE (신뢰 정책)\tPOLICIES\tADMIN\n'
  echo "$AUTH" | jq -r "$JQ_LIB"'
    .RoleDetailList[]
    | ( [.AttachedManagedPolicies[] | {name: .PolicyName, d: $pol[.PolicyArn]}]
      + [.RolePolicyList[]?         | {name: .PolicyName, d: .PolicyDocument}] ) as $all
    | [.RoleName,
       ([.AssumeRolePolicyDocument.Statement[].Principal | (.Service // .AWS // "?") | arr[]] | join(",")),
       (($all | map(.name) | join(", ")) | if . == "" then "-" else . end),
       (if ($all | any(.d != null and (.d | isadmin))) then "⚠️ 관리자" else "-" end)]
    | @tsv'
} | column -t -s $'\t'
