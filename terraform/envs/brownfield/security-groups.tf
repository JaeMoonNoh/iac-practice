# 콘솔로 만들어졌던 SG. 2026-11 import 후 Terraform 관리

resource "aws_security_group" "launch_wizard_1" {
  description = "launch-wizard-1 created 2022-03-14T10:22:01.123+09:00"
  egress = [{
    cidr_blocks      = ["0.0.0.0/0"]
    description      = ""
    from_port        = 0
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
    protocol         = "-1"
    security_groups  = []
    self             = false
    to_port          = 0
  }]
  ingress                = []
  name                   = "launch-wizard-1"
  region                 = "ap-northeast-2"
  revoke_rules_on_delete = null
  tags                   = {}
  tags_all               = {}
  vpc_id                 = "vpc-default-ap-northeast-2"
}

resource "aws_security_group" "web" {
  description = "web server"
  egress = [{
    cidr_blocks      = ["0.0.0.0/0"]
    description      = ""
    from_port        = 0
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
    protocol         = "-1"
    security_groups  = []
    self             = false
    to_port          = 0
  }]
  ingress = [{
    cidr_blocks      = ["0.0.0.0/0"]
    description      = ""
    from_port        = 443
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
    protocol         = "tcp"
    security_groups  = []
    self             = false
    to_port          = 443
    }, {
    cidr_blocks      = ["0.0.0.0/0"]
    description      = ""
    from_port        = 80
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
    protocol         = "tcp"
    security_groups  = []
    self             = false
    to_port          = 80
    }, {
    cidr_blocks      = ["211.234.10.5/32"]
    description      = "office"
    from_port        = 22
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
    protocol         = "tcp"
    security_groups  = []
    self             = false
    to_port          = 22
  }]
  name                   = "web"
  region                 = "ap-northeast-2"
  revoke_rules_on_delete = null
  tags = {
    Name  = "web"
    owner = "park"
  }
  tags_all = {
    Name  = "web"
    owner = "park"
  }
  vpc_id = "vpc-default-ap-northeast-2"
}
