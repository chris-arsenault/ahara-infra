resource "aws_vpc" "this" {
  cidr_block           = local.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name       = "${local.prefix}-vpc"
    "vpc:role" = "ahara"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.prefix}-vgw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnet_cidr
  availability_zone       = local.az
  map_public_ip_on_launch = true

  tags = {
    Name            = "${local.prefix}-public"
    "subnet:access" = "public"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnet_cidr_b
  availability_zone       = local.az_secondary
  map_public_ip_on_launch = true

  tags = {
    Name            = "${local.prefix}-public-b"
    "subnet:access" = "public"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_subnet_cidr
  availability_zone = local.az

  tags = {
    Name            = "${local.prefix}-private"
    "subnet:access" = "private"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_subnet_cidr_b
  availability_zone = local.az_secondary

  tags = {
    Name            = "${local.prefix}-private-b"
    "subnet:access" = "private"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${local.prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# Route from PRIVATE subnet to WG clients via the EC2 instance
resource "aws_route" "private_to_wg_via_lan" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = local.home_lan_cidr
  network_interface_id   = module.wireguard.primary_network_interface_id
}

resource "aws_route" "private_to_wg_via_wg" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = local.wireguard_cidr
  network_interface_id   = module.wireguard.primary_network_interface_id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${local.prefix}-private-rt" }
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b_assoc" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route" "private_default_via_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = module.nat.primary_network_interface_id
}
