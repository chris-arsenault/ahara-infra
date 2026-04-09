# ── Diagnostic Bastion ──────────────────────────────────────
# Permanent instance in the private subnet with the ahara-lambda
# security group. Replicates the exact network position of VPC Lambdas
# for connectivity debugging.
#
# Auto-stops 60 minutes after each boot (systemd timer).
# No compute cost while stopped; ~$0.10/mo for 8GB gp3 EBS.
#
# Start:    aws ec2 start-instances --instance-ids <id>
# Connect:  aws ssm start-session --target <id>
# Test:     nc -zv 192.168.66.3 5432
#           psql -h 192.168.66.3 -U <user> -d postgres
#           traceroute 192.168.66.3

data "aws_ssm_parameter" "al2023_ami_bastion" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
}

resource "aws_iam_role" "bastion" {
  name_prefix        = "${local.prefix}-bastion-"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_instance_profile" "bastion" {
  name_prefix = "${local.prefix}-bastion-"
  role        = aws_iam_role.bastion.name
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_instance" "bastion" {
  ami                                  = data.aws_ssm_parameter.al2023_ami_bastion.value
  instance_type                        = "t3.micro"
  subnet_id                            = aws_subnet.private_b.id
  vpc_security_group_ids               = [aws_security_group.ahara_lambda.id]
  iam_instance_profile                 = aws_iam_instance_profile.bastion.name
  instance_initiated_shutdown_behavior = "stop"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    encrypted   = true
    volume_size = 8
    volume_type = "gp3"
  }

  user_data = <<-USERDATA
    #!/bin/bash
    set -euxo pipefail
    dnf -y install postgresql16 nmap-ncat traceroute

    # Auto-shutdown service: stops the instance 60 minutes after each boot
    cat > /etc/systemd/system/auto-shutdown.service <<'EOF'
    [Unit]
    Description=Auto-shutdown 60 minutes after boot
    After=network.target

    [Service]
    Type=oneshot
    ExecStart=/usr/sbin/shutdown -h +60

    [Install]
    WantedBy=multi-user.target
    EOF

    systemctl daemon-reload
    systemctl enable --now auto-shutdown.service
  USERDATA

  tags = {
    Name = "${local.prefix}-lambda-bastion"
  }
}

output "bastion_instance_id" {
  description = "Instance ID for SSM session (aws ssm start-session --target <id>)"
  value       = aws_instance.bastion.id
}
