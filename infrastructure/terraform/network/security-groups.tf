resource "aws_security_group" "nat" {
  name        = "${local.prefix}-nat-sg"
  description = "Allows private subnet instances to reach the NAT instance"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Allow traffic from within the VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [local.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = [
      "::/0"
    ]
  }

  tags = {
    Name       = "${local.prefix}-nat-sg"
    "sg:role"  = "nat"
    "sg:scope" = "internet"
  }
}

resource "aws_security_group" "alb" {
  name        = "${local.prefix}-alb-sg"
  description = "Public ALB access controls"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = [
      "::/0"
    ]
  }

  tags = {
    Name       = "${local.prefix}-alb-sg"
    "sg:role"  = "alb"
    "sg:scope" = "public"
  }
}

resource "aws_security_group" "reverse_proxy" {
  name        = "${local.prefix}-proxy-sg"
  description = "Allows ALB traffic to reach reverse proxy"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = [
      "::/0"
    ]
  }

  tags = {
    Name       = "${local.prefix}-proxy-sg"
    "sg:role"  = "reverse-proxy"
    "sg:scope" = "base"
  }
}

# Per-service reverse proxy SGs — grants access to a specific TrueNAS service port
resource "aws_security_group" "reverse_proxy_service" {
  for_each = local.reverse_proxy_routes

  name        = "${local.prefix}-proxy-${replace(each.key, ".", "-")}-sg"
  description = "Reverse proxy access to ${each.key}"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name       = "${local.prefix}-proxy-${replace(each.key, ".", "-")}-sg"
    "sg:role"  = "reverse-proxy"
    "sg:scope" = each.key
  }
}

resource "aws_security_group" "ahara_lambda" {
  name        = "${local.prefix}-lambda-sg"
  description = "Shared security group for VPC Lambdas"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name       = "${local.prefix}-lambda-sg"
    project    = local.prefix
    "sg:role"  = "lambda"
    "sg:scope" = "ahara"
  }
}

resource "aws_security_group" "vpn_client" {
  name        = "${local.prefix}-vpn-client-sg"
  description = "Opt-in SG for Lambdas that need VPN/TrueNAS access"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name       = "${local.prefix}-vpn-client-sg"
    "sg:role"  = "vpn-client"
    "sg:scope" = "ahara"
  }
}

resource "aws_security_group" "wireguard" {
  name        = "${local.prefix}-sg"
  description = "WireGuard access controls"
  vpc_id      = aws_vpc.this.id

  ingress {
    description      = "WireGuard UDP ingress"
    from_port        = local.wireguard_port
    to_port          = local.wireguard_port
    protocol         = "udp"
    cidr_blocks      = local.allowed_cidrs
    ipv6_cidr_blocks = local.allowed_ipv6_cidrs
  }

  ingress {
    description = "DNS from WireGuard peers"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [local.wireguard_cidr]
  }

  ingress {
    description = "DNS TCP from WireGuard peers"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [local.wireguard_cidr]
  }

  ingress {
    description = "Health check from VPC"
    from_port   = 31000
    to_port     = 31000
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  dynamic "ingress" {
    for_each = local.reverse_proxy_routes
    content {
      description     = "${ingress.key} via reverse proxy"
      from_port       = ingress.value.port
      to_port         = ingress.value.port
      protocol        = "tcp"
      security_groups = [aws_security_group.reverse_proxy_service[ingress.key].id]
    }
  }

  ingress {
    description     = "All TCP from VPN client Lambdas"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.vpn_client.id]
  }

  ingress {
    description = "Komodo API from private subnets (middlebox routing requires CIDR, not SG ref)"
    from_port   = 30160
    to_port     = 30160
    protocol    = "tcp"
    cidr_blocks = [local.private_subnet_cidr, local.private_subnet_cidr_b]
  }

  ingress {
    description = "TrueNAS Postgres from private subnets (middlebox routing requires CIDR, not SG ref)"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [local.private_subnet_cidr, local.private_subnet_cidr_b]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = [
      "::/0"
    ]
  }

  tags = {
    Name       = "${local.prefix}-sg"
    "sg:role"  = "wireguard"
    "sg:scope" = "truenas"
  }
}
