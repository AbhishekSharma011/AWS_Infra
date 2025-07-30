provider "aws" {
  region = "eu-west-1"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "my-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = false
  reuse_nat_ips      = true
  external_nat_ip_ids = aws_eip.nat[*].id

  enable_vpn_gateway = false

  tags = {
    Terraform   = "true"
    Environment = "stg"
  }
}

resource "aws_eip" "nat" {
  count = 3

  
  tags = {
    Name = "nat-eip-${count.index}"
  }
}

resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow SSH inbound traffic and all outbound"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_ssh"
  }
}

module "ec2_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"

  name = "single-instance"

  instance_type = "t2.micro"
  key_name      = "user1"
  monitoring    = true
  subnet_id     = module.vpc.private_subnets[1]

  vpc_security_group_ids = [aws_security_group.allow_ssh.id]

  tags = {
    Terraform   = "true"
    Environment = "stg"
  }
}

module "db" {
  source = "terraform-aws-modules/rds/aws"

  identifier        = "demodb"
  engine            = "mysql"
  engine_version    = "5.7"
  instance_class    = "db.t3a.large"
  allocated_storage = 20
  db_name           = "demodb"
  username          = "user"
  password          = "YourSecurePassword123"
  port              = "3306"

  vpc_security_group_ids = [aws_security_group.allow_ssh.id]

  maintenance_window = "Mon:00:00-Mon:03:00"
  backup_window      = "03:00-06:00"

  iam_database_authentication_enabled = true

  monitoring_interval    = 30
  monitoring_role_name   = "MyRDSMonitoringRole"
  create_monitoring_role = true

  create_db_subnet_group = true
  subnet_ids             = module.vpc.private_subnets

  family                = "mysql5.7"
  major_engine_version  = "5.7"
  deletion_protection   = true

  parameters = [
    {
      name  = "character_set_client"
      value = "utf8mb4"
    },
    {
      name  = "character_set_server"
      value = "utf8mb4"
    }
  ]

  options = [
    {
      option_name = "MARIADB_AUDIT_PLUGIN"

      option_settings = [
        {
          name  = "SERVER_AUDIT_EVENTS"
          value = "CONNECT"
        },
        {
          name  = "SERVER_AUDIT_FILE_ROTATIONS"
          value = "37"
        },
      ]
    },
  ]

  tags = {
    Owner       = "user"
    Environment = "dev"
  }
}

resource "aws_network_acl" "main_nacl" {
  vpc_id = module.vpc.vpc_id

  subnet_ids = module.vpc.public_subnets

  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name = "main-nacl"
  }
}
